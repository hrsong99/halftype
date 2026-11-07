import AppKit
import ServiceManagement
import SwiftUI

/// The one window: a field to type in, in the manner of Ollama's app, with plain pages behind a sidebar. It exists only while open.
struct Root: View {
    @ObservedObject var app: App
    /// Stays in memory, and goes when the window closes.
    @State private var draft = ""
    @State private var sidebar: Bool
    @State private var page: Page

    private let picking: Bool

    init(app: App, page: Page = .field, sidebar: Bool = false, picking: Bool = false) {
        self.app = app
        self.picking = picking
        _page = State(initialValue: page)
        _sidebar = State(initialValue: sidebar)
    }

    enum Page: String, CaseIterable { case field = "Try It", models = "Models", apps = "Apps", general = "General" }

    var body: some View {
        HStack(spacing: 0) {
            if sidebar { side.transition(.move(edge: .leading)) }
            ZStack {
                switch page {
                case .field: FieldPage(app: app, draft: $draft, page: $page, picking: picking)
                case .models: ModelsPage(app: app)
                case .apps: AppsPage(app: app)
                case .general: GeneralPage(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 28)
        }
        .overlay(alignment: .topLeading) {
            Button { withAnimation(.easeOut(duration: 0.16)) { sidebar.toggle() } } label: { Image(systemName: "sidebar.left") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(sidebar ? "Hide sidebar" : "Show sidebar")
                .padding(.leading, 84)
                .padding(.top, 9)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 440, idealHeight: 500)
        .background(Color(nsColor: .textBackgroundColor))
        .ignoresSafeArea()
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Page.allCases, id: \.self) { item in
                Button { page = item } label: {
                    Text(item.rawValue).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 5).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(page == item ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
            }
            Spacer()
            Toggle("On", isOn: $app.on).toggleStyle(.switch).controlSize(.mini).tint(.primary).padding(.horizontal, 10)
        }
        .padding(.horizontal, 8)
        .padding(.top, 38)
        .padding(.bottom, 12)
        .frame(width: 150)
        .background(Color.primary.opacity(0.03))
    }
}

/// The app icon's caret and fading continuation, as a small line mark.
private struct Mark: View {
    var body: some View {
        HStack(spacing: 2) {
            Capsule().fill(.primary).frame(width: 3, height: 26)
            Capsule().fill(LinearGradient(colors: [.primary, .primary.opacity(0)], startPoint: .leading, endPoint: .trailing)).frame(width: 18, height: 3)
        }
    }
}

private struct FieldPage: View {
    @ObservedObject var app: App
    @Binding var draft: String
    @Binding var page: Root.Page
    @FocusState private var focused: Bool
    @State private var picking: Bool
    /// The watcher's reason once it has held for a moment, so typing doesn't flicker the line.
    @State private var settled: Watcher.Why

    init(app: App, draft: Binding<String>, page: Binding<Root.Page>, picking: Bool = false) {
        self.app = app
        _draft = draft
        _page = page
        _picking = State(initialValue: picking)
        _settled = State(initialValue: app.why)
    }

    var body: some View {
        VStack(spacing: 16) {
            Mark()
            if app.trusted { field.zIndex(1) } else { allow }  // The list hangs over what's below the field.
            status
        }
        .padding(24)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A click anywhere else only closes the list.
        .background { if picking { Color.black.opacity(0.001).onTapGesture { picking = false } } }
    }

    private var allow: some View {
        VStack(spacing: 12) {
            Text("Itda needs to see what you type. It stays on this Mac.").foregroundStyle(.secondary)
            Button("Allow Accessibility", action: app.askForAccessibility).buttonStyle(.borderedProminent).tint(.primary).buttonBorderShape(.capsule)
        }
    }

    private var field: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(!app.on ? "Itda is off" : app.ready ? "Type here, then press Tab on the grey text" : "Type here once the model is ready")
                        .foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $draft).focused($focused).scrollContentBackground(.hidden).scrollIndicators(.never).frame(height: 44)
                    .onKeyPress(.escape) {
                        guard picking else { return .ignored }
                        picking = false
                        return .handled
                    }
            }
            .font(.system(size: 15))
            HStack(spacing: 8) {
                Button { picking.toggle() } label: {
                    Text(app.activeName).font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 4).background(Color(nsColor: .textBackgroundColor), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Model: \(app.activeName)")
                .overlay(alignment: .topTrailing) {
                    if picking {
                        ModelList(app: app) { picking = false } showAll: { picking = false; page = .models }.offset(y: 32)
                    }
                }
                Button { app.on.toggle() } label: {
                    Image(systemName: "power").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(nsColor: .textBackgroundColor))
                        .frame(width: 24, height: 24)
                        .background(app.on ? Color.primary : Color.secondary.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .help(app.on ? "Itda is on. Click to turn it off." : "Itda is off. Click to turn it on.")
                .accessibilityLabel(app.on ? "Turn Itda off" : "Turn Itda on")
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 9, trailing: 10))
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
        .frame(maxWidth: 500)
        .onAppear { focused = true }
        .onChange(of: draft) { picking = false }
        .onChange(of: app.ready, initial: true) { if let sentence = app.takePrefill(draft: draft) { draft = sentence } }
        .task(id: app.why) {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { settled = app.why }
        }
    }

