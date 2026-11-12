import AppKit
import Charts
import HalftypeCore
import ServiceManagement
import SwiftUI

/// The one window: a sidebar that stays, and one page at a time (docs/design/settings-pages, B). Try It is the first page, the field alone.
/// Every page starts below the title bar, so nothing slides under the traffic lights.
struct Root: View {
    @ObservedObject var app: App
    /// Stays in memory while the window is open, across pages.
    @State private var draft = ""
    @State private var page: Page
    private let onboardingStep: Onboarding.Step

    /// `page` is where the window opens, for the window shots.
    init(app: App, page: Page = .field, onboardingStep: Onboarding.Step = .welcome) {
        self.app = app
        self.onboardingStep = onboardingStep
        _page = State(initialValue: page)
    }

    enum Page: String, CaseIterable, Identifiable {
        case field = "Try It", stats = "Stats", models = "Models", suggestions = "Suggestions", apps = "Apps", general = "General"
        var id: Self { self }
        var symbol: String {
            switch self {
            case .field: "play"; case .stats: "chart.bar"; case .models: "square.stack.3d.up"; case .suggestions: "text.cursor"
            case .apps: "square.grid.2x2"; case .general: "gearshape"
            }
        }
    }

    var body: some View {
        Group {
            if app.onboarding { Onboarding(app: app, step: onboardingStep).ignoresSafeArea() } else { home }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 480, idealHeight: 600)
        // The icon's cream tile.
        .background(Root.cream)
        // Cream in dark mode too (docs/design/home-glass).
        .preferredColorScheme(.light)
    }

