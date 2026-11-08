import AppKit
import Charts
import HalftypeCore
import ServiceManagement
import SwiftUI

/// The one window: a field to type in, in the manner of Ollama's app, with plain pages behind a sidebar. It exists only while open.
struct Root: View {
    @ObservedObject var app: App
    /// Stays in memory, and goes when the window closes.
    @State private var draft = ""
    @State private var sidebar: Bool
    @State private var page: Page
    /// The last Tab taken in this window, which the field breathes with.
    @State private var tab: Date?
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.controlActiveState) private var active

    private let picking: Bool

    init(app: App, page: Page = .field, sidebar: Bool = false, picking: Bool = false) {
        self.app = app
        self.picking = picking
        _page = State(initialValue: page)
        _sidebar = State(initialValue: sidebar)
    }

    enum Page: String, CaseIterable { case field = "Try It", stats = "Stats", models = "Models", apps = "Apps", general = "General" }

    var body: some View {
        HStack(spacing: 0) {
            if sidebar { side.transition(.move(edge: .leading)) }
            ZStack {
                switch page {
                case .field: FieldPage(app: app, draft: $draft, page: $page, picking: picking, tab: tab)
                case .stats: StatsPage(app: app)
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
        .background { Backdrop(ribbon: page == .field) }
        // The icon's cream tile, in dark mode too (docs/design/home-glass).
        .preferredColorScheme(.light)
        // A Tab in another app, with this window behind it, isn't this window's.
        .onChange(of: app.tabs) { if !still, active == .key { tab = .now } }
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

/// The app icon's cursive h (docs/icon/menubar.svg, on an 18-point grid): an inked stem, then an arch that thins into the icon's blue and peach.
private struct Mark: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 18
            let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * s, y: y * s) }
            var stem = Path(), arch = Path()
            stem.move(to: p(8.4, 3.6)); stem.addCurve(to: p(4.9, 4.6), control1: p(7.6, 1.6), control2: p(5, 1.7))
            stem.addCurve(to: p(4.6, 15.6), control1: p(4.8, 7.5), control2: p(4.7, 11.5))
            arch.move(to: p(4.9, 12.2)); arch.addCurve(to: p(10.2, 8.4), control1: p(6.5, 9.4), control2: p(8.7, 8))
            arch.addCurve(to: p(11.3, 13.4), control1: p(11.8, 8.8), control2: p(11.2, 11.6))
            arch.addCurve(to: p(15.2, 13.9), control1: p(11.4, 15.4), control2: p(13.2, 15.6))
            let line = StrokeStyle(lineWidth: 1.9 * s, lineCap: .round, lineJoin: .round)
            context.stroke(arch, with: .linearGradient(Gradient(colors: [.primary, Color(red: 0.663, green: 0.804, blue: 0.941), Color(red: 0.965, green: 0.765, blue: 0.643).opacity(0.7)]),
                                                     startPoint: p(5.5, 0), endPoint: p(15.2, 0)), style: line)
            context.stroke(stem, with: .color(.primary), style: line)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

private struct FieldPage: View {
    @ObservedObject var app: App
    @Binding var draft: String
    @Binding var page: Root.Page
    /// The last Tab taken here, which the field breathes with.
    var tab: Date?
    @FocusState private var focused: Bool
    @State private var picking: Bool
    /// The watcher's reason once it has held for a moment, so typing doesn't flicker the line.
    @State private var settled: Watcher.Why

    init(app: App, draft: Binding<String>, page: Binding<Root.Page>, picking: Bool = false, tab: Date? = nil) {
        self.app = app
        self.tab = tab
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
            Text("Halftype needs to see what you type. It stays on this Mac.").foregroundStyle(.secondary)
            Button("Allow Accessibility", action: app.askForAccessibility).buttonStyle(.borderedProminent).tint(.primary).buttonBorderShape(.capsule)
        }
    }

    private var field: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(!app.on ? "Halftype is off" : app.ready ? "Type here, then press Tab on the grey text" : "Type here once the model is ready")
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
                    HStack(spacing: 6) {
                        if app.loadingName != nil { ProgressView().controlSize(.mini) }
                        Text(app.loadingName ?? app.activeName)
                    }
                    .font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 4).background(Color(nsColor: .textBackgroundColor), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(app.loadingName.map { "Loading model: \($0)" } ?? "Model: \(app.activeName)")
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
                .help(app.on ? "Halftype is on. Click to turn it off." : "Halftype is off. Click to turn it on.")
                .accessibilityLabel(app.on ? "Turn Halftype off" : "Turn Halftype on")
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 9, trailing: 10))
        .pane()
        .keyframeAnimator(initialValue: 1.0, trigger: tab) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
            CubicKeyframe(1.006, duration: 0.25)
            CubicKeyframe(1, duration: 0.45)
        }
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

extension View {
    /// A milky pane over the ribbon, as in the design. Not `.glassEffect`: it decides its text colour from what's behind, which went dark on a dark window in our off-screen shots.
    func pane() -> some View {
        background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
    }
}

