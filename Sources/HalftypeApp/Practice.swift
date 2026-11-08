import AppKit
import HalftypeEngine
import SwiftUI

/// Answers before any model is ready, during onboarding, so Try It's first Tab needs no 3 GB wait: it finishes only its own sentences,
/// so anywhere else it says nothing. A real model replaces it the moment one loads.
final class Practice: Completer {
    /// Onboarding's three lessons, which start with these sentences' first halves.
    static let sentences = ["Please let me know if you have any questions or concerns.", "Thanks so much for the birthday wishes, it made my day.",
                            "Can we move the meeting to Thursday afternoon?"]

    /// The rest of a practice sentence whose start, at least `least` characters of it, is the end of what's typed.
    static func rest(after typed: String, least: Int = 8) -> String? {
        for sentence in sentences {
            for cut in stride(from: sentence.count - 1, through: least, by: -1) where typed.hasSuffix(sentence.prefix(cut)) {
                return String(sentence.dropFirst(cut))
            }
        }
        return nil
    }

    func suggest(prefix: String, fragment: String, composing: String, onResult: @escaping @Sendable (Suggestion?) -> Void) {
        onResult(Practice.rest(after: prefix + fragment).map { Suggestion(text: $0, gate: 0) })
    }
    func cancel() {}
    func unload() {}
}

/// A card docked beside System Settings while it's open on our account, saying which switch to flip (docs/design/onboarding, H).
/// Its icon drags into the list, for a build the system didn't list. It goes when the grant comes or Settings quits.
final class SettingsGuide {
    private(set) var panel: NSPanel?
    private var timer: Timer?
    private var quit: NSObjectProtocol?
    private var asked = Date.distantPast
    private var seen = false
    static let settingsID = "com.apple.systempreferences"

    func show() {
        close()
        (asked, seen) = (Date(), false)
        // Settings takes a moment to open; the card follows its window wherever it's dragged, and hides while it's minimized or hidden.
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.follow() }
        quit = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == SettingsGuide.settingsID { self?.close() }
        }
        follow()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        quit.map(NSWorkspace.shared.notificationCenter.removeObserver)
        quit = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func follow() {
        guard let settings = SettingsGuide.settingsFrame() else {
            panel?.orderOut(nil)
            // Settings never came (the prompt was denied): stop asking the window list. A second click starts it again.
            if !seen, Date().timeIntervalSince(asked) > 120 { close() }
            return
        }
        seen = true
        let panel = self.panel ?? make()
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(settings) }) ?? NSScreen.main else { return }
        let (origin, left) = SettingsGuide.place(beside: settings, size: panel.frame.size, in: screen.visibleFrame)
        (panel.contentView as? NSHostingView<GuideCard>)?.rootView.left = left
        panel.setFrameOrigin(origin)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func make() -> NSPanel {
        let host = NSHostingView(rootView: GuideCard(left: true) { [weak self] in self?.close() })
        host.frame.size = host.fittingSize
        let made = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        made.isOpaque = false
        made.backgroundColor = .clear
        made.hasShadow = true
        made.level = .floating
        made.hidesOnDeactivate = false
        made.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        made.contentView = host
        panel = made
        return made
    }

    /// System Settings' largest window, in AppKit's coordinates. Bounds and owner need no Screen Recording; the title would.
    static func settingsFrame() -> CGRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: settingsID).first?.processIdentifier,
              let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let frames = list.compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid, info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary, let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return rect
        }
        return frames.max { $0.width * $0.height < $1.width * $1.height }.map { GhostLayout.appKitRect($0, primaryHeight: primary.frame.height) }
    }

    /// Left of Settings if it fits, else right, else just inside its left edge; level with the top of its list, kept on screen.
    /// `left` is true when the card sits on Settings' left, so its arrow points right.
    static func place(beside settings: CGRect, size: CGSize, in visible: CGRect, gap: CGFloat = 14) -> (CGPoint, left: Bool) {
        var x = settings.minX - gap - size.width, left = true
        if x < visible.minX {
            x = settings.maxX + gap
            left = false
            if x + size.width > visible.maxX { (x, left) = (max(visible.minX, settings.minX + gap), true) }
        }
        let y = min(max(settings.maxY - 120 - size.height, visible.minY), visible.maxY - size.height)
        return (CGPoint(x: x, y: y), left)
    }
}

struct GuideCard: View {
    var left: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if !left { arrow }
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                    .help("Drag into the list if Halftype isn't there")
                Text("Turn on Halftype").font(.system(size: 13, weight: .semibold))
                Text("Flip the switch next to it in the list. Not there? Drag this icon in.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 150)
            if left { arrow }
        }
        .padding(14)
        // The window's cream, so it reads as Halftype's beside Settings in light or dark mode (docs/design/onboarding, H).
        .background(Color(red: 0.965, green: 0.945, blue: 0.914), in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(8) }
                .buttonStyle(.plain).help("Hide")
        }
        .preferredColorScheme(.light)
    }

    private var arrow: some View {
        Image(systemName: left ? "arrow.right" : "arrow.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Root.peach)
    }
}