    private var home: some View {
        HStack(spacing: 0) {
            sidebar.ignoresSafeArea()
            Divider().opacity(0.5).ignoresSafeArea()
            Group {
                if page == .field {
                    FieldPage(app: app, draft: $draft).background { Arch() }.clipped().ignoresSafeArea()
                } else {
                    // Inside the safe area, which the title bar sets: a page scrolls out of sight below it instead of under it.
                    ScrollView { settings.frame(maxWidth: 560).padding(.horizontal, 32).padding(.vertical, 24).frame(maxWidth: .infinity) }
                        .id(page)  // Each page opens at its top.
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var settings: some View {
        switch page {
        case .field: EmptyView()
        case .stats: StatsPage(app: app)
        case .models: ModelsPage(app: app)
        case .suggestions: SuggestionsPage(app: app)
        case .apps: AppsPage(app: app)
        case .general: GeneralPage(app: app)
        }
    }

    /// Every page, the one showing marked by a peach icon, and the on switch at the foot.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Page.allCases) { item($0) }
            Spacer()
            Toggle("On", isOn: $app.on).toggleStyle(.switch).controlSize(.mini).tint(.primary).padding(.horizontal, 10)
        }
        .padding(EdgeInsets(top: 44, leading: 8, bottom: 12, trailing: 8))
        .frame(width: 168)
        .frame(maxHeight: .infinity)
        .background(Color.white.opacity(0.3))
    }

    private func item(_ shown: Page) -> some View {
        Button { page = shown } label: {
            HStack(spacing: 8) {
                Image(systemName: shown.symbol).font(.system(size: 12, weight: .medium)).frame(width: 16)
                    .foregroundStyle(page == shown ? AnyShapeStyle(Root.peach) : AnyShapeStyle(.secondary))
                Text(shown.rawValue).font(.system(size: 13)).foregroundStyle(page == shown ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(page == shown ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityAddTraits(page == shown ? .isSelected : [])
        // Try It stands apart from the pages about Halftype itself.
        .padding(.bottom, shown == .field ? 10 : 0)
    }

    /// The ribbon's peach, deeper, for small marks on cream.
    static let peach = Color(red: 0.9, green: 0.58, blue: 0.42)
    /// The icon's cream tile, the window's ground and the Settings card's.
    static let cream = Color(red: 0.965, green: 0.945, blue: 0.914)
}

/// The app icon's cursive h (docs/icon/menubar.svg, on an 18-point grid): an inked stem, then an arch that thins into the icon's blue and peach.
struct Mark: View {
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

struct FieldPage: View {
    @ObservedObject var app: App
    @Binding var draft: String
    /// The mark above, the room below and the line that teaches the keys, which onboarding's lessons draw their own way.
    var chrome = true
    /// A lesson's keys, drawn in the field's foot.
    var keycaps: [String] = []
    @FocusState private var focused: Bool
    /// The watcher's reason once it has held for a moment, so typing doesn't flicker the line.
    @State private var settled: Watcher.Why

    init(app: App, draft: Binding<String>, chrome: Bool = true, keycaps: [String] = []) {
        self.app = app
        self.chrome = chrome
        self.keycaps = keycaps
        _draft = draft
        _settled = State(initialValue: app.why)
    }

    var body: some View {
        VStack(spacing: 16) {
            if chrome { Mark() }
            if app.trusted { field } else { allow }
            if chrome { status }
        }
        .padding(.horizontal, 24).padding(.vertical, chrome ? 24 : 12)
        .padding(.bottom, chrome ? 40 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allow: some View {
        VStack(spacing: 12) {
            Text("Halftype needs to see what you type. It stays on this Mac.").foregroundStyle(.secondary)
            Button("Allow Accessibility", action: app.askForAccessibility).buttonStyle(Ink())
        }
    }

    private var field: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text(!app.on ? "Halftype is off" : app.ready || app.practicing ? "Type anything." : "Type here once the model is ready")
                        .foregroundStyle(.tertiary).padding(.leading, 5).allowsHitTesting(false)
                }
                TextEditor(text: $draft).focused($focused).scrollContentBackground(.hidden).scrollIndicators(.never).frame(height: 44)
            }
            .font(.system(size: 15))
            if !keycaps.isEmpty {
                HStack(spacing: 4) { ForEach(keycaps, id: \.self) { Keycap(label: $0) } }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 9, trailing: 10))
        .pane()
        .frame(maxWidth: 500)
        // A turn later: a field swapped in (an onboarding step, the home after it) isn't in the window yet when it appears.
        // `.defaultFocus` left it unfocused there, so the lesson's first Tab only moved focus (tried live, 2026-11-09).
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: app.ready, initial: true) { if let sentence = app.takePrefill(draft: draft) { draft = sentence } }
        .task(id: app.why) {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { settled = app.why }
        }
    }

    /// How to take a suggestion, always there while Halftype can suggest, so nothing jumps when a ghost appears (docs/design/settings-pages, F2).
    private var keys: some View {
        HStack(spacing: 18) {
            ForEach([("Tab", "next word"), ("⇧ Tab", "all of it"), ("Esc", "hide")], id: \.0) { key, does in
                HStack(spacing: 7) { Keycap(label: key); Line(text: does) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The model until it's ready, then the keys, and under them why there's no suggestion when something is in the way.
    @ViewBuilder private var status: some View {
        VStack(spacing: 6) {
            if (!app.ready && !app.practicing) || app.notice != nil {
                NoticeLine(app: app, text: app.notice ?? app.modelLine)
                if !app.ready, app.downloading != nil {
                    ProgressView(value: app.downloadFraction).frame(width: 160).tint(.primary)
                    Line(text: "You can close this window.")
                }
            } else if chrome, app.line(for: settled) != nil {
                // The keys stay while you type (John, 2026-11-13); a reason shows under them, in room kept so they never move.
                keys
                Line(text: app.fieldLine(settled) ?? " ")
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

/// The icon's arch drawn large and out of focus, blue to peach, behind the field (docs/design/home-glass).
struct Arch: View {
    var body: some View {
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

struct Line: View {
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

/// One page of the settings: its title and a line on what it's for on the cream, then its rows in a white pane, parted by space alone
/// (docs/design/settings-clean, C; settings-pages, B).
private struct Plain<Content: View>: View {
    let title: String
    let note: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 26, weight: .semibold))
            Text(note).font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 3).padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                .pane()
        }
    }
}

/// What leads a row: a model's maker, an app's own icon, or a symbol.
private enum Icon {
    case logo(String), app(NSImage), symbol(String)

    static func maker(of model: ModelStore.Model) -> Icon? { model.logo.map(Icon.logo) }
}

private struct Row<Trailing: View>: View {
    let title: String
    var note: String? = nil
    var icon: Icon? = nil
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 10) {
            if let icon { tile(icon) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 12)
    }

    /// The makers' marks come from Logos/: a PNG fills its tile, a PDF sits on white, as both are drawn for a light ground.
    @ViewBuilder private func tile(_ icon: Icon) -> some View {
        switch icon {
        case .logo(let file):
            let image = Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Logos").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
            if file.hasSuffix(".png") {
                Image(nsImage: image).resizable().interpolation(.high).frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 18, height: 18).frame(width: 28, height: 28)
                    .background(.white, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.1), lineWidth: 0.5))
            }
        case .app(let image):
            Image(nsImage: image).resizable().frame(width: 30, height: 30).padding(-1)
        case .symbol(let name):
            Image(systemName: name).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
    }
}

/// A segmented choice in the window's ink: macOS paints a selected `.segmented` Picker in the system accent, blue on our cream
/// (John, 2026-11-13), so the chosen one is a white pill instead.
private struct Choice<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    init(selection: Binding<Value>, _ options: [(Value, String)]) { _selection = selection; self.options = options }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                let on = value == selection
                Button { selection = value } label: {
                    Text(title).font(.system(size: 12, weight: on ? .medium : .regular)).foregroundStyle(on ? .primary : .secondary)
                        .padding(.horizontal, 11).padding(.vertical, 3)
                        .background { if on { RoundedRectangle(cornerRadius: 6).fill(.white).shadow(color: .black.opacity(0.12), radius: 1, y: 0.5) } }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
        .animation(.easeOut(duration: 0.12), value: selection)
    }
}

/// A week or a month as bars, paged back with arrows, or every day as a dot; the numbers follow what's showing (docs/design/stats round 2, B).
/// Time saved leads, in one sentence, with the other counts as chips below (round 5, E).
struct StatsPage: View {
    enum Span: String, CaseIterable { case week = "Week", month = "Month", all = "All" }
    /// Where the page opens, for the window shots.
    nonisolated(unsafe) static var opening = Span.week

    @ObservedObject var app: App
    @State private var span = StatsPage.opening
    /// How many weeks or months back.
    @State private var back = 0
    @State private var picked: Date?
    @State private var hovered: Date?
    private let calendar = Calendar.current

    var body: some View {
        let period = span == .all ? nil : Tally.period(span == .week ? .weekOfYear : .month, back: back, now: Date(), calendar)
        let shown = period.map { app.tally.sum($0.elapsed, to: day($0.elapsed - 1, of: $0.start), calendar) } ?? app.tally.total
        // Nothing to compare with until counting had begun by the end of the stretch before; after that a quiet stretch counts as 0.
        let before = period.flatMap { period -> Tally.Day? in
            let last = day(period.previousLength - 1, of: period.previousStart)
            guard period.previousLength > 0, let since = app.tally.since, since <= Tally.key(last, calendar) else { return nil }
            return app.tally.sum(period.previousLength, to: last, calendar)
        }
        Plain(title: "Stats", note: "What Tab has typed for you. Only counts are kept, never what you type.") {
            HStack {
                if let period {
                    Button { back += 1; picked = nil } label: { Image(systemName: "chevron.left") }.disabled(oldest(period)).help("Earlier")
                    Button { back -= 1; picked = nil } label: { Image(systemName: "chevron.right") }.disabled(back == 0).help("Later")
                }
                Text(heading(period)).font(.system(size: 13, weight: .medium))
                Spacer()
                Choice(selection: $span, Span.allCases.map { ($0, $0.rawValue) })
            }
            .buttonStyle(.borderless)
            .padding(.top, 6)
            .onChange(of: span) { back = 0; picked = nil; hovered = nil }
            headline(shown, period).padding(.top, 18)
            HStack(spacing: 8) {
                Chip(value: shown.wordCount.formatted(), label: shown.wordCount == 1 ? "word" : "words", help: "Words Tab typed for you, whole or in part.")
                if let n = shown.oneIn { Chip(value: "1 in \(n)", label: "keys by Tab", help: "Of all the keys you typed, Tab typed one in \(n) for you.") }
                Chip(value: shown.tabs.formatted(), label: shown.tabs == 1 ? "Tab" : "Tabs", help: "How many times you pressed Tab to take a suggestion.")
            }
            .padding(.top, 12)
            Text(caption(period, before)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().padding(.top, 24).padding(.bottom, 8)
            if let period { bars(period) } else { dots }
            personal.padding(.bottom, 8)
        }
    }

    private func day(_ offset: Int, of start: Date) -> Date { calendar.date(byAdding: .day, value: offset, to: start) ?? start }

    /// Nothing was counted before the period starts.
    private func oldest(_ period: Tally.Period) -> Bool { app.tally.since.map { Tally.key(period.start, calendar) <= $0 } ?? true }

    private func heading(_ period: Tally.Period?) -> String {
        guard let period else { return app.tally.since.flatMap { since in Self.keyFormat.date(from: since) }.map { "Since \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "All" }
        if back == 0 { return span == .week ? "This week" : "This month" }
        if span == .month { return period.start.formatted(calendar.isDate(period.start, equalTo: Date(), toGranularity: .year) ? .dateTime.month(.wide) : .dateTime.month(.wide).year()) }
        return (period.start..<day(period.length - 1, of: period.start)).formatted(.interval.month(.abbreviated).day())
    }
    private static let keyFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

    /// "Halftype saved you 21 minutes of typing this week.", the time in the icon's glass.
    private func headline(_ day: Tally.Day, _ period: Tally.Period?) -> some View {
        let end = period == nil ? " so far." : back > 0 ? "." : span == .week ? " this week." : " this month."
        let time = Text(Self.time(app.tally.minutes(day)) + " of typing").fontWeight(.semibold).foregroundStyle(StatsPage.glass)
        let sentence = day.tabs == 0 ? Text("Nothing typed by Tab" + end) : Text("Halftype saved you \(time)\(end)")
        return sentence.foregroundStyle(.secondary).font(.system(size: 22)).fixedSize(horizontal: false, vertical: true)
            .help(app.tally.speed.map { "Keys Tab typed for you, at your typing speed: \(Int($0.rounded())) keys a minute." }
                  ?? "Keys Tab typed for you, at 40 words a minute (200 keys), until Halftype has timed a minute of your typing.")
    }

    /// The icon's glass, pale blue to peach, darkened to read on cream.
    static let glass = LinearGradient(colors: [Color(red: 0.36, green: 0.58, blue: 0.84), Color(red: 0.88, green: 0.50, blue: 0.32)], startPoint: .leading, endPoint: .trailing)

    /// "21 minutes", "1 hour, 12 minutes", or under a minute.
    static func time(_ minutes: Double) -> String {
        let whole = Int(minutes.rounded())
        if whole == 0 { return "under a minute" }
        return Duration.seconds(whole * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    private func caption(_ period: Tally.Period?, _ before: Tally.Day?) -> String {
        if let hovered {
            let day = app.tally.last(1, to: hovered, calendar)[0].day
            return "\(hovered.formatted(.dateTime.weekday(.wide).month().day())): \(Self.time(app.tally.minutes(day))) saved, \(day.wordCount.formatted()) words"
        }
        guard let period else { return "Each dot is a day, bigger for more time saved." }
        guard let before else { return "" }
        let stretch = back > 0 ? (span == .week ? "The week before" : "The month before")
            : period.elapsed == 1 ? "The same day last \(span == .week ? "week" : "month")" : "The same \(period.previousLength) days last \(span == .week ? "week" : "month")"
        return "\(stretch): \(Self.time(app.tally.minutes(before)))"
    }

    /// The period's days as bars; hovering one shows it in a tag above.
    private func bars(_ period: Tally.Period) -> some View {
        let days = app.tally.last(period.length, to: day(period.length - 1, of: period.start), calendar)
        return Chart {
            ForEach(days, id: \.date) { entry in
                BarMark(x: .value("Day", entry.date, unit: .day), y: .value("Minutes", app.tally.minutes(entry.day)), width: .ratio(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(Color.primary.opacity(lit(entry.date) ? 0.85 : 0.18))
            }
            if let picked, let entry = days.first(where: { calendar.isDate($0.date, inSameDayAs: picked) }) {
                RuleMark(x: .value("Day", entry.date, unit: .day)).foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) { Tag(date: entry.date, day: entry.day, minutes: app.tally.minutes(entry.day)) }
            }
        }
        .chartXSelection(value: $picked)
        .chartXAxis {
            if span == .week {
                AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true) }
            } else {
                // At noon, the middle of each day's bar: a stride of 7 days would centre each label on its whole week.
                AxisMarks(values: [0, 7, 14, 21, 28].compactMap { calendar.date(byAdding: .hour, value: 12, to: day($0, of: period.start)) }) { _ in AxisValueLabel(format: .dateTime.day()) }
            }
        }
        // Only the baseline: a day's number is in its tag (round 5).
        .chartYAxis { AxisMarks(values: [0]) { _ in AxisGridLine() } }
        .frame(height: 140)
    }

    private func lit(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: picked ?? Date()) }

    /// The last 26 weeks, one dot a day in the sky's halftone, bigger for more time saved. Days before counting began are specks.
    private var dots: some View {
        let weeks = 26, cell: CGFloat = 18
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let first = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
        let all = app.tally.last(weeks * 7, to: day(weeks * 7 - 1, of: first), calendar)
        let most = max(1, all.map(\.day.saved).max() ?? 1), since = app.tally.since
        return HStack(spacing: 0) {
            ForEach(0..<weeks, id: \.self) { week in
                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { weekday in
                        let entry = all[week * 7 + weekday], key = Tally.key(entry.date, calendar)
                        let future = entry.date > Date(), counted = since.map { key >= $0 } ?? false, today = calendar.isDateInToday(entry.date)
                        let radius = future ? 0 : !counted ? 0.9 : entry.day.saved == 0 ? 1.2 : 1.4 + (cell * 0.42 - 1.4) * sqrt(Double(entry.day.saved) / Double(most))
                        Circle().fill(Color.primary.opacity(today ? 0.88 : counted ? 0.55 : 0.13)).frame(width: radius * 2, height: radius * 2)
                            .frame(width: cell, height: cell)
                            .contentShape(Rectangle())
                            .onHover { inside in if inside, counted { hovered = entry.date } else if hovered == entry.date { hovered = nil } }
                    }
                }
            }
        }
        .accessibilityLabel("Time saved per day for the last 26 weeks")
    }

    /// Days with the personal model against days without, once there are both, and each version's days once more than one has run a whole
    /// day (which checkpoint to keep; with Personal Model On there are no days without). One bar each, from zero, so the gap is true to size.
    @ViewBuilder private var personal: some View {
        let with = app.tally.sum(personal: true), without = app.tally.sum(personal: false)
        let both = with.sum.byTab.flatMap { a in without.sum.byTab.map { b in [Meter(id: "with", label: "With it", share: a, days: with.count, glass: true), Meter(id: "without", label: "Without", share: b, days: without.count, glass: false)] } } ?? []
        let versions = app.tally.adapters.count < 2 ? [] : app.tally.adapters.compactMap { name -> Meter? in
            let one = app.tally.sum(personal: true, adapter: name)
            return one.sum.byTab.map { Meter(id: name, label: "\(AdapterInfo.title(name: name)) version", share: $0, days: one.count, glass: true) }
        }
        let rows = both + versions
        if let most = rows.map(\.share).max() {  // 0 when nothing was saved: empty tracks
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your personal model").font(.system(size: 13, weight: .semibold))
                    Text("Of your typing, how much Tab typed on whole days with it and without.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)
                ForEach(rows, id: \.id) { $0.scaled(to: most) }
            }
            .padding(.top, 32)
        }
    }
}

/// One row of the personal model's comparison: its share of typing by Tab as a bar, the icon's glass for the model, grey without it.
private struct Meter: View {
    /// The adapter's file name: two versions can share a title.
    let id: String
    let label: String
    let share: Double
    let days: Int
    let glass: Bool
    var most = 1.0
    func scaled(to most: Double) -> Meter { var meter = self; meter.most = most; return meter }
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
            GeometryReader { space in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.05))
                    Capsule().fill(glass ? AnyShapeStyle(StatsPage.glass)
                                         : AnyShapeStyle(Color.primary.opacity(0.22)))
                        .frame(width: most > 0 ? space.size.width * share / most : 0)
                }
            }
            .frame(height: 8)
            Text(share.formatted(.percent.precision(.fractionLength(1)))).font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 48, alignment: .trailing)
            Text("\(days) \(days == 1 ? "day" : "days")").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().frame(width: 56, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pro's fake door (docs/pricing.md): the prices, and an email for the early-bird list. No "free": a sign-up should mean they'd pay.
private struct ProSignup: View {
    @ObservedObject var app: App
    @State private var email = ""
    @State private var sending = false
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Personal Model")
                Spacer()
                Text("$4 a month · $36 a year · $99 once").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Text("Coming soon: a model trained on your own typing, and retrained routinely as you type, so suggestions get more accurate and more like you.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if app.signedUp {
                Label("You're on the list. We'll email you when it's ready.", systemImage: "checkmark").font(.system(size: 12)).padding(.top, 4)
            } else {
                HStack {
                    TextField("you@example.com", text: $email).textFieldStyle(.roundedBorder).onSubmit(send)
                    Button("Notify Me", action: send).disabled(sending || address == nil)
                    Button("See Plans") { NSWorkspace.shared.open(App.proPage) }
                }
                .controlSize(.small).padding(.top, 4)
                Text(failed ? "Couldn't send. Check your connection and try again." : "Halftype sends only this address, and only when you press Notify Me.")
                    .font(.system(size: 11)).foregroundStyle(failed ? .red : .secondary)
            }
        }
        .padding(.vertical, 9)
    }
    /// shortcut: one @ and a dot after it, enough to catch a slip; the list's first email shows a wrong one.
    private var address: String? {
        let e = email.trimmingCharacters(in: .whitespaces), parts = e.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !e.contains(" ") ? e : nil
    }
    private func send() {
        guard let address, !sending else { return }
        (sending, failed) = (true, false)
        app.notifyMe(address) { ok in (sending, failed) = (false, !ok) }
    }
}

/// Saved typing (`Typing`): the switch, how long it's kept, what's there, and Delete All. The text is read only into Show's sheet.
private struct SavedTyping: View {
    @ObservedObject var app: App
    @State private var summary: (count: Int, from: Date, to: Date)?
    /// A file is there, read or not: Delete All works even when the Keychain won't open it.
    @State private var exists = false
    @State private var failed = false
    @State private var shown: [Typing.Record]?
    @State private var asking: Ask?
    private enum Ask { case off, delete }
    var body: some View {
        Row(title: "Save What You Type", note: "Encrypted, on this Mac only.") {
            Toggle("", isOn: Binding(get: { app.savesTyping }, set: { on in if on { app.savesTyping = true } else { asking = .off } }))
                .toggleStyle(.switch).controlSize(.small).tint(.primary).labelsHidden()
        }
        .help(Self.explained)
        Row(title: "Keep", note: note) {
            Button("Show") { shown = app.typing?.all().reversed() }.disabled(summary == nil)
            Button("Delete All") { asking = .delete }  // Always: a key can outlive its file, as when the Keychain refused once
            Picker("", selection: $app.keepTyping) {
                Text("1 Month").tag(KeepTyping.oneMonth); Text("6 Months").tag(KeepTyping.sixMonths); Text("1 Year").tag(KeepTyping.year); Text("All").tag(KeepTyping.all)
            }
            .labelsHidden().fixedSize()
        }
        .padding(.leading, 16)
        .onAppear(perform: count)
        .onChange(of: app.keepTyping) { DispatchQueue.main.async(execute: count) }
        .sheet(isPresented: Binding(get: { shown != nil }, set: { if !$0 { shown = nil } })) { sheet }
        .confirmationDialog(asking == .off ? "Stop saving what you type?" : "Delete everything saved?",
                            isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })) {
            Button("Delete All", role: .destructive) {
                if asking == .off { app.savesTyping = false }
                failed = app.typing?.deleteAll() == false
                count()
            }
            if asking == .off { Button("Stop and Keep It") { app.savesTyping = false } }
        } message: {
            Text("Deleted text can't be brought back. Personal Model versions already trained stay until you delete them.")
        }
    }

    /// On hover only: onboarding doesn't mention it (John, 2026-11-11).
    static let explained = "If you get Personal Model, it learns from what you've already written, so it's good from day one. Kept: what you add to a field, with the text on screen before it. Never passwords, paused apps or pastes. Encrypted with a key in your Keychain; sent only for a training you start."

    private var note: String {
        if failed { return "Couldn't delete all of it. Try again, or remove typing.sealed in Application Support." }
        guard let summary else { return exists ? "Saved, but the Keychain didn't open it." : "Nothing saved yet." }
        let range = summary.from.formatted(date: .abbreviated, time: .omitted) + " – " + summary.to.formatted(date: .abbreviated, time: .omitted)
        return "\(summary.count.formatted()) saved, \(range)"
    }

    private func count() {
        let all = app.typing?.all() ?? []
        exists = app.typing?.exists ?? false
        summary = all.first.map { (all.count, $0.date, all.last?.date ?? $0.date) }
    }

    /// In memory only while it's open.
    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved Typing").font(.headline)
                Spacer()
                Button("Done") { shown = nil }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            List(Array((shown ?? []).enumerated()), id: \.offset) { _, record in
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(record.text).textSelection(.enabled)
                    if !record.context.isEmpty {
                        Text(record.context.suffix(200)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .padding(.vertical, 3)
            }
        }
        .frame(width: 560, height: 480)
    }
}

/// A hovered day, dark above its bar.
private struct Tag: View {
    let date: Date
    let day: Tally.Day
    let minutes: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(date.formatted(.dateTime.weekday(.wide).month().day())).foregroundStyle(.white.opacity(0.6))
            Text("\(StatsPage.time(minutes)) saved · \(day.wordCount.formatted()) words")
            Text("\(day.tabs.formatted()) Tabs" + (day.oneIn.map { " · 1 in \($0) keys by Tab" } ?? ""))
        }
        .font(.system(size: 11)).monospacedDigit().foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// One count under the sentence, in faint glass so it doesn't read as a button; hovering says what it means.
private struct Chip: View {
    let value: String
    let label: String
    let help: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(.white.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.09), lineWidth: 0.5))
        .help(help)
    }
}

