import AppKit
import Carbon
import CompareKit
@testable import HalftypeApp

// Everything the runner asks of the Mac: processes, permissions, input sources, keys.

let msPerTick: Double = {
    var info = mach_timebase_info()
    mach_timebase_info(&info)
    return Double(info.numer) / Double(info.denom) / 1e6
}()
func now() -> UInt64 { mach_absolute_time() }
func ms(_ from: UInt64, _ to: UInt64) -> Double { Double(Int64(to) - Int64(from)) * msPerTick }
func sleepMs(_ x: Double) { usleep(useconds_t(max(0, x) * 1000)) }
func onMain<T>(_ work: () -> T) -> T { Thread.isMainThread ? work() : DispatchQueue.main.sync(execute: work) }

@discardableResult
func sh(_ path: String, _ args: [String]) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return (-1, "") }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

/// An app under test. macOS's own predictions have no app: they draw in the test field itself.
struct Rival {
    let name: String, bundleID: String?, path: String?, unit: TabUnit, korean: Bool
    /// Granting Accessibility to a copy outside /Applications asks for Touch ID or the password.
    let touchID: Bool

    var executable: String? {
        guard let path, let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") else { return nil }
        return info["CFBundleExecutable"] as? String
    }
    var version: String {
        guard let path else { return ProcessInfo.processInfo.operatingSystemVersionString }
        return (NSDictionary(contentsOfFile: path + "/Contents/Info.plist")?["CFBundleShortVersionString"] as? String) ?? "?"
    }
    /// Every process running from inside the bundle, helpers included.
    var pids: [pid_t] {
        guard let path else { return [] }
        return sh("/usr/bin/pgrep", ["-f", path + "/Contents/"]).out.split(separator: "\n").compactMap { pid_t($0) }
    }
}

let lab = NSHomeDirectory() + "/halftype-lab-private"
/// `--halftype-app <path>`: a build to measure in place of the installed app. It must carry the Developer ID, whose Accessibility grant it shares.
let halftypeApp = CommandLine.arguments.firstIndex(of: "--halftype-app").map { CommandLine.arguments[$0 + 1] } ?? "/Applications/Halftype.app"
let rivals: [Rival] = [
    Rival(name: "macos", bundleID: nil, path: nil, unit: .all, korean: false, touchID: false),
    Rival(name: "halftype", bundleID: "app.halftype.Halftype", path: halftypeApp, unit: .word, korean: true, touchID: false),
    Rival(name: "cotypist", bundleID: "app.cotypist.Cotypist", path: "/Applications/Cotypist.app", unit: .word, korean: true, touchID: false),
    Rival(name: "cotabby", bundleID: "com.jacobfu.tabby", path: lab + "/rivals/Cotabby.app", unit: .word, korean: true, touchID: true),
    Rival(name: "keytype", bundleID: "com.pattonium.KeyType", path: lab + "/rivals/KeyType.app", unit: .word, korean: true, touchID: true),
]

/// Any autocomplete app running now, wherever it was started from: a dev build of Halftype counts too.
func runningAutocompleters() -> [String] {
    let names = ["Halftype", "Itda", "Cotypist", "Cotabby", "KeyType"]
    return names.flatMap { name in
        sh("/usr/bin/pgrep", ["-lx", name]).out.split(separator: "\n").map { line in
            let pid = line.split(separator: " ").first.map(String.init) ?? "?"
            return "\(name) pid \(pid): \(sh("/bin/ps", ["-o", "comm=", "-p", pid]).out.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }
}

// MARK: Memory and CPU, from outside, the same way for every app.

/// The capture groups of the first match.
func groups(_ pattern: String, _ s: String) -> [String]? {
    let r = try! NSRegularExpression(pattern: pattern)
    guard let m = r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
    return (1..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
}

func footprintMB(_ pid: pid_t) -> Double? {
    let out = sh("/usr/bin/footprint", ["-p", "\(pid)"]).out
    guard let m = groups(#"Footprint: ([0-9.]+) ([KMG])B"#, out), let v = Double(m[0]) else { return nil }
    return v * ["K": 1.0 / 1024, "M": 1, "G": 1024][m[1]]!
}

/// Resident size of mapped .gguf files: the model weights, which footprint doesn't count (they are file-backed).
func modelResidentMB(_ pids: [pid_t]) -> Double? {
    var total = 0.0, any = false
    for pid in pids {
        for line in sh("/usr/bin/vmmap", ["-wide", "\(pid)"]).out.split(separator: "\n") where line.lowercased().contains(".gguf") {
            guard let m = groups(#"\[\s*([0-9.]+)([KMG]?)\s+([0-9.]+)([KMG]?)"#, String(line)), let v = Double(m[2]) else { continue }
            any = true
            total += v * ["": 1.0 / 1_048_576, "K": 1.0 / 1024, "M": 1, "G": 1024][m[3]]!
        }
    }
    return any ? total : nil
}

func cpuSeconds(_ pids: [pid_t]) -> Double {
    pids.reduce(0) { sum, pid in
        var info = rusage_info_v2()
        let ok = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) } }
        return ok == 0 ? sum + Double(info.ri_user_time + info.ri_system_time) * msPerTick / 1000 : sum
    }
}

// MARK: Input sources

let twoSet = TwoSetLayout.source
func sourceInstalled(_ id: String) -> TISInputSource? {
    let list = TISCreateInputSourceList([kTISPropertyInputSourceID as String: id] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource]
    return list?.first
}
func currentSource() -> String {
    onMain {
        let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyInputSourceID)).takeUnretainedValue() as String
    }
}
@discardableResult func selectSource(_ id: String) -> Bool {
    onMain { sourceInstalled(id).map { TISSelectInputSource($0) == noErr } ?? false }
}
let latinSource = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"].first { sourceInstalled($0) != nil }

// MARK: Keys, at the HID level, so every app's event tap and the input method see them as typed.

private let letters: [Character: CGKeyCode] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
                                               "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46]

/// The physical key for a Latin letter, or what 2-set types a jamo, digit, space or punctuation with.
func stroke(_ c: Character) -> TwoSetLayout.Stroke? {
    if let code = letters[Character(c.lowercased())], c.isASCII { return (code, c.isUppercase) }
    return TwoSetLayout.strokes(String(c))?.first
}

func press(_ code: CGKeyCode, shift: Bool = false) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
        e.flags = shift ? .maskShift : []
        e.post(tap: .cghidEventTap)
        usleep(8_000)
    }
}

func click(_ p: CGPoint) {
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
        usleep(30_000)
    }
}

// MARK: Accessibility of the apps under test, where the TCC database can be read (the terminal needs Full Disk Access).

func accessibilityGrants() -> [String: Bool]? {
    let db = "/Library/Application Support/com.apple.TCC/TCC.db"
    let r = sh("/usr/bin/sqlite3", [db, "select client, auth_value from access where service='kTCCServiceAccessibility'"])
    guard r.status == 0 else { return nil }
    var out: [String: Bool] = [:]
    for line in r.out.split(separator: "\n") {
        let cells = line.split(separator: "|")
        if cells.count == 2 { out[String(cells[0])] = cells[1] == "2" }
    }
    return out
}