/// The window's ground, from the icon: its cream tile, and on the field page its arch drawn large and out of focus, blue to peach.
private struct Backdrop: View {
    var ribbon: Bool
    var body: some View {
        Color(red: 0.965, green: 0.945, blue: 0.914)
            .overlay {
                if ribbon {
                    Canvas { context, size in
                        // The arch on a 720 x 460 window, scaled to this one.
                        let s = CGSize(width: size.width / 720, height: size.height / 460)
                        let p = { (x: CGFloat, y: CGFloat) in CGPoint(x: x * s.width, y: y * s.height) }
                        var arch = Path()
                        arch.move(to: p(40, 400)); arch.addCurve(to: p(400, 150), control1: p(160, 200), control2: p(300, 120))
                        arch.addCurve(to: p(520, 370), control1: p(500, 180), control2: p(470, 330))
                        arch.addCurve(to: p(700, 320), control1: p(570, 410), control2: p(640, 380))
                        context.addFilter(.blur(radius: 26))
                        context.opacity = 0.75
                        context.stroke(arch, with: .linearGradient(Gradient(colors: [Color(red: 0.561, green: 0.733, blue: 0.91), Color(red: 0.875, green: 0.906, blue: 0.937), Color(red: 0.957, green: 0.706, blue: 0.549)]),
                                                                   startPoint: p(60, 0), endPoint: p(680, 0)),
                                       style: StrokeStyle(lineWidth: 90 * s.width, lineCap: .round))
                    }
                }
            }
            .accessibilityHidden(true)
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
            .padding(EdgeInsets(top: 16, leading: 20, bottom: 18, trailing: 20))
            .pane()
            .frame(maxWidth: 520, alignment: .leading)
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

/// Today in three numbers, the last two weeks as bars, and all time in a line. Hovering a bar shows that day.
private struct StatsPage: View {
    @ObservedObject var app: App
    @State private var picked: Date?
    private static let days = 14

    var body: some View {
        // shortcut: a suggestion shown before midnight and taken after counts on two days, so the share is capped at 100%.
        let today = app.tally.last(1)[0].day
        let weeks = app.tally.last(Self.days)
        Plain(title: "Stats") {
            HStack(alignment: .lastTextBaseline, spacing: 36) {
                Figure(value: today.tabs.formatted(), label: today.tabs == 1 ? "Tab today" : "Tabs today", big: true)
                Figure(value: today.characters.formatted(), label: "letters typed for you")
                Figure(value: today.shown == 0 ? "–" : min(1, Double(today.taken) / Double(today.shown)).formatted(.percent.precision(.fractionLength(0))),
                       label: "of suggestions taken")
            }
            .padding(.vertical, 18)
            Divider()
            Text(caption(weeks)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().padding(.top, 16).padding(.bottom, 8)
            Chart(weeks, id: \.date) { entry in
                BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Tabs", entry.day.tabs), width: .ratio(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(Color.primary.opacity(highlighted(entry.date) ? 0.85 : 0.18))
            }
            .chartXSelection(value: $picked)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { AxisGridLine(); AxisValueLabel() } }
            .frame(height: 140)
            personal
            Text(footnote).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 20)
        }
    }

    /// Days with the personal model against days without, once there are both.
    @ViewBuilder private var personal: some View {
        let with = app.tally.sum(personal: true), without = app.tally.sum(personal: false)
        if let a = with.sum.byTab, let b = without.sum.byTab {
            Divider().padding(.top, 20)
            HStack(alignment: .lastTextBaseline, spacing: 36) {
                Figure(value: a.formatted(.percent.precision(.fractionLength(1))), label: "typed by Tab with your model, \(with.count) \(with.count == 1 ? "day" : "days")")
                Figure(value: b.formatted(.percent.precision(.fractionLength(1))), label: "without it, \(without.count) \(without.count == 1 ? "day" : "days")")
            }
            .padding(.top, 18)
        }
    }

    private func highlighted(_ date: Date) -> Bool { Calendar.current.isDate(date, inSameDayAs: picked ?? Date()) }

    /// The hovered day, or else the two weeks in sum.
    private func caption(_ weeks: [(date: Date, day: Tally.Day)]) -> String {
        if let picked, let entry = weeks.first(where: { Calendar.current.isDate($0.date, inSameDayAs: picked) }) {
            return "\(entry.date.formatted(.dateTime.weekday(.wide).month().day())): \(entry.day.tabs) Tabs, \(entry.day.characters) letters"
        }
        let tabs = weeks.reduce(0) { $0 + $1.day.tabs }
        return "Last \(Self.days) days: \(tabs.formatted()) Tabs"
    }

    private var footnote: String {
        let total = app.tally.total
        guard total.tabs > 0 else { return "Press Tab on grey text and it counts here. Only counts are kept, never what you type." }
        return "\(total.tabs.formatted()) Tabs and \(total.characters.formatted()) letters in all. Only counts are kept, never what you type."
    }
}

private struct Figure: View {
    let value: String
    let label: String
    var big = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: big ? 44 : 26, weight: big ? .semibold : .regular)).monospacedDigit()
                .contentTransition(.numericText()).animation(.snappy, value: value)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

