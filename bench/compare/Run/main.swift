// The typing comparison: Halftype against Cotypist, Cotabby, KeyType and macOS's own predictions, one app at a time,
// typed into this process's own field and read off the screen. bench/compare/run.sh builds and starts it; see the README.
//   halftype-compare --check                  preconditions only; types nothing, launches nothing
//   halftype-compare [--apps a,b] [--en 16] [--ko 10] [--text dir] [--out dir]
//   halftype-compare --score <out dir>        the summary again from a run's records
import AppKit
import CompareKit
import HalftypeCore
import ScreenCaptureKit

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
func option(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
let chosen = (option("--apps")?.split(separator: ",").map(String.init)).map { names in rivals.filter { names.contains($0.name) } } ?? rivals
let enCount = Int(option("--en") ?? "") ?? 16, koCount = Int(option("--ko") ?? "") ?? 10
let textDir = option("--text") ?? lab + "/compare/text"
/// A pause this long after every third word lets a slow app finish, so its speed is measured rather than cut off.
let probeMs = 1500.0

// MARK: Records

func lines<T: Decodable>(_ path: String, _: T.Type) -> [T] {
    ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
}
func append<T: Encodable>(_ row: T, to path: String) {
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    let h = FileHandle(forWritingAtPath: path)!
    h.seekToEndOfFile()
    h.write(try! JSONEncoder().encode(row) + Data("\n".utf8))
    h.closeFile()
}
func summarize(_ out: String) {
    let rows = Score.rows(keys: lines(out + "/keys.jsonl", KeyRecord.self), sentences: lines(out + "/sentences.jsonl", SentenceRecord.self),
                          resources: lines(out + "/resources.jsonl", ResourceRecord.self))
    let meta = (try? String(contentsOfFile: out + "/meta.md", encoding: .utf8)) ?? ""
    let md = meta + "\n" + Score.markdown(rows)
    try? md.write(toFile: out + "/summary.md", atomically: true, encoding: .utf8)
    print("\n" + md + "\nWritten to \(out)/summary.md. Only that file is meant for the repo: bench/compare/results/.")
}
if let dir = option("--score") { summarize(dir); exit(0) }

// MARK: Preconditions

func sentences(_ lang: String) -> [(id: String, text: String)] {
    ((try? String(contentsOfFile: "\(textDir)/\(lang).tsv", encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
        let c = $0.split(separator: "\t", maxSplits: 1)
        return c.count == 2 ? (String(c[0]), String(c[1])) : nil
    }
}

/// Halftype is measured at its defaults: Short, Normal, the default model, no personal model. What the user set is put back after.
let halftypeDefaults = UserDefaults(suiteName: "app.halftype.Halftype")!
let halftypeKeys = ["length", "often", "personal", "modelPath"]
var halftypeSaved: [String: Any]? = nil

/// Prints every precondition, and returns false if any isn't met.
func preflight() -> Bool {
    var ok = true
    func line(_ good: Bool, _ what: String, fix: String = "") {
        print("  \(good ? "ok  " : "FIX ") \(what)\(good || fix.isEmpty ? "" : "\n         -> \(fix)")")
        ok = ok && good
    }
    print("Preconditions (the terminal you run this from is what macOS grants permissions to):")
    line(CGPreflightPostEventAccess(), "the terminal may send keys and clicks (Accessibility)", fix: "System Settings > Privacy & Security > Accessibility: add your terminal")
    line(CGPreflightScreenCaptureAccess(), "the terminal may read the screen, for this harness only (Screen Recording)",
         fix: "System Settings > Privacy & Security > Screen & System Audio Recording: add your terminal, then restart it")
    line(sourceInstalled(twoSet) != nil, "2-Set Korean is an input source", fix: "System Settings > Keyboard > Text Input > Edit > + > Korean > 2-Set Korean")
    line(latinSource != nil, "ABC or U.S. is an input source", fix: "add ABC in System Settings > Keyboard > Text Input")
    let others = runningAutocompleters()
    line(others.isEmpty, "no autocomplete app is running" + (others.isEmpty ? "" : ": " + others.joined(separator: "; ")),
         fix: "quit them (a dev build of Halftype from another session counts: ask it to stop, don't kill it)")
    let en = sentences("en"), ko = sentences("ko")
    line(en.count > enCount && ko.count >= koCount, "public sentences in \(textDir): \(en.count) English (1 is the warm-up), \(ko.count) Korean",
         fix: "bench/compare/text.py fetch \(textDir)")
    let grants = accessibilityGrants()
    for r in chosen {
        guard let path = r.path, let id = r.bundleID else { print("  --   macos: predictions drawn by the test field itself (set on for it, off for the others); English only"); continue }
        line(FileManager.default.fileExists(atPath: path), "\(r.name) \(r.version) at \(path)")
        let grant = grants?[id]
        let how = r.touchID ? "System Settings > Privacy & Security > Accessibility > + > \(path) (asks for Touch ID)" : "System Settings > Privacy & Security > Accessibility: turn on \(r.name)"
        if let grant { line(grant, "\(r.name) has Accessibility", fix: how) }
        else { print("  ??   \(r.name) Accessibility: can't read the TCC database without Full Disk Access; the warm-up checks it. If missing: \(how)") }
    }
    if chosen.contains(where: { $0.name == "halftype" }) {
        let set = halftypeKeys.compactMap { k in halftypeDefaults.object(forKey: k).map { "\(k)=\($0)" } }
        print("  --   halftype runs at its defaults (Short, Normal, Gemma 4 E2B, no personal model)" +
              (set.isEmpty ? "" : "; your settings \(set.joined(separator: ", ")) are put back when it quits"))
        let model = NSHomeDirectory() + "/Library/Application Support/Halftype/gemma-4-E2B.Q4_K_M.gguf"
        line(FileManager.default.fileExists(atPath: model), "Halftype's default model is downloaded")
    }
    if chosen.contains(where: { $0.name == "cotypist" }) {
        let c = UserDefaults(suiteName: "app.cotypist.Cotypist")!
        if !(c.string(forKey: "CompletionManager_userPrompt") ?? "").isEmpty {
            print("  !!   cotypist has a personal prompt set (not its default): its numbers include it. Clear it in Cotypist's settings for a default run.")
        }
        print("  !!   cotypist's free plan has a daily cap: if its suggestions stop part-way, the run says so and its numbers aren't comparable")
    }
    let minutes = chosen.reduce(0) { $0 + ($1.path == nil ? 5 : $1.korean ? 11 : 6) }
    print("About \(minutes) minutes. It takes the keyboard, the pointer and the front window the whole time, and switches input sources.")
    return ok
}

let okToRun = preflight()
if args.contains("--check") { exit(okToRun ? 0 : 1) }
guard okToRun else { print("Not running: fix the lines marked FIX."); exit(1) }

// MARK: Leaving the Mac as it was

let startSource = currentSource()
var launched: Rival?
func restoreHalftype() {
    guard let saved = halftypeSaved else { return }
    for k in halftypeKeys { if let v = saved[k] { halftypeDefaults.set(v, forKey: k) } else { halftypeDefaults.removeObject(forKey: k) } }
    halftypeSaved = nil
}
func quit(_ r: Rival) {
    guard let id = r.bundleID else { return }
    sh("/usr/bin/osascript", ["-e", "tell application id \"\(id)\" to quit"])
    for _ in 0..<60 where !r.pids.isEmpty { sleepMs(500) }
    for pid in r.pids { kill(pid, SIGTERM) }
    for _ in 0..<20 where !r.pids.isEmpty { sleepMs(500) }
    if r.name == "halftype" { restoreHalftype() }
}
func cleanUp() {
    if let r = launched { quit(r); launched = nil }
    restoreHalftype()
    selectSource(startSource)
}
/// Set by Ctrl-C: the runner stops at its next key or wait, then cleans up itself, so cleanup never races a launch.
let stopLock = NSLock()
var stopAsked = false
var stopRequested: Bool { stopLock.withLock { stopAsked } }
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let s = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    s.setEventHandler {
        print("\nStopping: putting things back.")
        stopLock.withLock { stopAsked = true }
        // The runner checks at every key and every 5 s of waiting, and quitting an app takes under 45 s; if it hangs anyway, clean up from here.
        sleepMs(120_000)
        cleanUp()
        exit(2)
    }
    s.resume()
    signalSources.append(s)
}

// MARK: Typing

struct Stop: Error { let why: String }

final class Typist {
    let field: Field, capture: Capture, r: Rival, lang: String, out: String
    var ocrWaitMs = 0.0
    init(field: Field, capture: Capture, r: Rival, lang: String, out: String) {
        (self.field, self.capture, self.r, self.lang, self.out) = (field, capture, r, lang, out)
    }

    /// Types one sentence to the end at human delays, pressing Tab whenever the ghost on screen is the true text.
    /// `record` false is the warm-up. Returns how many keys found a ghost on screen.
    @discardableResult
    func type(id: String, text: String, record: Bool = true) throws -> Int {
        let plan = Plan(text)
        var delays = Delays(seed: Delays.seed(id))
        var pressed = 0, tabs = 0, wrongTabs = 0, asRead = 0, words = 0, shownKeys = 0, steps = 0
        var pending: (record: KeyRecord, t0: UInt64, before: Ink?)?
        field.clear()
        for _ in 0..<100 where capture.inkNow != nil { sleepMs(20) }  // A ghost left from the last sentence.
        sleepMs(600)
        while true {
            steps += 1
            if stopRequested { throw Stop(why: "stopped") }
            guard steps < plan.keys.count * 4 + 20 else { throw Stop(why: "\(id) never finished: the field kept leaving the text") }
            var (now_, composing) = field.text
            // Off the text (only a wrong Tab should do it): a user would delete back to where it went wrong.
            if plan.done(field: now_, composing: composing) == nil {
                let common = String(zip(now_, plan.target).prefix(while: { $0 == $1 }).map(\.0))
                // 2-set deletes a composing syllable a jamo at a time (값: four), a committed one whole.
                pressed += Hangul.keys(composing).count + max(0, now_.count - composing.count - common.count)
                field.set(common)
                (now_, composing) = (common, "")
                sleepMs(300)
            }
            let start = now()
            let ghost = capture.ghost(wait: 500)
            ocrWaitMs += ms(start, now())
            if var p = pending {
                p.record.latencyMs = capture.firstChange(after: p.t0, from: p.before)
                p.record.shown = ghost != nil
                p.record.firstRight = ghost.map { plan.firstWordRight(field: now_, composing: composing, ghost: $0) } ?? false
                p.record.composing = !composing.isEmpty
                if p.record.shown { shownKeys += 1 }
                if record { append(p.record, to: out + "/keys.jsonl") }
                pending = nil
            }
            guard let done = plan.done(field: now_, composing: composing), done < plan.keys.count else { break }
            // Only the app under test may take the window back from (an onboarding window, say). Anyone else is a person: stop.
            if !field.focused, !(r.pids.contains(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0) && field.focus()) {
                throw Stop(why: "the test window lost the keyboard; not typing into anything else")
            }
            let before = capture.inkNow, t0: UInt64
            let isTab: Bool, probe: Bool
            if let ghost, case let expected = plan.tab(field: now_, composing: composing, ghost: ghost, unit: r.unit), !expected.isEmpty {
                t0 = now()
                press(48)
                (isTab, probe) = (true, false)
                tabs += 1
                pressed += 1
                var after = field.text
                for _ in 0..<40 where after.field == now_ { sleepMs(10); after = field.text }
                if plan.done(field: after.field, composing: after.composing) == nil { wrongTabs += 1 }
                else if expected.contains(after.field) { asRead += 1 }
            } else {
                let key = plan.keys[done]
                guard let s = stroke(key) else { throw Stop(why: "no key types \(key)") }
                if key == " " { words += 1 }
                probe = key == " " && words % 3 == 0
                isTab = false
                t0 = now()
                press(s.code, shift: s.shift)
                pressed += 1
            }
            pending = (KeyRecord(app: r.name, lang: lang, sentence: id, tab: isTab, probe: probe, fresh: before == nil, latencyMs: nil,
                                 shown: false, firstRight: false, composing: false), t0, before)
            sleepMs(probe ? probeMs : delays.next())
        }
        if record {
            append(SentenceRecord(app: r.name, lang: lang, sentence: id, total: plan.keys.count, pressed: pressed, tabs: tabs, wrongTabs: wrongTabs, tabsAsRead: asRead),
                   to: out + "/sentences.jsonl")
        }
        print("    \(id.prefix(24))…: \(pressed) of \(plan.keys.count) keys, \(tabs) Tabs\(wrongTabs > 0 ? " (\(wrongTabs) wrong)" : ""), ghost on \(shownKeys) keys")
        return shownKeys
    }
}

// MARK: One app

func waitForModel(_ r: Rival) -> Bool {
    for _ in 0..<36 where !stopRequested {
        if modelResidentMB(r.pids) != nil { return true }
        sleepMs(5000)
    }
    return false
}

func run(_ r: Rival, field: Field, capture: Capture, out: String) throws {
    print("\n== \(r.name) \(r.version)")
    if r.path != nil {
        guard r.pids.isEmpty, runningAutocompleters().isEmpty else { throw Stop(why: "another autocomplete app is running") }
        if r.name == "halftype" {
            halftypeSaved = Dictionary(uniqueKeysWithValues: halftypeKeys.compactMap { k in halftypeDefaults.object(forKey: k).map { (k, $0) } })
            for k in halftypeKeys { halftypeDefaults.removeObject(forKey: k) }
            halftypeDefaults.set("off", forKey: "personal")
        }
        launched = r
        sh("/usr/bin/open", ["-g", "-j", r.path!])
        print("  launched hidden; waiting for its model to be mapped (up to 3 minutes)")
        // KeyType starts its engine only with Accessibility, so an app without it may never load its model.
        guard waitForModel(r) else { throw Stop(why: "\(r.name) never mapped a .gguf: no Accessibility, or it's waiting in onboarding") }
    }
    onMain { field.view.inlinePredictionType = r.path == nil ? .yes : .no }
    guard field.focus() else { throw Stop(why: "couldn't bring the test window forward") }
    guard selectSource(latinSource!) else { throw Stop(why: "couldn't select \(latinSource!)") }
    capture.korean = false
    capture.resetCrops(out + "/crops/\(r.name)")
    let en = sentences("en"), ko = sentences("ko")
    // The warm-up: the app must really be suggesting in this field before anything is recorded.
    print("  warm-up (not scored)")
    let warm = Typist(field: field, capture: capture, r: r, lang: "en", out: out)
    guard try warm.type(id: en[0].id, text: en[0].text, record: false) + warm.type(id: en[0].id, text: en[0].text, record: false) > 0 else {
        throw Stop(why: "\(r.name) showed no suggestion in the warm-up sentence, twice: check its Accessibility and that it's switched on")
    }
    var phases = [("en", Array(en.dropFirst().prefix(enCount)))]
    if r.korean { phases.append(("ko", Array(ko.prefix(koCount)))) }
    for (lang, list) in phases where !list.isEmpty {  // --ko 0: no phase, and no division by its zero seconds
        print("  \(lang == "en" ? "English" : "Korean, 2-Set")")
        guard selectSource(lang == "ko" ? twoSet : latinSource!) else { throw Stop(why: "couldn't select the input source") }
        capture.korean = lang == "ko"
        let typist = Typist(field: field, capture: capture, r: r, lang: lang, out: out)
        let pids = r.pids, cpu0 = cpuSeconds(pids), t0 = now()
        var footprints: [Double] = [], quiet = 0
        for s in list {
            let shown = try typist.type(id: s.id, text: s.text)
            quiet = shown == 0 ? quiet + 1 : 0
            if quiet == 3 { print("  !! no suggestion in three sentences running: a daily cap, a crash, or the app gave up. Its numbers from here aren't comparable.") }
            if !pids.isEmpty { footprints.append(pids.compactMap(footprintMB).reduce(0, +)) }
        }
        let seconds = ms(t0, now()) / 1000
        // The CPU share is over typing and the sampling between sentences, the same for every app.
        append(ResourceRecord(app: r.name, lang: lang, footprintMB: footprints, modelResidentMB: modelResidentMB(pids),
                              cpuPercent: pids.isEmpty ? nil : (cpuSeconds(pids) - cpu0) / seconds * 100, seconds: seconds), to: out + "/resources.jsonl")
        print(String(format: "  %.0f s, waited %.1f s in all for OCR", seconds, typist.ocrWaitMs / 1000))
    }
    selectSource(latinSource!)
    if r.path != nil {
        print("  quitting, and waiting until its memory is gone")
        quit(r)
        launched = nil
        guard r.pids.isEmpty else { throw Stop(why: "\(r.name) didn't quit") }
        sleepMs(5000)
    }
}

// MARK: Main

let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
let out = option("--out") ?? "\(lab)/compare/\(stamp)"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let meta = """
    Run \(stamp) on \(sh("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]).out.trimmingCharacters(in: .whitespacesAndNewlines)), \
    \(ProcessInfo.processInfo.physicalMemory >> 30) GB, macOS \(ProcessInfo.processInfo.operatingSystemVersionString). \
    Apps: \(chosen.map { "\($0.name) \($0.version)" }.joined(separator: ", ")). \
    \(enCount) English (Taskmaster-1) and \(koCount) Korean (SmileStyle) sentences from bench/compare/ids.tsv, \
    typed at log-normal delays around 264 ms with a 1.5 s probe after every third word.

    """
try? meta.write(toFile: out + "/meta.md", atomically: true, encoding: .utf8)

NSApplication.shared.setActivationPolicy(.regular)
Thread {
    let field = onMain { Field() }
    let capture = Capture(field: field)
    var failed: [String] = []
    do {
        onMain { field.window.orderFrontRegardless() }
        Ghost.warmUp()
        try capture.start()
        for r in chosen where !stopRequested {
            do { try run(r, field: field, capture: capture, out: out) } catch let stop as Stop {
                print("  !! \(r.name) not measured: \(stop.why)")
                failed.append(r.name)
                if let l = launched { quit(l); launched = nil }
                if stop.why.contains("lost the keyboard") { break }
            }
        }
    } catch { print("Screen capture didn't start: \(error)") }
    capture.stop()
    cleanUp()
    onMain { field.window.orderOut(nil) }
    summarize(out)
    if !failed.isEmpty { print("Not measured: \(failed.joined(separator: ", ")).") }
    exit(failed.isEmpty ? 0 : 1)
}.start()
NSApplication.shared.run()
