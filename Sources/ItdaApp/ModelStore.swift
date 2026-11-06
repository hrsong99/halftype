import CryptoKit
import Foundation

/// The default model, fetched once from Hugging Face into Application Support and verified before it is moved into place.
final class ModelStore: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let url = URL(string: "https://huggingface.co/mradermacher/kanana-1.5-2.1b-base-GGUF/resolve/main/kanana-1.5-2.1b-base.Q4_K_M.gguf")!
    static let fileName = "kanana-1.5-2.1b-base.Q4_K_M.gguf"
    static let size: Int64 = 1_393_493_632
    static let sha256 = "e5ac9254ca38cab1a8c0821d7b67e4b4bb0fe6e901c10569e77125b252b14ff1"

    enum State: Equatable { case downloading(Double), verifying, ready(String), failed(String) }

    let directory: URL
    var onChange: (@Sendable (State) -> Void)?
    private var session: URLSession?

    init(directory: URL) {
        self.directory = directory
    }

    var destination: URL { directory.appendingPathComponent(Self.fileName) }

    /// A file of the right size was verified before it got this name, and hashing 1.4 GB on each launch is not worth it.
    var hasModel: Bool {
        (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64) == Self.size
    }

    func fetch() {
        guard session == nil else { return }
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        onChange?(.downloading(0))
        session.downloadTask(with: Self.url).resume()
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
        onChange?(.downloading(Double(written) / Double(Self.size)))
    }

    /// The system deletes `location` when this returns, so all of it happens here.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        onChange?(.verifying)
        do {
            guard (downloadTask.response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,
                  try Self.verify(location, size: Self.size, sha256: Self.sha256) else {
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
