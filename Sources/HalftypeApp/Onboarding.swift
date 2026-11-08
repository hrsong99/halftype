import SwiftUI

/// First launch, in four steps (docs/design/onboarding, C): a welcome that shows the product in one sentence, the one permission,
/// Try It with real glass suggestions (practice ones until the model is in), and where Halftype lives. The model downloads all along.
struct Onboarding: View {
    @ObservedObject var app: App
    enum Step: Int, CaseIterable { case welcome, allow, tryIt, done }
    @State private var step: Step
    @State private var draft = ""

    init(app: App, step: Step = .welcome) {
        self.app = app
        _step = State(initialValue: step)
    }

    var body: some View {
        ZStack {
            Arch().padding(.top, -28)
            Group {
                switch step {
                case .welcome: Welcome { next() }
                case .allow: allow
                case .tryIt: tryIt
                case .done: done
                }
            }
            // A fade, not a slide: the ghost is placed where the field's caret is when it's read, and a field still sliding in
            // sends no move, so the suggestion stayed where the slide began (seen live, 2026-11-09).
            .transition(.opacity)
        }
        .overlay(alignment: .top) { top.padding(.top, 14) }
        .animation(.easeInOut(duration: 0.35), value: step)
        // The grant brings the window back in front (App.tapChanged); the step moves on with it.
        .onChange(of: app.trusted) { if app.trusted, step == .allow { step = .tryIt } }
    }

    private func next() {
        guard let after = Step(rawValue: step.rawValue + 1) else { return app.finishOnboarding() }
        step = after == .allow && app.trusted ? .tryIt : after
    }