    /// The model until it's ready, then what the menu says about this field: how to take a ghost, that it worked, or why there's none.
    @ViewBuilder private var status: some View {
        VStack(spacing: 6) {
            if !app.ready || app.notice != nil {
                NoticeLine(app: app, text: app.notice ?? app.modelLine)
                if !app.ready, app.downloading != nil {
                    ProgressView(value: app.downloadFraction).frame(width: 160).tint(.primary)
                    Line(text: "You can close this window.")
                }
            } else if let line = app.fieldLine(settled) {
                HStack(spacing: 8) {
                    Line(text: line)
                    if line == App.success, !app.startAtLogin { Button("Start at Login") { app.startAtLogin = true }.controlSize(.small) }
                }
            }
            if app.predictions {
                HStack(spacing: 8) {
                    Line(text: "macOS shows its own grey predictions too.")
                    Button("Turn Them Off…", action: app.openKeyboardSettings).controlSize(.small)
                }
            }
        }
    }
}

private struct Line: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(.secondary) }
}

/// A line of status, with Retry when it's a download that failed.
private struct NoticeLine: View {
    @ObservedObject var app: App
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Line(text: text)
            if app.retryable { Button("Retry", action: app.retry).controlSize(.small) }
        }
    }
}

/// The model list under the pill: ours, so it opens at once and reads like the window. Models you don't have yet start downloading from here.
private struct ModelList: View {
    @ObservedObject var app: App
    let close: () -> Void
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // Six rows, then it scrolls: a long list of your own would run off the window.
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(ModelStore.models) { model in
                        item(model.name, detail: app.downloading == model.id ? "\(Int(app.downloadFraction * 100))%" : model.sizeText,
                             mark: app.isActive(model) ? "checkmark" : app.store.has(model) ? nil : "arrow.down") { app.use(model); close() }
                            .disabled(!app.store.has(model) && app.downloading != nil)
                    }
                    ForEach(app.ownModels, id: \.self) { path in
                        item(App.fileName(path), detail: nil, mark: app.isActive(path: path) ? "checkmark" : nil) { app.use(path: path); close() }
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: CGFloat(min(ModelStore.models.count + app.ownModels.count, 6)) * 28)
            Divider().padding(.vertical, 3)
            item("All Models", detail: nil, mark: nil, action: showAll)
        }
        .padding(5)
        .frame(width: 270)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
    }

    private func item(_ title: String, detail: String?, mark: String?, action: @escaping () -> Void) -> some View {
        Hover { hovering in
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                    Image(systemName: mark ?? "checkmark").font(.system(size: 10.5, weight: .semibold)).frame(width: 14).opacity(mark == nil ? 0 : 1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(hovering ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct Hover<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false
    var body: some View { content(hovering).onHover { hovering = $0 } }
}

/// A title and hairline rows, with no boxes.
private struct Plain<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 20, weight: .semibold)).padding(.bottom, 12)
                content
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct Row<Trailing: View>: View {
    let title: String
    var note: String? = nil
    @ViewBuilder let trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                }
                Spacer()
                trailing
            }
            .padding(.vertical, 10)
        }
    }
}

private struct ModelsPage: View {
    @ObservedObject var app: App
    var body: some View {
        Plain(title: "Models") {
            ForEach(ModelStore.models) { model in
                Row(title: model.name, note: model.note) {
                    Text(model.sizeText).foregroundStyle(.secondary).font(.system(size: 12))
                    action(model).frame(minWidth: 64, alignment: .trailing)
                }
            }
            ForEach(app.ownModels, id: \.self) { path in
                Row(title: App.fileName(path), note: "Your own, from \(URL(fileURLWithPath: path).deletingLastPathComponent().path)") {
                    if app.isActive(path: path) {
                        Text("In use").foregroundStyle(.secondary).font(.system(size: 12)).frame(minWidth: 64, alignment: .trailing)
                    } else {
                        Button("Forget") { app.forgetOwnModel(path) }.help("Takes it off this list. The file stays.")
                        Button("Use") { app.use(path: path) }.frame(minWidth: 64, alignment: .trailing)
                    }
                }
            }
            Row(title: "Add Your Own GGUF") {
                Button("Choose…", action: app.chooseModel).frame(minWidth: 64, alignment: .trailing)
            }
            if let notice = app.notice { NoticeLine(app: app, text: notice).padding(.top, 8) }
        }
    }