private struct ModelsPage: View {
    @ObservedObject var app: App
    @State private var deleting: ModelStore.Model?
    var body: some View {
        Plain(title: "Models") {
            ForEach(ModelStore.models) { model in
                Row(title: model.name, note: model.note) {
                    if app.canDelete(model) {
                        Button { deleting = model } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Delete the downloaded file")
                    }
                    Text(model.sizeText).foregroundStyle(.secondary).font(.system(size: 12))
                    action(model).frame(width: Self.column)
                }
            }
            ForEach(app.ownModels, id: \.self) { path in
                Row(title: App.fileName(path), note: "Your own, from \(URL(fileURLWithPath: path).deletingLastPathComponent().path)") {
                    if app.isLoading(path: path) {
                        loading
                    } else if app.isActive(path: path) {
                        Text("In use").foregroundStyle(.secondary).font(.system(size: 12)).frame(width: Self.column)
                    } else {
                        Button("Forget") { app.forgetOwnModel(path) }.help("Takes it off this list. The file stays.")
                        wide("Use") { app.use(path: path) }
                    }
                }
            }
            Row(title: "Add Your Own GGUF") {
                wide("Choose…", app.chooseModel)
            }
            if let notice = app.notice { NoticeLine(app: app, text: notice).padding(.top, 8) }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let deleting { app.delete(deleting) } }
        } message: {
            Text("It frees \(deleting?.sizeText ?? ""). You can get it again here.")
        }
    }

    /// One width for every button and state in the last column, so their edges line up.
    private static let column: CGFloat = 80
    private func wide(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }.frame(width: Self.column)
    }

    private var loading: some View {
        HStack(spacing: 5) { ProgressView().controlSize(.mini); Text("Loading").font(.system(size: 12)).foregroundStyle(.secondary) }.frame(width: Self.column)
    }

    @ViewBuilder private func action(_ model: ModelStore.Model) -> some View {
        if app.downloading == model.id, app.verifying {
            Text("Checking…").foregroundStyle(.secondary).font(.system(size: 12))
        } else if app.downloading == model.id {
            wide("\(Int(app.downloadFraction * 100))%  ✕") { app.store.cancel() }.help("Stop the download")
        } else if app.isLoading(model) {
            loading
        } else if app.isActive(model) {
            Text("In use").foregroundStyle(.secondary).font(.system(size: 12))
        } else if app.store.has(model) {
            wide("Use") { app.use(model) }
        } else {
            wide("Get") { app.use(model) }.disabled(app.downloading != nil)
        }
    }
}

private struct AppsPage: View {
    @ObservedObject var app: App
    var body: some View {
        Plain(title: "Paused Apps") {
            Text("Halftype stays quiet in these apps, and Tab is theirs.").foregroundStyle(.secondary).padding(.bottom, 12)
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
            Row(title: "Length", note: "Longer suggestions are wrong more often.") {
                Picker("", selection: $app.length) { Text("Short").tag(Length.short); Text("Medium").tag(Length.medium); Text("Long").tag(Length.long) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            Row(title: "How Often", note: "More often means more wrong ones.") {
                Picker("", selection: $app.often) { Text("Less").tag(Often.less); Text("Normal").tag(Often.normal); Text("More").tag(Often.more); Text("Always").tag(Often.always) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 280)
            }
            if let path = app.activePath, App.adapterFile(for: path) != nil {
                Row(title: "Personal Model", note: "Trained on your writing. Compare leaves it off every other day, for Stats.") {
                    Picker("", selection: $app.personal) { Text("Off").tag(Personal.off); Text("Compare").tag(Personal.compare); Text("On").tag(Personal.on) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }
            }
            Row(title: "Next word") { key("Tab") }
            Row(title: "Whole suggestion") { key("⇧ Tab") }
            Row(title: "Hide the suggestion") { key("Esc") }
            Divider()
            Text("Everything runs on this Mac. Nothing you type is sent, and only counts are saved, never text.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
        }
    }
    private func key(_ name: String) -> some View {
        Text(name).font(.system(size: 11.5)).padding(.horizontal, 6).padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
    }
}

extension App {
    /// While the window is open Halftype is an ordinary app, in the Dock and Cmd-Tab. Without the window it is only the menu bar icon again.
    func showWindow() {
        if window == nil {
            let host = NSHostingController(rootView: Root(app: self))
            let made = NSWindow(contentViewController: host)
            made.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            made.titlebarAppearsTransparent = true
            made.titleVisibility = .hidden
            made.title = "Halftype"
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
        main.addItem(menu("Halftype", [("Quit Halftype", #selector(NSApplication.terminate(_:)), "q")]))
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
