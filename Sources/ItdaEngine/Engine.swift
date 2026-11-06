import Foundation
import ItdaCore
import Synchronization
import llama

public struct Suggestion: Sendable {
    /// `Stop.cut`'s text so far, after the fragment.
    public var text: String
    /// Log P(first word | fits the fragment). Nil until the first word is finished, as it can only fall until then.
    public var gate: Double?
    public var tokens: [Token]
    /// Each token's log probability over the whole vocabulary, for comparing gates offline.
    public var plain: [Double]
    public var done: Bool
}

/// What one request cost, cancelled or not. `prefilled` counts tokens decoded before the first generated one.
public struct RequestStats: Sendable {
    public var promptTokens = 0, prefilled = 0, generated = 0
    public var cancelled = false
    public init() {}
}

public enum EngineError: Error { case load(String) }

/// llama.cpp in-process: greedy, fragment forced at the logits, latest request wins, one serial queue.
public final class Engine: @unchecked Sendable {
    /// `Prompt.windowChars` is 1200, and text runs below one token per character; the rest is room for the output.
    static let contextTokens: UInt32 = 1400
    /// Prefill decodes in batches this small, as a decode can't be interrupted on Metal.
    static let prefillBatch: Int32 = 32
    static let checkpointTail = 4

    private let path: String
    private let stopBelow: Double?
    private let queue = DispatchQueue(label: "itda.engine", qos: .userInteractive)
    private let latest = Atomic<Int>(0)
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: Vocab?
    /// The tokens in the model's memory right now.
    private var cached: [llama_token] = []
    /// False when the memory can't drop a suffix (recurrent state, as in Qwen 3.5). `checkpoint` then stands in for it.
    public private(set) var canTrim = true
    /// The recurrent state a few tokens before the last prompt's end, and how many tokens that is.
    private var checkpoint: (count: Int, state: [UInt8])?
    public private(set) var coldStartSeconds = 0.0

    /// `stopBelow` ends a request as soon as its first word falls below the gate. Nil keeps generating, for offline replay.
    public init(modelPath: String, stopBelow: Double? = Gate.threshold) throws {
        path = modelPath
        self.stopBelow = stopBelow
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
        try queue.sync { try load() }
    }

    deinit { unload() }

    /// `onResult` runs on the engine's queue after each token, and with nil if there is nothing to suggest. A cancelled
    /// request says nothing more. `onFinish`, if given, always runs last.
    public func suggest(prefix: String, fragment: String, composing: String = "", onResult: @escaping @Sendable (Suggestion?) -> Void,
                        onFinish: (@Sendable (RequestStats) -> Void)? = nil) {
        let id = latest.add(1, ordering: .sequentiallyConsistent).newValue
        queue.async { [self] in
            var stats = RequestStats()
            run(id, prefix, fragment, composing, onResult, &stats)
            stats.cancelled = stats.cancelled || isStale(id)
            onFinish?(stats)
        }
    }

    public func cancel() { latest.add(1, ordering: .sequentiallyConsistent) }

    /// Frees the model; the next `suggest` loads it again. Call it before the process exits: ggml's Metal device asserts
    /// at exit if a model is still loaded.
    public func unload() {
        cancel()
        queue.sync {
            if let ctx { llama_free(ctx) }
            if let model { llama_model_free(model) }
            (ctx, model, vocab, cached, checkpoint) = (nil, nil, nil, [], nil)
        }
    }

    private func isStale(_ id: Int) -> Bool { latest.load(ordering: .sequentiallyConsistent) != id }

    private func load() throws {
        let start = Date()
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = -1
        guard let model = llama_model_load_from_file(path, modelParams) else { throw EngineError.load(path) }
        var params = llama_context_default_params()
        params.n_ctx = Self.contextTokens
        params.n_batch = UInt32(Self.prefillBatch)
        params.n_ubatch = UInt32(Self.prefillBatch)
        params.swa_full = true
        params.no_perf = true
        guard let ctx = llama_init_from_model(model, params) else {
            llama_model_free(model)
            throw EngineError.load(path)
        }
        (self.model, self.ctx) = (model, ctx)
        vocab = Vocab(llama_model_get_vocab(model))
        canTrim = !llama_model_is_recurrent(model) && !llama_model_is_hybrid(model)
        coldStartSeconds = Date().timeIntervalSince(start)
    }

