import HalftypeEngine

/// Onboarding's suggestions: its own sentences always get the suggestion each lesson was written for (a model may offer one word where
/// Shift-Tab needs several), and anything else goes to the model, or gets nothing before one is ready, so no lesson waits on 3 GB.
final class Practice: Completer {
    let model: Completer?
    init(over model: Completer? = nil) { self.model = model }

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
        if let rest = Practice.rest(after: prefix + fragment) { return onResult(Suggestion(text: rest, gate: 0)) }
        guard let model else { return onResult(nil) }
        model.suggest(prefix: prefix, fragment: fragment, composing: composing, onResult: onResult)
    }
    func cancel() { model?.cancel() }
    func unload() { model?.unload() }
    func close() { model?.close() }
}
