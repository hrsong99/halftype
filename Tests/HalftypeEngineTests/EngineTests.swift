import Foundation
import HalftypeCore
import llama
import Synchronization
import Testing
@testable import HalftypeEngine

// Set HALFTYPE_MODEL to a GGUF path to run the tests marked `needsModel`.
private let modelPath = ProcessInfo.processInfo.environment["HALFTYPE_MODEL"]
private let needsModel = Testing.ConditionTrait.enabled(if: modelPath != nil, "needs HALFTYPE_MODEL")

@Test func bytesAgreeAcrossASplitHangulCharacter() {
    let need = Array("한".utf8)[...]  // ED 95 9C
    #expect(Vocab.agrees([0xED], need))
    #expect(Vocab.agrees([0xED, 0x95, 0x9C, 0xEA], need))
    #expect(!Vocab.agrees([0xED, 0x96], need))
    #expect(!Vocab.agrees([0xEA], need))
}

@Test func renormalisesExactlyOverTheAllowedTokens() throws {
    let logits: [Float] = [log(0.5), log(0.3), log(0.2)]
    let pick = try #require(logits.withUnsafeBufferPointer { Pick.best($0, allowed: { $0 != 0 }, isEnd: { _ in false }) })
    #expect(pick.token == 1)
    #expect(abs(pick.logprob - log(0.3 / 0.5)) < 1e-6)
}

@Test func nothingAllowedIsNoPick() {
    let logits: [Float] = [0, 0]
    #expect(logits.withUnsafeBufferPointer { Pick.best($0, allowed: { _ in false }, isEnd: { _ in false }) } == nil)
}

private final class Box: @unchecked Sendable { var last: Suggestion? }

private func run(_ engine: Engine, _ prefix: String, _ fragment: String, composing: String = "") -> Suggestion? {
    let box = Box()
    engine.suggest(prefix: prefix, fragment: fragment, composing: composing, onResult: { box.last = $0 ?? box.last })
    engine.finish()
    return box.last
}

private let long = String(repeating: "The river runs past the old mill and on toward the sea. ", count: 8) + "We"

@Test(needsModel) func forcesTheFragmentAndNeverLetsAControlTokenThrough() throws {
    let engine = try Engine(modelPath: modelPath!)
    defer { engine.unload() }
    for (prefix, fragment) in [(long, " sho"), ("오늘 날씨가", " 정"), ("Hello my", " fr")] {
        let tokens = try #require(run(engine, prefix, fragment)).tokens
        let bytes = tokens.flatMap(\.bytes)
        #expect(bytes.starts(with: Array(fragment.utf8)))
        #expect(tokens.allSatisfy { $0.special || !$0.bytes.isEmpty })
    }
}

@Test(needsModel) func decodesOnlyTheDifference() throws {
    let engine = try Engine(modelPath: modelPath!)
    defer { engine.unload() }
    _ = run(engine, long, " sho")
    #expect(engine.prefilled > 50)
    _ = run(engine, long, " shou")
    #expect(engine.prefilled <= Engine.checkpointTail + 1)
    _ = run(engine, long + " should", " g")
    #expect(engine.prefilled <= Engine.checkpointTail + 3)
}

/// The reused memory, whether trimmed or restored from a checkpoint, must give what a fresh decode gives.
@Test(needsModel) func reuseMatchesAFreshDecode() throws {
    let engine = try Engine(modelPath: modelPath!)
    _ = run(engine, long, " sho")
    let reused = try #require(run(engine, long, " shou"))
    engine.unload()
    let fresh = try #require(run(engine, long, " shou"))
    engine.unload()
    #expect(reused.text == fresh.text)
    #expect(reused.tokens.count == fresh.tokens.count)
    #expect(zip(reused.tokens, fresh.tokens).allSatisfy { abs($0.logprob - $1.logprob) < 0.05 })
}

@Test(needsModel) func cancelInterruptsPrefillAndTheNextRequestStillWorks() throws {
    let engine = try Engine(modelPath: modelPath!)
    defer { engine.unload() }
    let cancelled = Box()
    engine.suggest(prefix: long + long + long, fragment: "", composing: "", onResult: { cancelled.last = $0 })
    Thread.sleep(forTimeInterval: 0.02)
    engine.cancel()
    engine.finish()
    #expect(cancelled.last == nil)
    #expect(run(engine, long, " sho") != nil)
}