    private func run(_ id: Int, _ prefix: String, _ fragment: String, _ composing: String, _ onResult: (Suggestion?) -> Void,
                     _ stats: inout RequestStats) {
        guard !isStale(id) else { stats.cancelled = true; return }
        if ctx == nil { try? load() }
        guard let ctx, let vocab, !prefix.isEmpty else { return onResult(nil) }

        var prompt = vocab.tokenize(prefix)
        // shortcut: past the context we keep the tail, losing the cached head; `contextTokens` is sized so this is rare.
        let room = Int(Self.contextTokens) - fragment.utf8.count - Stop.maxTokens - 2
        if prompt.count > room { prompt.removeFirst(prompt.count - room) }
        stats.promptTokens = prompt.count
        guard prefill(prompt, ctx, id, &stats) else { return }

        var need = Constraint(fragment: fragment, composing: composing)
        var suggestion = Suggestion(text: "", tokens: [], plain: [], done: false)
        var shown = ""
        while true {
            let logits = UnsafeBufferPointer(start: llama_get_logits_ith(ctx, -1), count: vocab.count)
            guard let pick = vocab.pick(logits, need: need) else { return onResult(nil) }
            let piece = vocab.piece(pick.token)
            need.consume(piece)
            suggestion.tokens.append(Token(bytes: Array(piece), logprob: pick.logprob, special: pick.isEnd))
            suggestion.plain.append(pick.plain)
            stats.generated += 1

            let cut = Stop.cut(suggestion.tokens, fragment: fragment)
            let finished = cut.done || (!cut.text.isEmpty && Word.firstEnd(cut.text) != cut.text.endIndex)
            suggestion.text = cut.text
            suggestion.gate = finished ? Gate.firstWord(suggestion.tokens, fragment: fragment) : nil
            suggestion.done = cut.done || (stopBelow != nil && suggestion.gate.map { $0 < stopBelow! } == true)
            guard !isStale(id) else { stats.cancelled = true; return }
            if suggestion.done { return onResult(cut.text.isEmpty ? nil : suggestion) }
            if cut.text != shown { onResult(suggestion); shown = cut.text }

            var next = pick.token
            guard llama_decode(ctx, llama_batch_get_one(&next, 1)) == 0 else { return reset(ctx, onResult) }
            cached.append(next)
            guard !isStale(id) else { stats.cancelled = true; return }
        }
    }

    /// Brings the memory to `prompt` by decoding only what differs. False if cancelled or failed; what was decoded stays
    /// usable by the next request. The last token is always decoded, for its logits.
    private func prefill(_ prompt: [llama_token], _ ctx: OpaquePointer, _ id: Int, _ stats: inout RequestStats) -> Bool {
        var keep = min(zip(cached, prompt).prefix { $0 == $1 }.count, prompt.count - 1)
        if keep < cached.count {
            keep = trim(to: keep, ctx)
            cached.removeLast(cached.count - keep)
        }
        // Re-tokenising can change a prompt's last tokens as a word grows, so the checkpoint sits this far back.
        let saveAt = canTrim ? -1 : prompt.count - Self.checkpointTail
        while keep < prompt.count {
            guard !isStale(id) else { stats.cancelled = true; return false }
            let end = min(keep + Int(Self.prefillBatch), keep < saveAt ? saveAt : prompt.count)
            var batch = Array(prompt[keep..<end])
            let count = Int32(batch.count)
            guard llama_decode(ctx, llama_batch_get_one(&batch, count)) == 0 else {
                llama_memory_clear(llama_get_memory(ctx), true)
                (cached, checkpoint) = ([], nil)
                return false
            }
            cached += batch
            stats.prefilled += batch.count
            keep = end
            if keep == saveAt { save(ctx, count: keep) }
        }
        return true
    }

