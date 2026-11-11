import CryptoKit
import Foundation
import Security

/// Saved typing, Personal Model's training data (docs/pricing.md "Saved typing"): one file, each line one record sealed with AES-GCM
/// under a key kept in the Keychain, this Mac only. A copied file or a backup is unreadable without the key, and the file is excluded
/// from backups anyway. Never logged, never in Stats; read only to show the user, and for a training run they start.
final class Typing: @unchecked Sendable {
    struct Record: Codable, Equatable, Sendable {
        var date: Date
        /// The prompt it trains on (`Visit.context`): the screen's text before the field, then the field's before the added text.
        var context: String
        var text: String
    }

    /// The key's Keychain item. Tests pass their own key.
    enum Key {
        static let service = "app.halftype.typing"

        static func load(create: Bool) -> SymmetricKey? {
            var item: CFTypeRef?
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                        kSecReturnData as String: true]
            let found = SecItemCopyMatching(query as CFDictionary, &item)
            if found == errSecSuccess, let data = item as? Data, data.count == 32 { return SymmetricKey(data: data) }
            // Only a key that isn't there is made anew: a locked or refusing Keychain must not orphan the file's records.
            guard create, found == errSecItemNotFound else { return nil }
            let key = SymmetricKey(size: .bits256)
            let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                      kSecValueData as String: key.withUnsafeBytes { Data($0) },
                                      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                      kSecAttrSynchronizable as String: false, kSecAttrLabel as String: "Halftype saved typing"]
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? key : nil
        }

        /// True once there's no key: gone now, or never made.
        static func delete() -> Bool {
            let status = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
    }

    let file: URL
    private let key: (_ create: Bool) -> SymmetricKey?
    private let deleteKey: () -> Bool
    /// Every read and write, so an append can't land in the middle of a prune or a Delete All.
    private let queue = DispatchQueue(label: "halftype.typing")
    private var lastText: String?
    /// The last Delete All: a visit begun before it, still on its way from the watcher, mustn't bring its text back.
    private var cleared = Date.distantPast
    /// A prune's rewrite before it replaces the file: excluded from backups too, and removed by Delete All and the next launch's prune.
    private var temp: URL { file.appendingPathExtension("new") }

    init(file: URL, key: @escaping (_ create: Bool) -> SymmetricKey? = Key.load, deleteKey: @escaping () -> Bool = Key.delete) {
        self.file = file
        self.key = key
        self.deleteKey = deleteKey
    }

    /// `began`: when the visit that wrote it started.
    func append(_ record: Record, began: Date) {
        queue.async { [self] in
            guard began > cleared, record.text != lastText, let key = key(true), let line = seal(record, key) else { return }
            lastText = record.text
            // A file no line of which opens was sealed under a key that's gone: begin again rather than mix keys in one file.
            if FileManager.default.fileExists(atPath: file.path), !opens(key) { try? FileManager.default.removeItem(at: file) }
            if !FileManager.default.fileExists(atPath: file.path) { create(Data()) }
            guard let handle = try? FileHandle(forWritingTo: file) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }

    /// Oldest first. Lines that don't open (another key, or tampered with) are left out.
    func all() -> [Record] {
        queue.sync { read() }
    }

    /// Whether a file is there, read or not: Delete All must work with the Keychain refusing.
    var exists: Bool { queue.sync { FileManager.default.fileExists(atPath: file.path) } }

    /// Drops records older than `cutoff`, rewriting the file.
    func prune(before cutoff: Date) {
        queue.async { [self] in
            try? FileManager.default.removeItem(at: temp)  // left by a rewrite cut off
            let records = read()
            let kept = records.filter { $0.date >= cutoff }
            guard kept.count < records.count, let key = key(false) else { return }
            write(kept.compactMap { seal($0, key) }.reduce(Data(), +))
        }
    }

    /// The file and its key, both gone; false if either is still there. Called again, nothing to do.
    @discardableResult func deleteAll() -> Bool {
        queue.sync {
            cleared = Date()
            lastText = nil
            for url in [file, temp] { try? FileManager.default.removeItem(at: url) }
            let keyGone = deleteKey()
            return keyGone && ![file, temp].contains { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    // MARK: Queue only

    private func read() -> [Record] {
        guard let data = try? Data(contentsOf: file), let key = key(false) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).compactMap { open(Data($0), key) }
    }

    private func opens(_ key: SymmetricKey) -> Bool {
        guard let data = try? Data(contentsOf: file) else { return true }
        let lines = data.split(separator: UInt8(ascii: "\n"))
        return lines.isEmpty || lines.contains { open(Data($0), key) != nil }
    }

    private func seal(_ record: Record, _ key: SymmetricKey) -> Data? {
        guard let json = try? JSONEncoder().encode(record), let box = try? AES.GCM.seal(json, using: key), let combined = box.combined else { return nil }
        return combined.base64EncodedData() + Data("\n".utf8)
    }

    private func open(_ line: Data, _ key: SymmetricKey) -> Record? {
        guard let raw = Data(base64Encoded: line), let box = try? AES.GCM.SealedBox(combined: raw),
              let json = try? AES.GCM.open(box, using: key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: json)
    }

    /// Readable by this user only, and never in a Time Machine or iCloud backup.
    private func create(_ data: Data) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
        exclude(file)
    }

    private func exclude(_ file: URL) {
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Excluded before any text is in it.
    private func write(_ data: Data) {
        FileManager.default.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600])
        exclude(temp)
        do {
            try data.write(to: temp)
            _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
            exclude(file)
        } catch { try? FileManager.default.removeItem(at: temp) }
    }
}
