import Foundation

/// What a training run writes beside its adapter as `<name>.json` (lab/dogfood/train.sh on `learn`): counts, dates and settings, never text.
public struct AdapterInfo: Codable, Equatable, Sendable {
    /// Messages it learned from, and the first and last of their days (`yyyy-MM-dd`).
    public var rows: Int?, from: String?, to: String?
    /// The GPU it trained on, or "Mac".
    public var gpu: String?
    public init(rows: Int? = nil, from: String? = nil, to: String? = nil, gpu: String? = nil) { (self.rows, self.from, self.to, self.gpu) = (rows, from, to, gpu) }

    /// "3,014 messages, Aug 9 – Nov 9 · trained on a rented GPU"; nil parts are left out.
    public var note: String? {
        var parts: [String] = []
        if let rows { parts.append("\(rows.formatted(.number.locale(Locale(identifier: "en_US")))) messages" + (Self.day(from).flatMap { a in Self.day(to).map { ", \(a) – \($0)" } } ?? "")) }
        if let gpu { parts.append(gpu == "Mac" ? "trained on this Mac" : "trained on a rented GPU") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Nov 9" from the date in a name like `john-2026-11-09-cloud`, "Nov 9 (2)" for `…-cloud-2`, or the name itself.
    public static func title(name: String) -> String {
        guard let r = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression), let day = day(String(name[r])) else { return name }
        let rest = name[r.upperBound...]
        if let n = rest.range(of: #"-(\d+)$"#, options: .regularExpression) { return "\(day) (\(rest[n].dropFirst()))" }
        return day
    }

    private static let locale = Locale(identifier: "en_US_POSIX")
    private static func day(_ text: String?) -> String? {
        let parse = DateFormatter(), show = DateFormatter()
        parse.locale = locale; parse.dateFormat = "yyyy-MM-dd"; show.locale = locale; show.dateFormat = "MMM d"
        return text.flatMap(parse.date(from:)).map(show.string(from:))
    }
}