    /// Drops the memory past `count` tokens and returns how many are left, which is fewer if the model can't do just that.
    private func trim(to count: Int, _ ctx: OpaquePointer) -> Int {
        let memory = llama_get_memory(ctx)
        if canTrim {
            if llama_memory_seq_rm(memory, 0, llama_pos(count), -1) { return count }
            canTrim = false
        }
        if let checkpoint, checkpoint.count <= count, checkpoint.count > 0,
           llama_state_seq_set_data_ext(ctx, checkpoint.state, checkpoint.state.count, 0, flags) > 0,
           llama_memory_seq_rm(memory, 0, llama_pos(checkpoint.count), -1) {
            return checkpoint.count
        }
        llama_memory_clear(memory, true)
        checkpoint = nil
        return 0
    }

    private let flags = llama_state_seq_flags(LLAMA_STATE_SEQ_FLAGS_PARTIAL_ONLY)

    private func save(_ ctx: OpaquePointer, count: Int) {
        var state = [UInt8](repeating: 0, count: llama_state_seq_get_size_ext(ctx, 0, flags))
        let written = llama_state_seq_get_data_ext(ctx, &state, state.count, 0, flags)
        checkpoint = written > 0 ? (count, state) : nil
    }

    private func reset(_ ctx: OpaquePointer, _ onResult: (Suggestion?) -> Void) {
        llama_memory_clear(llama_get_memory(ctx), true)
        (cached, checkpoint) = ([], nil)
        onResult(nil)
    }
}

/// Every token's bytes, looked up once, so the fragment can be enforced in bytes on the logits.
final class Vocab {
    let raw: OpaquePointer
    let count: Int
    private let bytes: [UInt8]
    private let starts: [Int32]
    private let allowed: [Bool]
    private let ends: [Bool]
    private var keyStarts: [Int32] = [], keyCodes: [UInt16] = []

    init(_ vocab: OpaquePointer?) {
        raw = vocab!
        count = Int(llama_vocab_n_tokens(raw))
        var bytes: [UInt8] = [], starts: [Int32] = [0], allowed = [Bool](repeating: false, count: count), ends = allowed
        var buffer = [CChar](repeating: 0, count: 512)
        let hidden = LLAMA_TOKEN_ATTR_CONTROL.rawValue | LLAMA_TOKEN_ATTR_UNKNOWN.rawValue | LLAMA_TOKEN_ATTR_UNUSED.rawValue
        for t in 0..<count {
            let token = llama_token(t)
            let n = Int(llama_token_to_piece(raw, token, &buffer, 512, 0, false))
            if n > 0 { buffer[..<n].withUnsafeBytes { bytes.append(contentsOf: $0) } }
            starts.append(Int32(bytes.count))
            ends[t] = llama_vocab_is_eog(raw, token)
            let attr = llama_vocab_get_attr(raw, token).rawValue
            allowed[t] = ends[t] || (n > 0 && attr != LLAMA_TOKEN_ATTR_UNDEFINED.rawValue && attr & hidden == 0)
        }
        (self.bytes, self.starts, self.allowed, self.ends) = (bytes, starts, allowed, ends)
    }

    func tokenize(_ text: String) -> [llama_token] {
        let utf8 = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8) + 8)
        let n = llama_tokenize(raw, text, utf8, &tokens, Int32(tokens.count), true, false)
        return Array(tokens.prefix(Int(max(n, 0))))
    }

    func piece(_ token: llama_token) -> ArraySlice<UInt8> { bytes[Int(starts[Int(token)])..<Int(starts[Int(token) + 1])] }

    /// Greedy over the allowed tokens, those that `need` lets through.
    func pick(_ logits: UnsafeBufferPointer<Float>, need: Constraint) -> Pick? {
        if !need.keys.isEmpty, keyStarts.isEmpty { indexKeys() }
        return Pick.best(logits, allowed: { [self] t in
            guard allowed[t] else { return false }
            if need.isDone { return true }
            let s = Int(starts[t]), e = Int(starts[t + 1])
            guard s < e else { return false }
            if let wanted = need.bytes.first {
                guard bytes[s] == wanted, Vocab.agrees(bytes[s..<e], need.bytes) else { return false }
                return e - s <= need.bytes.count || need.agrees(tail: bytes[(s + need.bytes.count)..<e])
            }
            if !need.held.isEmpty { return need.agrees(tail: bytes[s..<e]) }
            let codes = keyCodes[Int(keyStarts[t])..<Int(keyStarts[t + 1])]
            // A token with no whole character yet may still begin one.
            if codes.isEmpty { return bytes[s] >= 0xC0 }
            return codes.prefix(need.keys.count).elementsEqual(need.keys.prefix(codes.count))
        }, isEnd: { [self] in ends[$0] })
    }

    /// Each token's 2-set keystrokes, up to its first incomplete character. Only Korean typing needs them, so built on first use.
    private func indexKeys() {
        keyStarts = [0]
        for t in 0..<count {
            let piece = bytes[Int(starts[t])..<Int(starts[t + 1])]
            keyCodes += Constraint.keyCodes(piece).codes
            keyStarts.append(Int32(keyCodes.count))
        }
    }
}

