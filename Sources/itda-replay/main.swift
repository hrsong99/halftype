import Foundation
import ItdaCore
import ItdaEngine
import TwoSet

// Replays typing against the real engine, in real time, under the product's policy. Input: JSONL of {"context","text"},
// optionally "start", characters of text already in the field. Output: a JSONL trace, which holds the input's text.
//   itda-replay --model m.gguf --in in.jsonl --out trace.jsonl [--mode timed|sync] [--threshold -1.2]
//               [--composing keys|withhold|send] [--max-keys 40] [--stride 1] [--speed 1] [--seed 1]
//   itda-replay probe --model m.gguf
// timed: keys arrive with real delays, the next key cancels; Follow runs before any model call.
// sync: each key waits for an uncut answer, no Follow, for fitting gates offline.

var options: [String: String] = [:]
var args = Array(CommandLine.arguments.dropFirst())
let isProbe = args.first == "probe"
if isProbe { args.removeFirst() }
while args.count >= 2, args[0].hasPrefix("--") {
    options[String(args[0].dropFirst(2))] = args[1]
    args.removeFirst(2)
}
guard let modelPath = options["model"] else { fatalError("--model is required") }
if isProbe {
    try probe(modelPath: modelPath)
    exit(0)
}
guard let input = options["in"], let output = options["out"] else { fatalError("--in and --out are required") }

let config = Replay.Config(
    timed: options["mode", default: "timed"] == "timed",
    threshold: Double(options["threshold"] ?? "") ?? Gate.threshold,
    composing: Replay.Composing(rawValue: options["composing"] ?? "keys")!,
    maxKeys: Int(options["max-keys"] ?? "") ?? Int.max,
    stride: Int(options["stride"] ?? "") ?? 1,
    speed: Double(options["speed"] ?? "") ?? 1,
    seed: UInt64(options["seed"] ?? "") ?? 1)

struct Row: Decodable {
    var context: String
    var text: String
    var start: Int?
}
let rows = try String(contentsOfFile: input, encoding: .utf8).split(separator: "\n").map {
    try JSONDecoder().decode(Row.self, from: Data($0.utf8))
}
let engine = try Engine(modelPath: modelPath, stopBelow: config.timed ? config.threshold : nil)
FileManager.default.createFile(atPath: output, contents: nil)
let replay = Replay(engine: engine, config: config, out: try FileHandle(forWritingTo: URL(fileURLWithPath: output)))
for (index, row) in rows.enumerated() {
    replay.message(index, context: row.context, text: row.text, start: row.start ?? 0)
    if index % 20 == 19 { print("\(index + 1)/\(rows.count)") }
}
replay.close()
engine.unload()