@Test(needsModel) func latestRequestWins() throws {
    let engine = try Engine(modelPath: modelPath!)
    defer { engine.unload() }
    let stale = Box()
    engine.suggest(prefix: long, fragment: "", composing: "", onResult: { stale.last = $0 })
    #expect(run(engine, "Hello my", " fr") != nil)
    #expect(stale.last == nil)
}

@Test func constraintFollowsKeystrokesAcrossASplitCharacter() {
    var need = Constraint(fragment: " 안", composing: "달")
    #expect(need.agrees(tail: Array("다".utf8)))
    #expect(need.agrees(tail: Array("달".utf8)))
    #expect(need.agrees(tail: Array("다라".utf8)))
    #expect(!need.agrees(tail: Array("나".utf8)))
    need.consume(Array(" 안".utf8)[...])
    #expect(need.bytes.isEmpty)
    let da = Array("다".utf8)
    need.consume(da[..<2])  // the token stops inside 다
    #expect(!need.isDone)
    #expect(need.agrees(tail: [da[2]]))
    need.consume(da[2...])
    #expect(need.agrees(tail: Array("라".utf8)))
    #expect(!need.agrees(tail: Array("가".utf8)))
    need.consume(Array("라".utf8)[...])
    #expect(need.isDone)
}

@Test func aSpaceBeforeTheComposingSyllableIsPartOfWhatMustFit() {
    let need = Constraint(fragment: "", composing: " 날")
    #expect(need.agrees(tail: Array(" 날씨".utf8)))
    #expect(!need.agrees(tail: Array("날씨".utf8)))
}

@Test(needsModel) func composingForcesKeystrokesNotBytes() throws {
    let engine = try Engine(modelPath: modelPath!)
    defer { engine.unload() }
    let text = try #require(run(engine, "오늘 날씨가 정말 좋아서 공원에", " 산책", composing: "하")).text
    #expect(Hangul.fits(composing: "하", suggestion: text))
}

@Test func anImpossibleStartOfACharacterIsRejected() throws {
    let han = Array("한".utf8)  // ED 95 9C
    let need = Constraint(fragment: "", composing: "하")
    #expect(!need.agrees(tail: [0xEA]))  // Starts no syllable with ㅎ.
    #expect(need.agrees(tail: [0xED]))
    #expect(need.agrees(tail: han[..<2]))
    #expect(!need.agrees(tail: [0xED, 0x80]))  // 퀀's neighbourhood, ㅋ.
    #expect(need.agrees(tail: han))
    #expect(need.agrees(tail: [0xE3, 0x85]))  // The lone jamo ㅎ is E3 85 8E.
    var held = need
    held.consume([0xED])
    #expect(held.agrees(tail: [0x95]))
    #expect(!held.agrees(tail: [0x80]))
    // Three tokens: the mask, and so the probability, leaves out the impossible one.
    let tokens: [[UInt8]] = [[0xEA], [0xED, 0x95], han]
    let logits: [Float] = [log(0.5), log(0.3), log(0.2)]
    let pick = try #require(logits.withUnsafeBufferPointer { Pick.best($0, allowed: { need.agrees(tail: tokens[$0]) }, isEnd: { _ in false }) })
    #expect(pick.token == 1)
    #expect(abs(pick.logprob - log(0.3 / 0.5)) < 1e-6)
}

@Test func aFragmentTooLongForTheContextIsNoRequest() {
    #expect(Engine.promptRoom(fragment: String(repeating: "a", count: 1000), composing: "") == nil)
    #expect(Engine.promptRoom(fragment: String(repeating: "한", count: 300), composing: "") == nil)
    #expect(Engine.promptRoom(fragment: " sho", composing: "하") == 900 - 4 - 3 - Stop.maxTokens - 2)
}

@Test func droppingTheLastOwnerDuringARequestEndsCleanly() {
    weak var weakEngine: Engine?
    let done = DispatchSemaphore(value: 0)
    do {
        // No model at this path, so the request ends in nil on the engine's queue, holding the last reference.
        let engine = Engine(unloaded: "/nonexistent.gguf")
        weakEngine = engine
        engine.suggest(prefix: "x", fragment: "", composing: "") { _ in usleep(50_000); done.signal() }
    }
    done.wait()
    for _ in 0..<100 where weakEngine != nil { usleep(10_000) }
    #expect(weakEngine == nil)
}

@Test(needsModel) func anAdapterThatWontLoadIsLeftOut() throws {
    let plain = try Engine(modelPath: modelPath!)
    let text = run(plain, "Hello my", " fr")?.text
    plain.unload()
    let engine = try Engine(modelPath: modelPath!, adapter: { _ in "/nonexistent.gguf" })
    defer { engine.unload() }
    #expect(run(engine, "Hello my", " fr")?.text == text)
}

