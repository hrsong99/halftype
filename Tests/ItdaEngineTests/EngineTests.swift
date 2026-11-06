import Foundation
import ItdaCore
import Testing
@testable import ItdaEngine

// Set ITDA_MODEL to a GGUF path to run the tests marked `needsModel`.
private let modelPath = ProcessInfo.processInfo.environment["ITDA_MODEL"]
private let needsModel = Testing.ConditionTrait.enabled(if: modelPath != nil, "needs ITDA_MODEL")

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
    #expect(abs(pick.plain - log(0.3)) < 1e-6)
}

@Test func nothingAllowedIsNoPick() {
    let logits: [Float] = [0, 0]
    #expect(logits.withUnsafeBufferPointer { Pick.best($0, allowed: { _ in false }, isEnd: { _ in false }) } == nil)
}

private final class Box: @unchecked Sendable {
    var last: Suggestion?, stats = RequestStats()
}

private func run(_ engine: Engine, _ prefix: String, _ fragment: String, composing: String = "") -> Box {
    let box = Box(), done = DispatchSemaphore(value: 0)
    engine.suggest(prefix: prefix, fragment: fragment, composing: composing, onResult: { box.last = $0 ?? box.last }, onFinish: {
        box.stats = $0
        done.signal()
    })
    done.wait()
    return box
}

private let long = String(repeating: "The river runs past the old mill and on toward the sea. ", count: 8) + "We"

@Test(needsModel) func forcesTheFragmentAndNeverLetsAControlTokenThrough() throws {
    let engine = try Engine(modelPath: modelPath!, stopBelow: nil)
    defer { engine.unload() }
    for (prefix, fragment) in [(long, " sho"), ("오늘 날씨가", " 정"), ("Hello my", " fr")] {
        let tokens = try #require(run(engine, prefix, fragment).last).tokens
        let bytes = tokens.flatMap(\.bytes)
        #expect(bytes.starts(with: Array(fragment.utf8)))
        #expect(tokens.allSatisfy { $0.special || !$0.bytes.isEmpty })
    }
}

@Test(needsModel) func decodesOnlyTheDifference() throws {
    let engine = try Engine(modelPath: modelPath!, stopBelow: nil)
    defer { engine.unload() }
    let first = run(engine, long, " sho")
    #expect(first.stats.prefilled == first.stats.promptTokens)
    #expect(run(engine, long, " shou").stats.prefilled <= Engine.checkpointTail + 1)
    #expect(run(engine, long + " should", " g").stats.prefilled <= Engine.checkpointTail + 3)
}

/// The reused memory, whether trimmed or restored from a checkpoint, must give what a fresh decode gives.
@Test(needsModel) func reuseMatchesAFreshDecode() throws {
    let engine = try Engine(modelPath: modelPath!, stopBelow: nil)
    _ = run(engine, long, " sho")
    let reused = try #require(run(engine, long, " shou").last)
    engine.unload()
    let fresh = try #require(run(engine, long, " shou").last)
    engine.unload()
    #expect(reused.text == fresh.text)
    #expect(zip(reused.tokens, fresh.tokens).allSatisfy { abs($0.logprob - $1.logprob) < 0.05 })
}

@Test(needsModel) func cancelInterruptsPrefillAndTheNextRequestStillWorks() throws {
    let engine = try Engine(modelPath: modelPath!, stopBelow: nil)
    defer { engine.unload() }
    let cancelled = Box(), done = DispatchSemaphore(value: 0)
    engine.suggest(prefix: long + long + long, fragment: "", onResult: { cancelled.last = $0 }, onFinish: {
        cancelled.stats = $0
        done.signal()
    })
    Thread.sleep(forTimeInterval: 0.02)
    engine.cancel()
    done.wait()
    #expect(cancelled.stats.cancelled)
    #expect(cancelled.last == nil)
    #expect(run(engine, long, " sho").last != nil)
}

@Test(needsModel) func latestRequestWins() throws {
    let engine = try Engine(modelPath: modelPath!, stopBelow: nil)
    defer { engine.unload() }
    let stale = Box()
    engine.suggest(prefix: long, fragment: "", onResult: { stale.last = $0 })
    let latest = run(engine, "Hello my", " fr")
    #expect(latest.last != nil)
    #expect(stale.last == nil || !stale.last!.done)
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
    let engine = try Engine(modelPath: modelPath!, stopBelow: nil)
    defer { engine.unload() }
    let text = try #require(run(engine, "오늘 날씨가 정말 좋아서 공원에", " 산책", composing: "하").last).text
    #expect(Hangul.fits(composing: "하", suggestion: text))
}