    @ViewBuilder private func action(_ model: ModelStore.Model) -> some View {
        if app.downloading == model.id, app.verifying {
            Text("Checking…").foregroundStyle(.secondary).font(.system(size: 12))
        } else if app.downloading == model.id {
            Button("\(Int(app.downloadFraction * 100))%  ✕") { app.store.cancel() }.help("Stop the download")
        } else if app.isActive(model) {
            Text("In use").foregroundStyle(.secondary).font(.system(size: 12))
        } else if app.store.has(model) {
            HStack {
                if app.canDelete(model) { Button("Delete") { app.delete(model) }.help("Removes the file. Get downloads it again.") }
                Button("Use") { app.use(model) }
            }
        } else {
            Button("Get") { app.use(model) }.disabled(app.downloading != nil)
        }
    }
}

private struct AppsPage: View {
    @ObservedObject var app: App
    var body: some View {
        Plain(title: "Paused Apps") {
            Text("Itda stays quiet in these apps, and Tab is theirs.").foregroundStyle(.secondary).padding(.bottom, 12)
            ForEach(app.pausedApps.sorted(), id: \.self) { id in
                Row(title: App.displayName(id)) { Button("Remove") { app.pausedApps.remove(id) } }
            }
            Divider()
            Button("Add App…", action: app.pauseAnApp).padding(.top, 12)
        }
    }
}

private struct GeneralPage: View {
    @ObservedObject var app: App
    var body: some View {
        Plain(title: "General") {
            Row(title: "Start at Login") { Toggle("", isOn: $app.startAtLogin).toggleStyle(.switch).controlSize(.small).tint(.primary).labelsHidden() }
            if app.isRelease {
                Row(title: "Update Automatically", note: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                    Button("Check Now", action: app.checkForUpdates)
                    Toggle("", isOn: $app.updatesAutomatically).toggleStyle(.switch).controlSize(.small).tint(.primary).labelsHidden()
                }
            }
            Row(title: "Next word") { key("Tab") }
            Row(title: "Whole suggestion") { key("⇧ Tab") }
            Row(title: "Hide the suggestion") { key("Esc") }
            Divider()
            Text("Everything runs on this Mac. Nothing you type is saved or sent.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
        }
    }
    private func key(_ name: String) -> some View {
        Text(name).font(.system(size: 11.5)).padding(.horizontal, 6).padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
    }
}

extension App {
    /// While the window is open Itda is an ordinary app, in the Dock and Cmd-Tab. Without the window it is only the menu bar icon again.
    func showWindow() {
        if window == nil {
            let host = NSHostingController(rootView: Root(app: self))
            let made = NSWindow(contentViewController: host)
            made.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            made.titlebarAppearsTransparent = true
            made.titleVisibility = .hidden
            made.title = "Itda"
            made.isReleasedWhenClosed = false
            made.delegate = self
            made.setContentSize(CGSize(width: 720, height: 500))
            made.center()
            window = made
            accepted = false
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ note: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }

    /// With no menu an ordinary app has no Cmd-C, Cmd-V, Cmd-W or Cmd-Q.
    func installMainMenu() {
        func menu(_ title: String, _ items: [(String, Selector, String)]) -> NSMenuItem {
            let holder = NSMenuItem()
            holder.submenu = NSMenu(title: title)
            for item in items { holder.submenu!.addItem(withTitle: item.0, action: item.1, keyEquivalent: item.2) }
            return holder
        }
        let main = NSMenu()
        main.addItem(menu("Itda", [("Quit Itda", #selector(NSApplication.terminate(_:)), "q")]))
        main.addItem(menu("Edit", [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"),
                                   ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")]))
        main.addItem(menu("Window", [("Close", #selector(NSWindow.performClose(_:)), "w"), ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")]))
        NSApp.mainMenu = main
    }

    static func displayName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
    }

    func pauseAnApp() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [.application]
        open.directoryURL = URL(fileURLWithPath: "/Applications")
        guard open.runModal() == .OK, let id = open.url.flatMap(Bundle.init(url:))?.bundleIdentifier else { return }
        pausedApps.insert(id)
    }

    /// The system's prompt comes once a launch, and a second click goes where it would have sent you.
    func askForAccessibility() {
        if askedForAccessibility {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            askedForAccessibility = true
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    /// Sparkle holds this. Checking and installing go together: an update that only nags isn't what the switch says.
    var updatesAutomatically: Bool {
        get { updates.updater.automaticallyChecksForUpdates && updates.updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updates.updater.automaticallyChecksForUpdates = newValue
            updates.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// The system holds this, not us. A registration awaiting approval shows as off, and goes to where it can be approved.
    var startAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            // On failure `get` still reads the system's answer, so the switch shows the truth.
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        }
    }
}