private struct ModelsPage: View {
    @ObservedObject var app: App
    @State private var deleting: ModelStore.Model?
    var body: some View {
        Plain(title: "Models", note: "They run on this Mac. Bigger ones are better, and slower.") {
            ForEach(ModelStore.models) { model in
                Row(title: model.name, note: model.note, icon: .maker(of: model)) {
                    if app.canDelete(model) {
                        Button { deleting = model } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Delete the downloaded file")
                    }
                    Text(model.sizeText).foregroundStyle(.secondary).font(.system(size: 12))
                    action(model).frame(width: Self.column)
                }
                if app.isActive(model) { PersonalModel(app: app) }
            }
            ForEach(app.ownModels, id: \.self) { path in
                Row(title: App.fileName(path), note: "Your own, from \(URL(fileURLWithPath: path).deletingLastPathComponent().path)", icon: .symbol("doc")) {
                    if app.isLoading(path: path) {
                        loading
                    } else if app.isActive(path: path) {
                        inUse.frame(width: Self.column)
                    } else {
                        Button("Forget") { app.forgetOwnModel(path) }.help("Takes it off this list. The file stays.")
                        wide("Use") { app.use(path: path) }
                    }
                }
                if app.isActive(path: path) { PersonalModel(app: app) }
            }
            Row(title: "Add Your Own GGUF", icon: .symbol("plus")) {
                wide("Choose…", app.chooseModel)
            }
            // Until this model has one of its own: the offer, below every model, as it would be trained for whichever is in use.
            if app.activePath.flatMap(App.adapterFile(for:)) == nil { ProSignup(app: app).padding(.top, 6) }
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

    private var inUse: some View { InUse() }

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
            inUse
        } else if app.store.has(model) {
            wide("Use") { app.use(model) }
        } else {
            wide("Get") { app.use(model) }.disabled(app.downloading != nil)
        }
    }
}

