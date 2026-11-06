import CryptoKit
import Foundation

/// The default model, fetched once from Hugging Face into Application Support and verified before it is moved into place.
final class ModelStore: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Source {
        var url: URL
        var fileName: String
        var size: Int64
        var sha256: String
    }

    static let kanana = Source(url: URL(string: "https://huggingface.co/mradermacher/kanana-1.5-2.1b-base-GGUF/resolve/main/kanana-1.5-2.1b-base.Q4_K_M.gguf")!,
                               fileName: "kanana-1.5-2.1b-base.Q4_K_M.gguf", size: 1_393_493_632,
                               sha256: "e5ac9254ca38cab1a8c0821d7b67e4b4bb0fe6e901c10569e77125b252b14ff1")

    enum State: Equatable { case idle, downloading(Double), verifying, ready(String), failed(String) }

    let source: Source
    let directory: URL
    var onChange: (@Sendable (State) -> Void)?
    private var session: URLSession?

    init(source: Source = kanana, directory: URL) {
        self.source = source
        self.directory = directory
    }

    var destination: URL { directory.appendingPathComponent(source.fileName) }

    /// A file of the right size was verified before it got this name, and hashing 1.4 GB on each launch is not worth it.
    var hasModel: Bool {
        (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) == source.size
    }

    func fetch() {
        guard session == nil else { return }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        onChange?(.downloading(0))
        session.downloadTask(with: source.url).resume()
    }

    static func verify(_ file: URL, size: Int64, sha256: String) throws -> Bool {
        guard try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64 == size else { return false }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == sha256
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten written: Int64, totalBytesExpectedToWrite _: Int64) {
        onChange?(.downloading(Double(written) / Double(source.size)))
    }

    /// The system deletes `location` when this returns, so all of it happens here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onChange?(.verifying)
        do {
            guard (downloadTask.response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,
                  try Self.verify(location, size: source.size, sha256: source.sha256) else {
                return finish(.failed("The download didn't match its checksum."))
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.ready(destination.path))
        } catch {
            finish(.failed(error.localizedDescription))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failed(error.localizedDescription)) }
    }

    private func finish(_ state: State) {
        session?.finishTasksAndInvalidate()
        session = nil
        onChange?(state)
    }
}