    /// Where you are, and the download, which starts at launch and carries on under every step.
    private var top: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule().fill(s == step ? Color.primary : Color.primary.opacity(0.18)).frame(width: s == step ? 16 : 6, height: 6)
                }
            }
            if app.downloading != nil || app.verifying {
                VStack(spacing: 4) {
                    ProgressView(value: app.downloadFraction).progressViewStyle(.linear).tint(Root.peach).frame(width: 180)
                    Text(app.modelLine).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var allow: some View {
        VStack(spacing: 12) {
            Mark()
            Text("Let Halftype see what you type").font(.system(size: 24, weight: .semibold))
            Text("To offer the rest of a sentence, it reads the field you're typing in.\nNothing you type leaves this Mac.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open System Settings", action: app.askForAccessibility)
                .buttonStyle(Ink()).padding(.top, 8)
            if app.askedForAccessibility {
                Text("Turn on Halftype in the list. You'll come straight back here.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 40)
    }

    private var tryIt: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Try it").font(.system(size: 24, weight: .semibold))
            FieldPage(app: app, draft: $draft, chrome: false) {}.fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(app.accepted ? "Continue" : "Skip") { next() }
                .buttonStyle(Ink(quiet: !app.accepted)).padding(.bottom, 40)
        }
    }

    private var done: some View {
        VStack(spacing: 12) {
            Mark()
            Text("You're set").font(.system(size: 28, weight: .semibold))
            Text("Halftype lives in the menu bar, up at the top right.\nOpen any app and start typing.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Toggle("Start at login", isOn: $app.startAtLogin).toggleStyle(.switch).tint(.black)
                .padding(.horizontal, 14).padding(.vertical, 8).pane().padding(.top, 8)
            Button("Start Writing") { app.finishOnboarding() }
                .buttonStyle(Ink()).padding(.top, 8)
        }
    }
}

/// The product in one sentence: the first half typed in ink, the rest offered in the icon's glass, then taken with a Tab and its glint,
/// as Try It draws them. Suggestions appear at once, as in the app; only the typing and the glint move. Each frame is a function of
/// the time since it opened, so the window shots can draw any moment.
private struct Welcome: View {
    let onContinue: () -> Void
    static let ink = "Write the first half.", offer = "We'll offer the rest."
    static let typing = 0.5, perLetter = 0.045
    static let offerAt = typing + Double(ink.count) * perLetter + 0.05, takeAt = offerAt + 1.1, restAt = takeAt + 0.45, end = restAt + 0.5
    @State private var start = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: finished)) { context in
            frame(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? Welcome.end : context.date.timeIntervalSince(start))
        }
        .task {
            try? await Task.sleep(for: .seconds(Welcome.end))
            finished = true
        }
    }

    private func frame(_ t: Double) -> some View {
        let typed = min(max(Int((t - Welcome.typing) / Welcome.perLetter), 0), Welcome.ink.count)
        let offered = t >= Welcome.offerAt, taken = t >= Welcome.takeAt, pressed = t >= Welcome.takeAt - 0.14 && !taken
        let glint = min(max((t - Welcome.takeAt) / 0.25, 0), 1)  // GlintPanel's quarter second.
        let rest = min(max((t - Welcome.restAt) / 0.4, 0), 1)
        return VStack(spacing: 6) {
            Mark().padding(.bottom, 14)
            Text(Welcome.ink.prefix(typed)).font(Welcome.font).frame(minHeight: 46)
            HStack(spacing: 12) {
                Text(Welcome.offer).font(Welcome.font)
                    .foregroundStyle(taken ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Welcome.glass))
                    .overlay { GlintBand(progress: glint * glint * (3 - 2 * glint)).mask(Text(Welcome.offer).font(Welcome.font)) }
                    .opacity(offered ? 1 : 0)
                key(pressed).opacity(offered && !taken ? 1 : 0)
            }
            .padding(.leading, 56)  // The key's room, so the sentence stays centred.
            Text("Suggestions from a model on this Mac, in almost any app.").font(.system(size: 13)).foregroundStyle(.secondary).padding(.top, 14).opacity(rest)
            Button("Get Started", action: onContinue)
                .buttonStyle(Ink()).padding(.top, 10)
                .opacity(rest).allowsHitTesting(rest > 0.5)
        }
    }

    private func key(_ pressed: Bool) -> some View {
        Text("tab").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(pressed ? 0.05 : 0.15), radius: 0, y: pressed ? 0.5 : 2)
            .offset(y: pressed ? 1.5 : 0)
            .frame(width: 44)
    }

    static let font = Font.system(size: 34, weight: .semibold)
    /// GhostView.glass: pale blue to peach.
    static let glass = LinearGradient(colors: [Color(red: 0.373, green: 0.608, blue: 0.847), Color(red: 0.6, green: 0.69, blue: 0.79), Color(red: 0.91, green: 0.561, blue: 0.369)],
                                      startPoint: .leading, endPoint: .trailing)
}

/// GlintView's band, crossing the words as progress goes 0 to 1.
private struct GlintBand: View {
    var progress: CGFloat
    var body: some View {
        GeometryReader { size in
            let width = max(40, size.size.height * 2)
            LinearGradient(colors: [.clear, Color(red: 0.45, green: 0.65, blue: 0.88), Color(red: 0.76, green: 0.83, blue: 0.91), Color(red: 0.93, green: 0.6, blue: 0.42), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: width)
                .offset(x: -width + progress * (size.size.width + width))
                .opacity(progress > 0 && progress < 1 ? 1 : 0)
        }
    }
}

/// The window's main buttons: white on ink, or, quiet, ink on a pale capsule. Not `.borderedProminent` with `.tint(.primary)`: that drew
/// black on black in a key window, and `.tint(.secondary)` crashed SwiftUI in an endless loop resolving the tint (2026-11-09).
struct Ink: ButtonStyle {
    var quiet = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(quiet ? Color.black.opacity(0.7) : .white)
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(quiet ? Color.black.opacity(0.07) : Color.black.opacity(configuration.isPressed ? 0.75 : 0.88), in: Capsule())
            .contentShape(Capsule())
    }
}
