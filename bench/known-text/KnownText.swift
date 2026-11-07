import Foundation
@testable import ItdaCore
@testable import ItdaEngine

// Types each line of well-known text into the real engine and policy, synchronously (each key waits for its answer),
// with no screen context. run.sh builds it as an extra target in a throwaway worktree; it isn't part of the app.
//   known-text <model.gguf> <out.jsonl> <group.txt>...
// Rows: one per position asked, and one "walk" row per even line: keys a Tab user presses, Tab taking one word.

let args = CommandLine.arguments
guard args.count >= 4 else { fatalError("usage: known-text <model.gguf> <out.jsonl> <group.txt>...") }
let engine = try Engine(modelPath: args[1])
FileManager.default.createFile(atPath: args[2], contents: nil)
let out = try FileHandle(forWritingTo: URL(fileURLWithPath: args[2]))

func write(_ row: [String: Any]) {
    out.write(try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]) + Data("\n".utf8))
}

struct Answer { var shown: Bool, right: Bool, ghost: String, gate: Double?, tabChars: Int, wordsChars: Int }

/// What Itda would show with the caret after `before`, as the app decides it: gate, then a first word of 3+ keys.
func ask(_ before: String, rest: String) -> Answer {
    let field = Field(before: before)
    let prompt = Prompt.make(context: "", field: field)
    guard !prompt.prefix.isEmpty else { return Answer(shown: false, right: false, ghost: "", gate: nil, tabChars: 0, wordsChars: 0) }
    final class Box: @unchecked Sendable { var last: Suggestion? }
    let box = Box()
    engine.suggest(prefix: prompt.prefix, fragment: prompt.fragment, composing: prompt.composing) { box.last = $0 }
    engine.finish()
    guard let s = box.last, let ghost = Follow.check(anchor: field.committed, suggestion: s.text, field: field) else {
        return Answer(shown: false, right: false, ghost: "", gate: box.last?.gate, tabChars: 0, wordsChars: 0)
    }
    let shown = (s.gate.map { $0 >= Gate.threshold } ?? false) && Gate.worthShowing(ghost)
    let score = score(ghost.remainder, rest: rest)
    return Answer(shown: shown, right: score.useful, ghost: ghost.remainder, gate: s.gate, tabChars: score.tab, wordsChars: score.words)
}

/// Exact match against the true rest, as bench-1's Score.swift for text with nothing composing.
func score(_ ghost: String, rest: String) -> (useful: Bool, tab: Int, words: Int) {
    let shown = Array(ghost), truth = Array(rest)
    let same = zip(shown, truth).prefix { $0 == $1 }.count
    func wholeWord(_ n: Int) -> Bool { (n == truth.count || !Word.isPart(truth[n])) && (n == shown.count || !Word.isPart(shown[n])) }
    let firstEnd = ghost.distance(from: ghost.startIndex, to: Word.firstEnd(ghost))
    guard firstEnd <= same, wholeWord(firstEnd) else { return (false, 0, 0) }
    return (true, firstEnd, (0...same).last { $0 >= firstEnd && wholeWord($0) } ?? firstEnd)
}

// Self-check of the scorer on invented text.
precondition(score("seven years", rest: "seven years ago") == (true, 5, 11))
precondition(score(" seven", rest: "seventy") == (false, 0, 0))
precondition(score("seven days", rest: "seven years") == (true, 5, 5))

let start = Date()
for path in args[3...] {
    let group = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    let lines = try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n").map(String.init)
    for (item, text) in lines.enumerated() {
        let chars = Array(text)
        var memo: [Int: Answer] = [:]
        func at(_ p: Int) -> Answer {
            if let a = memo[p] { return a }
            let a = ask(String(chars[..<p]), rest: String(chars[p...]))
            memo[p] = a
            return a
        }
        // Tab user: Tab when a right word shows, otherwise one more letter.
        // shortcut: every other line only, to keep a run of four models near 30 minutes; walk all for a tighter number.
        var p = item % 2 == 0 ? 0 : chars.count, keys = 0, tabs = 0
        var walked = Set<Int>()
        while p < chars.count {
            walked.insert(p)
            let a = at(p)
            keys += 1
            if a.shown, a.right { p += a.tabChars; tabs += 1 } else { p += 1 }
        }
        if item % 2 == 0 { write(["t": "walk", "group": group, "item": item, "len": chars.count, "keys": keys, "tabs": tabs]) }
        // Positions scored on their own: just after a space, and two letters into a word that goes on.
        let isPart = chars.map(Word.isPart)
        for p in 1..<chars.count {
            let wordStart = chars[p - 1] == " "
            let mid = p >= 2 && isPart[p - 1] && isPart[p - 2] && isPart[p] && (p == 2 || !isPart[p - 3])
            if wordStart || mid { _ = at(p) }
        }
        for (p, a) in memo.sorted(by: { $0.key < $1.key }) {
            let kind = p > 0 && chars[p - 1] == " " ? "start" : (p >= 2 && isPart[p - 1] && isPart[p - 2] && p < chars.count && isPart[p] && (p == 2 || !isPart[p - 3]) ? "mid" : "other")
            var row: [String: Any] = ["t": "pos", "group": group, "item": item, "pos": p, "kind": kind, "walk": walked.contains(p),
                                      "prefix": String(chars[..<p]), "shown": a.shown, "right": a.right, "ghost": a.ghost,
                                      "tab_chars": a.tabChars, "words_chars": a.wordsChars]
            if let g = a.gate { row["gate"] = g }
            write(row)
        }
    }
    print(group, String(format: "%.0f s", Date().timeIntervalSince(start)))
}
try out.close()
engine.unload()
