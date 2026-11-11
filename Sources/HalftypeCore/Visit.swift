/// Saved typing (docs/pricing.md): one visit to a field, from the first read to leaving it or its emptying, keeps what the user
/// added during it, with what came before as the training prompt. Text typed and erased within the visit isn't kept.
public enum Visit {
    /// The span that changed between arrival and departure, and the field's text before it. Nil if nothing was added.
    /// shortcut: edits in two places keep the text between them too, which `keeps` drops once that's over half; diff by words if it matters.
    public static func added(from arrival: String, to departure: String) -> (before: String, text: String)? {
        let a = Array(arrival), d = Array(departure)
        var start = 0
        while start < a.count, start < d.count, a[start] == d[start] { start += 1 }
        var end = 0  // Common tail, not overlapping the head.
        while end < a.count - start, end < d.count - start, a[a.count - 1 - end] == d[d.count - 1 - end] { end += 1 }
        let text = String(d[start..<(d.count - end)])
        return text.isEmpty ? nil : (String(d[..<start]), text)
    }

    /// Kept: two words or more, which also leaves out codes and passwords typed into plain fields, and at least half of it typed
    /// key by key, Tabs' words included, which leaves out pastes. 2-set Korean takes more keys than characters, so it passes.
    public static func keeps(_ text: String, keys: Int) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: Word.isPart) }
        return words.count >= 2 && keys * 2 >= text.count
    }

    /// One read's new text came from more than the keys since the last read: a paste, or text put in by the host or another app.
    /// A few characters of slack for a host's own autocorrect and smart quotes. Any such change and the visit isn't kept.
    public static func pasted(_ inserted: String, keys: Int) -> Bool { inserted.count > keys + 3 }

    /// The prompt a record trains on, as `Prompt.make` lays it out: the screen's text, a blank line, then the field's, cut to the window.
    public static func context(screen: String, before: String) -> String {
        String((screen.isEmpty ? before : screen + "\n\n" + before).suffix(Prompt.windowChars))
    }
}