private struct InUse: View {
    var body: some View {
        HStack(spacing: 5) { Circle().fill(Root.peach).frame(width: 6, height: 6); Text("In use").foregroundStyle(.secondary).font(.system(size: 12)) }
    }
}

/// One choice of Tab Motion, as System Settings shows Appearance: a little field playing it, its name under, a ring when chosen.
private struct MotionTile: View {
    let motion: AcceptMotion
    @Binding var chosen: AcceptMotion
    private var name: String { motion.rawValue.capitalized }
    var body: some View {
        let on = chosen == motion
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button { chosen = motion } label: {
            VStack(spacing: 6) {
                MotionPreview(motion: motion)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Color(nsColor: .textBackgroundColor), in: shape)
                    .overlay(shape.strokeBorder(.primary.opacity(0.09)))
                    .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.primary, lineWidth: 1.5).opacity(on ? 1 : 0))
                Text(verbatim: name).font(.system(size: 11.5, weight: on ? .medium : .regular)).foregroundStyle(on ? .primary : .secondary).fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The chosen motion on a loop, drawn by the app's own code: "see you at" takes " noon" with a Tab every 1.8 s.
private struct MotionPreview: View {
    let motion: AcceptMotion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False while the window is behind another app's or the app is hidden: the loop redraws every frame, a fifth of a core
    /// measured idle (2026-11-10), so it plays only while the window is the one in use.
    @Environment(\.appearsActive) private var appearsActive
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !appearsActive)) { timeline in
            Canvas { g, size in
                // Reduce Motion: the words already taken, as the app then plays nothing.
                let t = reduceMotion ? 1.79 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8)
                let typed = g.resolve(Text("see you at").font(.system(size: 12)).foregroundColor(.primary))
                let taken = g.resolve(Text(" noon").font(.system(size: 12)).foregroundColor(.primary.opacity(t < 0.8 ? 0.38 : 1)))
                let tw = typed.measure(in: size).width, nw = taken.measure(in: size).width
                let mid = size.height / 2, left = ((size.width - tw - nw) / 2).rounded(), w = left + tw, all = w + nw
                g.draw(typed, at: CGPoint(x: left, y: mid), anchor: .leading)
                g.draw(taken, at: CGPoint(x: w, y: mid), anchor: .leading)
                let from = CGRect(x: w, y: mid - 7.5, width: 1.5, height: 15), to = CGRect(x: all, y: mid - 7.5, width: 1.5, height: 15)
                g.fill(Path(t < 0.8 ? from : to), with: .color(Color(nsColor: .controlAccentColor)))
                if t >= 0.8, motion != .off {
                    g.withCGContext { AcceptMotion.draw(motion, from: from, to: to, progress: min((t - 0.8) / motion.duration, 1), in: $0) }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct AppsPage: View {
    @ObservedObject var app: App
    var body: some View {
        Plain(title: "Paused Apps", note: "Halftype stays quiet in these apps, and Tab is theirs.") {
            ForEach(app.pausedApps.sorted(), id: \.self) { id in
                Row(title: App.displayName(id), icon: App.icon(id).map(Icon.app)) { Button("Remove") { app.pausedApps.remove(id) } }
            }
            // Running apps first, as AltTab offers them, so most never need the Applications folder. Read again as apps open and quit.
            Menu("Add App") {
                let running = self.running.filter { !app.pausedApps.contains($0) }
                ForEach(running, id: \.self) { id in
                    Button { app.pausedApps.insert(id) } label: {
                        Label { Text(App.displayName(id)) } icon: { App.icon(id).map { Image(nsImage: App.small($0)) } }
                    }
                }
                if !running.isEmpty { Divider() }
                Button("Choose from Disk…", action: app.pauseAnApp)
            }
            .fixedSize()
            .padding(.top, 8)
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in running = App.runningApps(except: []) }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in running = App.runningApps(except: []) }
        }
    }
    @State private var running = App.runningApps(except: [])
}

