import SwiftUI

/// First launch (docs/design/onboarding, C): a welcome that shows the product in one sentence, the one permission, a lesson for each
/// key in Try It's real glass suggestions (practice ones until the model is in), and where Halftype lives. The model downloads all along.
struct Onboarding: View {
    @ObservedObject var app: App
    enum Step: Int, CaseIterable { case welcome, allow, tab, shiftTab, esc, done }
    @State private var step: Step
    @State private var draft: String
    /// This lesson's key was pressed on a suggestion.
    @State private var did = false

    init(app: App, step: Step = .welcome) {
        self.app = app
        _step = State(initialValue: step)
        _draft = State(initialValue: Lesson.of(step)?.prefill ?? "")
    }

    var body: some View {
        ZStack {
            Arch().padding(.top, -28)
            Group {
                switch step {
                case .welcome: Welcome { next() }
                case .allow: allow
                case .tab, .shiftTab, .esc: lesson(Lesson.of(step)!)
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
        .onChange(of: app.trusted) { if app.trusted, step == .allow { go(.tab) } }
        .onAppear { app.lessonKey = Lesson.of(step)?.key }
        .onChange(of: app.taught) {
            guard let lesson = Lesson.of(step), app.taught == lesson.key, !did else { return }
            did = true
        }
        // Moves on by itself once the key has done its job and the line saying so has been read.
        .task(id: did) {
            guard did else { return }
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled, did { next() }
        }
    }

    private func next() {
        guard let after = Step(rawValue: step.rawValue + 1) else { return app.finishOnboarding() }
        go(after == .allow && app.trusted ? .tab : after)
    }

    /// A lesson starts on its own sentence, with nothing pressed yet.
    private func go(_ to: Step) {
        did = false
        app.taught = nil
        app.refused = nil
        app.lessonKey = Lesson.of(to)?.key
        if let lesson = Lesson.of(to) { draft = lesson.prefill }
        step = to
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

    /// One key: what to press, the field with a suggestion waiting and the key drawn in it, then what the key does, which becomes
    /// what it did. Any other key on the suggestion does nothing, and the line says which one to press.
    private func lesson(_ lesson: Lesson) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text("\(lesson.number) of 3").font(.system(size: 12)).foregroundStyle(.secondary)
            Text(lesson.title).font(.system(size: 24, weight: .semibold)).padding(.top, 4)
            FieldPage(app: app, draft: $draft, chrome: false, keycaps: lesson.keycaps) {}.fixedSize(horizontal: false, vertical: true)
            Group {
                if did {
                    Label(lesson.done, systemImage: "checkmark.circle.fill").foregroundStyle(Color.primary)
                } else if let refused = app.refused {
                    Text("That was \(Lesson.name(refused)). This one is \(Lesson.name(lesson.key)).").foregroundStyle(Root.peach)
                } else {
                    Text(lesson.how).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13, weight: did ? .medium : .regular)).frame(height: 18)
            Spacer()
            Button(did ? "Next" : "Skip") { next() }.buttonStyle(Ink(quiet: !did)).padding(.bottom, 40)
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

/// A key drawn as a key, for the lessons.
struct Keycap: View {
    let label: String
    var body: some View {
        Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 5).frame(minWidth: 40)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.9), in: RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 0, y: 2)
    }
}

/// What each key lesson asks for and starts with. Each sentence is one of `Practice.sentences`, so it gets a suggestion before any model.
struct Lesson {
    let key: KeyTap.Taught, number: Int, title: String, keycaps: [String], how: String, prefill: String, done: String
    static func of(_ step: Onboarding.Step) -> Lesson? {
        switch step {
        case .tab: Lesson(key: .tab, number: 1, title: "Press Tab", keycaps: ["tab"], how: "Tab takes the next word of the suggestion.",
                          prefill: "Please let me know if you have any", done: "That's a word. Tab again takes the next.")
        case .shiftTab: Lesson(key: .shiftTab, number: 2, title: "Press Shift-Tab", keycaps: ["shift", "tab"], how: "Shift-Tab takes the whole suggestion at once.",
                               prefill: "Thanks so much for the", done: "All of it, in one go.")
        case .esc: Lesson(key: .esc, number: 3, title: "Press Esc", keycaps: ["esc"], how: "Esc hides a suggestion you don't want. Then just keep typing.",
                          prefill: "Can we move the meeting to", done: "Hidden. Type on, and a new one comes.")
        default: nil
        }
    }
    static func name(_ key: KeyTap.Taught) -> String {
        switch key { case .tab: "Tab"; case .shiftTab: "Shift-Tab"; case .esc: "Esc" }
    }
}