/// What the output must still match: the fragment's bytes exactly, then the keystrokes of what may be composing.
/// 하 lets through 하, 한 or 함 alike, so the model still chooses, and the gate is conditional on the keys typed.
struct Constraint {
    var bytes: ArraySlice<UInt8>
    var keys: ArraySlice<UInt16>
    /// The start of a character that a token left unfinished.
    var held: [UInt8] = []

    init(fragment: String, composing: String) {
        bytes = [UInt8](fragment.utf8)[...]
        keys = Array(Hangul.keys(composing).utf16)[...]
    }

    var isDone: Bool { bytes.isEmpty && keys.isEmpty }

    /// Keystrokes of the whole characters in `piece`, and how many bytes at its end don't decode yet.
    static func keyCodes(_ piece: some Collection<UInt8>) -> (codes: [UInt16], rest: Int) {
        let raw = Array(piece)
        for rest in 0...min(3, raw.count) {
            if let text = String(validating: raw.dropLast(rest), as: UTF8.self) { return (Array(Hangul.keys(text).utf16), rest) }
        }
        return ([], raw.count)
    }

    func agrees(tail: some Collection<UInt8>) -> Bool {
        if keys.isEmpty { return true }
        let codes = Self.keyCodes(held + tail).codes
        return codes.prefix(keys.count).elementsEqual(keys.prefix(codes.count))
    }

    mutating func consume(_ piece: ArraySlice<UInt8>) {
        let forced = min(bytes.count, piece.count)
        bytes = bytes.dropFirst(forced)
        guard bytes.isEmpty, !keys.isEmpty else { return }
        let joined = held + piece.dropFirst(forced)
        let (codes, rest) = Self.keyCodes(joined)
        keys = keys.dropFirst(codes.count)
        held = keys.isEmpty ? [] : Array(joined.suffix(rest))
    }
}

extension Vocab {
    /// In bytes, as a token can end inside a Hangul character.
    static func agrees(_ piece: ArraySlice<UInt8>, _ need: ArraySlice<UInt8>) -> Bool {
        piece.prefix(need.count).elementsEqual(need.prefix(piece.count))
    }
}

struct Pick: Equatable {
    var token: llama_token
    /// Log probability over the allowed tokens, and over the whole vocabulary.
    var logprob: Double, plain: Double
    var isEnd: Bool

    static func best(_ logits: UnsafeBufferPointer<Float>, allowed: (Int) -> Bool, isEnd: (Int) -> Bool) -> Pick? {
        var best = -1, top = -Float.infinity, overallTop = -Float.infinity
        var mask = [Bool](repeating: false, count: logits.count)
        for t in 0..<logits.count {
            overallTop = max(overallTop, logits[t])
            guard allowed(t) else { continue }
            mask[t] = true
            if logits[t] > top { (best, top) = (t, logits[t]) }
        }
        guard best >= 0 else { return nil }
        // log-sum-exp, relative to the top, so nothing over- or underflows.
        var allowedMass = 0.0, totalMass = 0.0
        for t in 0..<logits.count {
            totalMass += exp(Double(logits[t] - overallTop))
            if mask[t] { allowedMass += exp(Double(logits[t] - top)) }
        }
        return Pick(token: llama_token(best), logprob: -log(allowedMass),
                    plain: Double(top - overallTop) - log(totalMass), isEnd: isEnd(best))
    }
}
