import Foundation
import ItdaCore
import ItdaEngine

/// Resident size and physical footprint, the second of which is what Activity Monitor calls Memory.
private func memoryMB() -> (rss: Double, footprint: Double) {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return (Double(info.resident_size) / 1_048_576, Double(info.phys_footprint) / 1_048_576)
}

private func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
    return seconds(usage.ru_utime) + seconds(usage.ru_stime)
}

/// Runs one request to its end and returns (ms to the end, ms to the first result, stats, text).
private func timed(_ engine: Engine, _ prefix: String, _ fragment: String) -> (ms: Double, first: Double, stats: RequestStats, text: String) {
    final class Box: @unchecked Sendable { var first = 0.0, stats = RequestStats(), text = "" }
    let box = Box(), done = DispatchSemaphore(value: 0), start = Date()
    engine.suggest(prefix: prefix, fragment: fragment, onResult: { s in
        if box.first == 0 { box.first = Date().timeIntervalSince(start) * 1000 }
        box.text = s?.text ?? box.text
    }, onFinish: { stats in
        box.stats = stats
        done.signal()
    })
    done.wait()
    return (Date().timeIntervalSince(start) * 1000, box.first, box.stats, box.text)
}

/// Prefix reuse, cold start, memory, idle CPU and cancel latency, on text that isn't anyone's.
func probe(modelPath: String) throws {
    let filler = String(repeating: "The quick brown fox jumps over the lazy dog near the river bank at dawn. ", count: 14)
    print("baseline MB", memoryMB())
    var start = Date()
    let engine = try Engine(modelPath: modelPath, stopBelow: nil)
    print("first load s", Date().timeIntervalSince(start), "MB", memoryMB())

    let first = timed(engine, filler + "We", " sh")
    print("first request ms", first.ms, "first result ms", first.first, first.stats, "text", first.text, "MB", memoryMB())
    let same = timed(engine, filler + "We", " sho")
    print("same prompt, longer fragment", same.ms, same.first, same.stats, "canTrim", engine.canTrim)
    let grown = timed(engine, filler + "We should", " go")
    print("grown prompt", grown.ms, grown.first, grown.stats, "canTrim", engine.canTrim)
    let repeated = timed(engine, filler + "We should", " go")
    print("same again, must match", repeated.text == grown.text, repeated.stats)
    let hangul = timed(engine, "오늘 날씨가", " 정말")
    print("korean, new prompt", hangul.ms, hangul.first, hangul.stats, "text", hangul.text)
    let edited = timed(engine, filler.replacingOccurrences(of: "at dawn", with: "by dusk"), "")
    print("edited early", edited.ms, edited.first, edited.stats)

    var delays: [Double] = []
    for round in 0..<20 {
        _ = timed(engine, "x", "")
        let box = DispatchSemaphore(value: 0)
        final class End: @unchecked Sendable { var at = Date.distantPast }
        let end = End()
        engine.suggest(prefix: filler + "\(round)", fragment: "", onResult: { _ in }, onFinish: { _ in
            end.at = Date()
            box.signal()
        })
        Thread.sleep(forTimeInterval: 0.03)
        let asked = Date()
        engine.cancel()
        box.wait()
        delays.append(end.at.timeIntervalSince(asked) * 1000)
    }
    delays.sort()
    print("cancel during prefill ms p50", delays[10], "max", delays[19])

    let cpu = cpuSeconds()
    Thread.sleep(forTimeInterval: 20)
    print("idle CPU %, model loaded", (cpuSeconds() - cpu) / 20 * 100, "MB", memoryMB())
    engine.unload()
    print("after unload MB", memoryMB())
    let cpu2 = cpuSeconds()
    Thread.sleep(forTimeInterval: 10)
    print("idle CPU %, unloaded", (cpuSeconds() - cpu2) / 10 * 100)
    for _ in 0..<3 {
        start = Date()
        let again = timed(engine, "Hello", " the")
        print("reload to first answer s", Date().timeIntervalSince(start), "load s", engine.coldStartSeconds, again.stats)
        engine.unload()
    }
    print("final MB", memoryMB())
}
