import CryptoKit
import Foundation

/// The models offered, each fetched once from Hugging Face into Application Support and verified before it is moved into place.
/// Its state belongs to the main thread: the session delivers there, and only hashing leaves it.
final class ModelStore: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Model: Identifiable, Sendable {
        let name, note, file, sha256: String
        let repo: String
        let size: Int64
        var id: String { file }
        var url: URL { URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")! }
        var sizeText: String { String(format: "%.1f GB", Double(size) / 1e9) }
    }

    /// First is the default. Notes come from the measurements in docs/measuring.md.
    static let models = [
        Model(name: "Qwen 3.5 0.8B", note: "The default. The smallest and quickest.", file: "Qwen3.5-0.8B-Q4_K_M.gguf",
              sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517", repo: "unsloth/Qwen3.5-0.8B-GGUF", size: 532_517_120),
        Model(name: "Qwen 3.5 2B", note: "Better in Korean, and 2.4 times the size.", file: "Qwen3.5-2B-Q4_K_M.gguf",
              sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223", repo: "unsloth/Qwen3.5-2B-GGUF", size: 1_280_835_840),
        Model(name: "Kanana 1.5", note: "From Kakao, and strongest in Korean.", file: "kanana-1.5-2.1b-base.Q4_K_M.gguf",
              sha256: "e5ac9254ca38cab1a8c0821d7b67e4b4bb0fe6e901c10569e77125b252b14ff1", repo: "mradermacher/kanana-1.5-2.1b-base-GGUF", size: 1_393_493_632),
        Model(name: "Gemma 4 E2B", note: "Slightly better in English, and much larger.", file: "gemma-4-E2B.Q4_K_M.gguf",
              sha256: "389c868898bffed97fd178646f88562cafecc6f60983a636bac53b131fd068a2", repo: "mradermacher/gemma-4-E2B-GGUF", size: 3_427_861_984),
    ]

    enum State: Equatable { case downloading(Double), verifying, ready, failed(String), cancelled }

    let directory: URL
    var onChange: (@Sendable (State) -> Void)?
    /// The model last fetched. Only changes while nothing is downloading.
    private(set) var current = ModelStore.models[0]
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    /// Where a failed download of `current` stopped. Gone if the server refused to resume, so the next try starts over.
    private(set) var resumeData: Data?

    init(directory: URL) {
        self.directory = directory
    }

    func path(_ model: Model) -> URL { directory.appendingPathComponent(model.file) }

    /// A file of the right size was verified before it got this name, and hashing gigabytes on each launch is not worth it.
    func has(_ model: Model) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path(model).path)[.size] as? Int64) == model.size
    }

    var isBusy: Bool { session != nil }

    /// One at a time.
    func fetch(_ model: Model) {
        guard session == nil else { return }
        if model.id != current.id { resumeData = nil }
        current = model
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        self.session = session
        onChange?(.downloading(0))
        task = resumeData.map(session.downloadTask(withResumeData:)) ?? session.downloadTask(with: model.url)
        task?.resume()
    }

    /// A quit during hashing leaves one of these, gigabytes that nothing else cleans up.
    func removeLeftovers() {
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "unverified" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Keeps what it has, so getting the same model again resumes. It's over only once that is recorded.
    func cancel() {
        task?.cancel { data in
            DispatchQueue.main.async { [self] in
                resumeData = data
                finish(.cancelled)
            }
        }
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
        onChange?(.downloading(Double(written) / Double(current.size)))
    }

    /// The system deletes `location` when this returns, so it moves first. Hashing gigabytes then happens off the main thread.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        self.task = nil  // Past cancelling: the session stays until the hash is done, so nothing else starts.
        onChange?(.verifying)
        let model = current, destination = path(model), unverified = directory.appendingPathComponent(model.file + ".unverified")
        do {
            guard (downloadTask.response as? HTTPURLResponse).map({ [200, 206].contains($0.statusCode) }) ?? true else {
                return finish(.failed("The download didn't match its checksum."))
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try? FileManager.default.removeItem(at: unverified)
            try FileManager.default.moveItem(at: location, to: unverified)
        } catch {
            return finish(.failed(error.localizedDescription))
        }
        DispatchQueue.global(qos: .utility).async { [self] in
            let outcome: State
            do {
                if try Self.verify(unverified, size: model.size, sha256: model.sha256) {
                    _ = try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: unverified, to: destination)
                    outcome = .ready
                } else {
                    outcome = .failed("The download didn't match its checksum.")
                }
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            _ = try? FileManager.default.removeItem(at: unverified)
            DispatchQueue.main.async { self.finish(outcome) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let failure = error as NSError
        if failure.code == NSURLErrorCancelled { return }  // `cancel` finishes it.
        resumeData = failure.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        finish(.failed(failure.localizedDescription))
    }

    private func finish(_ state: State) {
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
        onChange?(state)
    }
}
