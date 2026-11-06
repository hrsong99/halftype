import Foundation
import ItdaCore
import ItdaEngine
import TwoSet

/// One message's typing against the engine. All state is behind `lock`: keys come from this thread, results from the engine's.
final class Replay: @unchecked Sendable {
    struct Config {
        var timed: Bool, threshold: Double, composing: Composing
        var maxKeys: Int, stride: Int, speed: Double, seed: UInt64
    }

    /// `keys`, the product: withhold the possibly composing syllable and force the next output to fit its keystrokes.
    /// `withhold`: the same without forcing. `send`: treat it as committed text.
    enum Composing: String { case keys, withhold, send }

    /// One request, kept whatever becomes of it. Guarded by `lock`.
    private final class Request: @unchecked Sendable {
        let id: Int, message: Int, key: Int, arrival = Date()
        let anchor: String, requested: String, field: Field, truth: String, fragment: String
        var firstToken: Date?, firstDisplayable: Date?, shown: Date?, end: Date?
        var last: Suggestion?
        var suggestion = ""

        init(id: Int, message: Int, key: Int, anchor: String, requested: String, field: Field, truth: String, fragment: String) {
            (self.id, self.message, self.key) = (id, message, key)
            (self.anchor, self.requested, self.field, self.truth, self.fragment) = (anchor, requested, field, truth, fragment)
        }
    }

    private let engine: Engine, config: Config, out: FileHandle
    private let lock = NSLock()
    private let idle = DispatchSemaphore(value: 0)
    private var rng: SplitMix
    private var nextId = 0
    private var current: Request?
    private var visible = false

    init(engine: Engine, config: Config, out: FileHandle) {
        (self.engine, self.config, self.out) = (engine, config, out)
        rng = SplitMix(state: config.seed)
    }

    func close() { try? out.close() }

    func message(_ index: Int, context: String, text: String, start: Int) {
        let text = text.precomposedStringWithCanonicalMapping, context = context.precomposedStringWithCanonicalMapping
        let opening = String(text.prefix(start))
        var states = TwoSet.trace(String(text.dropFirst(start)), start: opening).map(\.field)
        states.removeLast()  // the same text as the state before, committed; nothing is left to predict after it
        states = Array(states.prefix(config.maxKeys))
        lock.withLock { (current, visible) = (nil, false) }
        for (key, field) in states.enumerated() where key % config.stride == 0 {
            if config.timed {
                let delay = sampleDelayMs(using: &rng) / config.speed
                Thread.sleep(forTimeInterval: delay / 1000)
                press(index, key, field, context, text, delay: delay)
            } else {
                press(index, key, field, context, text, delay: 0)
                idle.wait()
            }
        }
        if config.timed {
            Thread.sleep(forTimeInterval: sampleDelayMs(using: &rng) / config.speed / 1000)
            lock.withLock { logVisible() }
        }
        engine.cancel()
    }

    private var lastKey: [String: Any] = [:]

    private func press(_ message: Int, _ key: Int, _ field: Field, _ context: String, _ text: String, delay: Double) {
        lock.lock()
        defer { lock.unlock() }
        if config.timed { logVisible() }
        let truth = String(text.dropFirst(field.committed.count))
        lastKey = ["t": "key", "msg": message, "key": key, "dt_ms": delay, "kind": kind(field, truth), "len": field.before.count, "truth_word": truthWordKeys(field, truth)]
        lastField = field
        lastTruth = truth
        if config.timed, visible, let c = current, Follow.check(anchor: c.anchor, suggestion: c.suggestion, field: field) != nil {
            lastKey["follow"] = true
            lastKey["req"] = c.id
            return
        }
        lastKey["follow"] = false
        visible = false
        let requested = config.composing == .send ? field.before : field.committed
        var prompt = Prompt.make(context: context, field: field)
        if config.composing != .keys { prompt = Prompt.make(context: context, before: requested) }
        nextId += 1
        let id = nextId
        lastKey["req"] = id
        let request = Request(id: id, message: message, key: key, anchor: field.committed, requested: requested,
                              field: field, truth: truth, fragment: prompt.fragment)
        current = request
        engine.suggest(prefix: prompt.prefix, fragment: prompt.fragment, composing: prompt.composing, onResult: { [self] suggestion in
            lock.withLock {
                let now = Date()
                if request.firstToken == nil { request.firstToken = now }
                guard let suggestion else { return }
                request.last = suggestion
                let full = Word.withoutTrailingSpaces(request.requested) + suggestion.text
                request.suggestion = String(full.dropFirst(Word.withoutTrailingSpaces(request.anchor).count))
                guard let gate = suggestion.gate, !suggestion.text.isEmpty,
                      Follow.check(anchor: request.anchor, suggestion: request.suggestion, field: request.field) != nil else { return }
                if request.firstDisplayable == nil { request.firstDisplayable = now }
                if gate >= config.threshold, current === request, !visible {
                    visible = true
                    request.shown = now
                }
            }
        }, onFinish: { [self] stats in
            lock.withLock {
                request.end = Date()
                logRequest(request, stats)
            }
            if !config.timed { idle.signal() }
        })
    }