/// How much it suggests, and how you take it.
private struct SuggestionsPage: View {
    @ObservedObject var app: App
    var body: some View {
        Plain(title: "Suggestions", note: "How much it suggests, and how you take it.") {
            // One line, for the choice made, not a sentence for every choice (docs/design/settings-pages round 2, B).
            let showNote = switch app.often {
                case .always: "Every guess shows; ignore the wrong ones."
                case .more: "Shows when it's fairly sure."
                case .normal: "Only when it's sure."
            }
            Row(title: "Show", note: showNote) {
                Choice(selection: $app.often, [(.always, "Always"), (.more, "When Likely"), (.normal, "When Sure")])
            }
            Row(title: "Length", note: app.length == .short ? "Ends sooner, so more of it is right." : "Goes on further, so a Tab can take more.") {
                Choice(selection: $app.length, [(.long, "Long"), (.short, "Short")])
            }
            // Under its title at full width, as System Settings' Appearance: beside it, three tiles crush the title in a small window.
            VStack(alignment: .leading, spacing: 8) {
                Text("Tab Motion")
                HStack(spacing: 12) { ForEach(AcceptMotion.allCases, id: \.self) { MotionTile(motion: $0, chosen: $app.motion) } }
            }
            .padding(.vertical, 12)
            // No rows for the keys: Try It always shows them (John, 2026-11-13).
        }
    }
}

