import Foundation

/// What a training run writes beside its adapter as `<name>.json` (lab/dogfood/train.sh in halftype-train): counts, dates and settings, never text.
/// The app shows what it learned from; where and how it trained stay in the file for the lab.
public struct AdapterInfo: Codable, Equatable, Sendable {
    /// Messages it learned from, and the first and last of their days (`yyyy-MM-dd`).
    public var rows: Int?, from: String?, to: String?
    public init(rows: Int? = nil, from: String? = nil, to: String? = nil) { (self.rows, self.from, self.to) = (rows, from, to) }

    /// "3,014 messages, Aug 9 – Nov 9", or nil without a count.
    public var note: String? {
        rows.map { "\($0.formatted(.number.locale(Locale(identifier: "en_US")))) messages" + (Self.day(from).flatMap { a in Self.day(to).map { ", \(a) – \($0)" } } ?? "") }
    }

    /// "Nov 9" from a name like `john-2026-11-09`, "Nov 9 (2)" for the day's second run `…-09-2`, or the name itself.
    public static func title(name: String) -> String {
        guard let r = name.range(of: #"\d{4}-\d{2}-\d{2}(-\d+)?$"#, options: .regularExpression), let day = day(String(name[r].prefix(10))) else { return name }
        let n = name[r].dropFirst(11)
        return n.isEmpty ? day : "\(day) (\(n))"
    }

    private static func day(_ text: String?) -> String? {
        let parse = DateFormatter(), show = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX"); parse.dateFormat = "yyyy-MM-dd"; show.locale = parse.locale; show.dateFormat = "MMM d"
        return text.flatMap(parse.date(from:)).map(show.string(from:))
    }
}