    private var lastField = Field(before: "")
    private var lastTruth = ""

    /// Scores what is on screen as the next key lands, or as the replay moves on.
    private func logVisible() {
        guard !lastKey.isEmpty else { return }
        var row = lastKey
        row["visible"] = false
        if visible, let c = current, let ghost = Follow.check(anchor: c.anchor, suggestion: c.suggestion, field: lastField) {
            row["visible"] = true
            row["needs_replace"] = ghost.needsReplace
            row["ghost"] = ghost.composing + ghost.remainder
            row.merge(fields(score(ghost, typed: lastField.composing, rest: lastTruth))) { $1 }
        }
        write(row)
        lastKey = [:]
    }

    private func logRequest(_ r: Request, _ stats: RequestStats) {
        var row: [String: Any] = [
            "t": "req", "id": r.id, "msg": r.message, "key": r.key, "kind": kind(r.field, r.truth), "fragment": r.fragment,
            "prompt_tokens": stats.promptTokens, "prefilled": stats.prefilled, "generated": stats.generated,
            "cancelled": stats.cancelled, "end_ms": ms(r.end, r.arrival) as Any, "first_token_ms": ms(r.firstToken, r.arrival) as Any,
            "first_displayable_ms": ms(r.firstDisplayable, r.arrival) as Any, "shown_ms": ms(r.shown, r.arrival) as Any,
        ]
        if let s = r.last {
            row["text"] = s.text
            row["gate"] = s.gate as Any
            row["gate_plain"] = plainGate(s, r.fragment) as Any
            row["tokens"] = zip(s.tokens, s.plain).map { t, plain in
                ["hex": t.bytes.map { String(format: "%02x", $0) }.joined(), "lp": t.logprob, "plain": plain, "special": t.special] as [String: Any]
            }
            row["fits"] = false
            if let ghost = Follow.check(anchor: r.anchor, suggestion: r.suggestion, field: r.field) {
                row["fits"] = true
                row["needs_replace"] = ghost.needsReplace
                row["ghost"] = ghost.composing + ghost.remainder
                row.merge(fields(score(ghost, typed: r.field.composing, rest: r.truth))) { $1 }
            }
        }
        write(row)
    }

    private func write(_ row: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) else { return }
        out.write(data + Data("\n".utf8))
    }
}

private func ms(_ date: Date?, _ from: Date) -> Double? { date.map { $0.timeIntervalSince(from) * 1000 } }

private func plainGate(_ s: Suggestion, _ fragment: String) -> Double? {
    let tokens = zip(s.tokens, s.plain).map { Token(bytes: $0.bytes, logprob: $1, special: $0.special) }
    return Gate.firstWord(tokens, fragment: fragment)
}

private func fields(_ s: Score) -> [String: Any] {
    ["useful": s.useful, "tab_chars": s.tabChars, "tab_keys": s.tabKeys, "words_chars": s.wordsChars, "words_keys": s.wordsKeys,
     "all_chars": s.allChars, "all_keys": s.allKeys]
}

/// `none`: nothing may be composing. `final`: the last syllable is already what will stay. `changing`: it will still change.
private func kind(_ field: Field, _ truth: String) -> String {
    guard !field.composing.isEmpty else { return "none" }
    return truth.first.map(String.init) == field.composing ? "final" : "changing"
}

/// Keys left to the end of the true next word, for a Tab user's walk over the trace.
private func truthWordKeys(_ field: Field, _ truth: String) -> Int {
    let word = truth[..<Word.firstEnd(truth)]
    return max(Hangul.keys(String(word)).count - Hangul.keys(field.composing).count, 0)
}