/// The model's own versions, trained on your writing, under the model they were trained for: a version works with that model only.
private struct PersonalModel: View {
    @ObservedObject var app: App
    @State private var deletingAdapter: String?
    var body: some View {
        if let path = app.activePath, let current = App.adapterFile(for: path) {
            VStack(alignment: .leading, spacing: 0) {
                let note = switch app.personal {
                    case .off: "Trained on your writing. Not used now."
                    case .compare: "Used every other day, so Stats can compare."
                    case .on: "Trained on your writing, and used every day."
                }
                Row(title: "Personal Model", note: note) {
                    Choice(selection: $app.personal, [(.off, "Off"), (.compare, "Compare"), (.on, "On")])
                }
                // Each trained version, newest first: a new one is used on arrival, and an older one can be used again or deleted.
                ForEach(App.adapters(for: path).reversed(), id: \.self) { file in
                    Row(title: AdapterInfo.title(name: App.name(ofAdapter: file)), note: App.info(ofAdapter: file)?.note ?? App.name(ofAdapter: file)) {
                        Button { deletingAdapter = file } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Delete this version")
                        if file == current { InUse().frame(width: 80) } else { Button { app.use(adapter: file) } label: { Text("Use").frame(maxWidth: .infinity) }.frame(width: 80) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 2)
            .background(Root.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .padding(.leading, 38).padding(.bottom, 6)
            .confirmationDialog("Delete the \(deletingAdapter.map { AdapterInfo.title(name: App.name(ofAdapter: $0)) } ?? "") version?", isPresented: Binding(get: { deletingAdapter != nil }, set: { if !$0 { deletingAdapter = nil } })) {
                Button("Delete", role: .destructive) { if let deletingAdapter { app.delete(adapter: deletingAdapter) } }
            } message: {
                Text("It can't be brought back. Stats keeps its days.")
            }
        }
    }
}

/// Halftype itself, and what it keeps.
private struct GeneralPage: View {
    @ObservedObject var app: App
    var body: some View {
        Plain(title: "General", note: "Everything runs on this Mac. Nothing you type is sent.") {
            Row(title: "Start at Login") { Toggle("", isOn: $app.startAtLogin).toggleStyle(.switch).controlSize(.small).tint(.primary).labelsHidden() }
            if app.isRelease {
                Row(title: "Update Automatically", note: "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")") {
                    Button("Check Now", action: app.checkForUpdates)
                    Toggle("", isOn: $app.updatesAutomatically).toggleStyle(.switch).controlSize(.small).tint(.primary).labelsHidden()
                }
            }
            SavedTyping(app: app)
            Row(title: "Show What the Model Sees", note: "Press ⌃⌥ over a suggestion. On screen only.") {
                Toggle("", isOn: $app.peeking).toggleStyle(.switch).controlSize(.small).tint(.primary).labelsHidden()
            }
        }
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
            made.setContentSize(CGSize(width: 860, height: 600))
            made.center()
            window = made
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

    static func icon(_ bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// Apps with a Dock icon now open, but not Halftype or ones already paused, by name.
    static func runningApps(except paused: Set<String>) -> [String] {
        let ids = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier)
        return Set(ids).subtracting(paused).subtracting([Bundle.main.bundleIdentifier ?? ""])
            .sorted { displayName($0).localizedCaseInsensitiveCompare(displayName($1)) == .orderedAscending }
    }

    /// A menu draws an image at its own size, so an app's 512-point icon would fill it.
    static func small(_ image: NSImage) -> NSImage {
        NSImage(size: CGSize(width: 16, height: 16), flipped: false) { image.draw(in: $0); return true }
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
        guide.show()
        if askedForAccessibility {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        } else {
            askedForAccessibility = true
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
    }

    /// Whether Sparkle downloads and installs on its own. The daily check stays on either way (App.swift, where the updater starts), so with this off a new version still shows as the dot.
    var updatesAutomatically: Bool {
        get { updates.updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
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