@Test func aClosedEngineNeverLoadsAgain() {
    let loads = Atomic<Int>(0)
    // No model at this path, so each load that is tried fails and says so.
    let engine = Engine(unloaded: "/nonexistent.gguf") { loads.add(1, ordering: .relaxed) }
    engine.suggest(prefix: "x", fragment: "", composing: "") { _ in }
    engine.finish()
    #expect(loads.load(ordering: .relaxed) == 1)  // A request does try, or the rest proves nothing.
    engine.close()
    engine.suggest(prefix: "x", fragment: "", composing: "") { _ in }
    engine.finish()
    #expect(loads.load(ordering: .relaxed) == 1)
}

@Test func aPieceTooBigForTheBufferIsWrittenInFull() {
    let long = [CChar](repeating: 0x61, count: 600)
    var buffer = [CChar](repeating: 0, count: 512)
    // As llama.cpp does: the negative of the size it needs, if the buffer is short.
    let n = Vocab.piece(into: &buffer) { out, size in
        guard size >= 600 else { return -600 }
        for i in 0..<600 { out[i] = long[i] }
        return 600
    }
    #expect(n == 600 && Array(buffer[..<n]) == long)
}

private final class Flag: @unchecked Sendable { var set = false }

@Test func aModelThatCantLoadAgainSaysSoApartFromNoSuggestion() {
    let failed = Flag(), box = Box()
    let engine = Engine(unloaded: "/nowhere/gone.gguf") { failed.set = true }  // As after an idle unload, with the file since moved.
    engine.suggest(prefix: "Hello", fragment: "", composing: "", onResult: { box.last = $0 })
    engine.finish()
    #expect(failed.set && box.last == nil)
}

/// The index of each token's unfinished bytes, and `canBegin` remembered per step, must let through exactly what decoding every
/// piece again did, for every token, mid-syllable and not. Also prints how long a step takes each way.
@Test(needsModel) func theIndexedCheckLetsThroughWhatDecodingDid() throws {
    llama_backend_init()
    var params = llama_model_default_params()
    params.vocab_only = true
    let model = try #require(llama_model_load_from_file(modelPath!, params))
    defer { llama_model_free(model) }
    let vocab = Vocab(llama_model_get_vocab(model))
    var needs = ["ㅎ", "하", "한", "가", "값", "ㄱ", "안", "녕"].map { Constraint(fragment: "", composing: $0) }
    needs.append(Constraint(fragment: " h", composing: ""))
    var held = Constraint(fragment: "", composing: "한")
    held.consume([0xED][...])  // A token that ended inside 한's first byte.
    needs.append(held)
    for need in needs {
        var begins: [Int: Bool] = [:], wrong = 0
        let t0 = Date()
        let fast = (0..<vocab.count).map { vocab.allows($0, need, &begins) }
        let t1 = Date()
        let slow = (0..<vocab.count).map { vocab.allowsByDecoding($0, need) }
        let t2 = Date()
        for t in 0..<vocab.count where fast[t] != slow[t] { wrong += 1 }
        #expect(wrong == 0, "\(wrong) tokens differ for keys \(Array(need.keys)), held \(need.held)")
        print(String(format: "keys %@: %.1f ms indexed, %.1f ms decoding, %d allowed", "\(Array(need.keys))", t1.timeIntervalSince(t0) * 1000, t2.timeIntervalSince(t1) * 1000, fast.filter { $0 }.count))
    }
}

extension Vocab {
    /// The check as it was before the index of rests: decoding each piece again.
    func allowsByDecoding(_ t: Int, _ need: Constraint) -> Bool {
        guard allowed[t] else { return false }
        if need.isDone { return true }
        let s = Int(starts[t]), e = Int(starts[t + 1])
        guard s < e else { return false }
        if let wanted = need.bytes.first {
            guard bytes[s] == wanted, Vocab.agrees(bytes[s..<e], need.bytes) else { return false }
            return e - s <= need.bytes.count || need.agrees(tail: bytes[(s + need.bytes.count)..<e])
        }
        if !need.held.isEmpty { return need.agrees(tail: bytes[s..<e]) }
        let codes = Constraint.keyCodes(bytes[s..<e]).codes
        guard codes.prefix(need.keys.count).elementsEqual(need.keys.prefix(codes.count)) else { return false }
        return bytes[e - 1] < 0x80 || need.agrees(tail: bytes[s..<e])
    }
}
