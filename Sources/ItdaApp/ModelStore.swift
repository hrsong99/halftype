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
        Model(name: "Kanana 1.5", note: "The default. From Kakao, and strongest in Korean.", file: "kanana-1.5-2.1b-base.Q4_K_M.gguf",
              sha256: "e5ac9254ca38cab1a8c0821d7b67e4b4bb0fe6e901c10569e77125b252b14ff1", repo: "mradermacher/kanana-1.5-2.1b-base-GGUF", size: 1_393_493_632),
        Model(name: "Qwen 3.5 2B", note: "The smallest, and slightly better in English.", file: "Qwen3.5-2B-Base.Q4_K_M.gguf",
              sha256: "1c42c644e4018f02ddf736e08426aa4597ba76f9de2aa649ef4cd669231743d3", repo: "mradermacher/Qwen3.5-2B-Base-GGUF", size: 1_274_396_800),
        Model(name: "Gemma 4 E2B", note: "Slightly better in English, and much larger.", file: "gemma-4-E2B.Q4_K_M.gguf",
              sha256: "389c868898bffed97fd178646f88562cafecc6f60983a636bac53b131fd068a2", repo: "mradermacher/gemma-4-E2B-GGUF", size: 3_427_861_984),
    ]

    enum State: Equatable { case waiting, downloading(Double), verifying, ready, failed(String), cancelled }

    let directory: URL
    /// Offline at launch, a fetch waits for a connection rather than failing.
    let configuration: URLSessionConfiguration
    var onChange: (@Sendable (State) -> Void)?
    /// The model last fetched. Only changes while nothing is downloading.
    private(set) var current = ModelStore.models[0]
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    /// Where a stopped download of `current` got to, kept beside the models so it survives a quit. Gone if the server refused to resume,
    /// and once a download completes, so the next try starts over.
    var resumeData: Data? {
        get { try? Data(contentsOf: resumeFile) }
        set {
            guard let newValue else { return _ = try? FileManager.default.removeItem(at: resumeFile) }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? newValue.write(to: resumeFile, options: .atomic)
        }
    }
    private var resumeFile: URL { directory.appendingPathComponent(current.file + ".resume") }

    init(directory: URL, configuration: URLSessionConfiguration = .default) {
        self.directory = directory
        self.configuration = configuration
        configuration.waitsForConnectivity = true
    }

    func path(_ model: Model) -> URL { directory.appendingPathComponent(model.file) }

    /// A file of the right size was verified before it got this name, and hashing gigabytes on each launch is not worth it.
    func has(_ model: Model) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path(model).path)[.size] as? Int64) == model.size
    }

    var isBusy: Bool { session != nil }

    /// One at a time, and only with room for the whole file.
    func fetch(_ model: Model) {
        guard session == nil else { return }
        current = model
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let free = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < model.size {
            onChange?(.failed("It needs \(model.sizeText) free, and this Mac has \(String(format: "%.1f GB", Double(free) / 1e9))."))
            return
        }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        self.session = session
        onChange?(.downloading(0))
        // From disk, so it may be damaged, and resume data that isn't URLSession's dictionary raises an exception.
        let resume = resumeData.flatMap { (try? PropertyListSerialization.propertyList(from: $0, format: nil)) is [String: Any] ? $0 : nil }
        task = resume.map(session.downloadTask(withResumeData:)) ?? session.downloadTask(with: model.url)
        task?.resume()
    }

    func delete(_ model: Model) { try? FileManager.default.removeItem(at: path(model)) }

    /// A quit during hashing leaves one of these, gigabytes that nothing else cleans up.
    func removeLeftovers() {
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "unverified" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Keeps what it has, so getting the same model again resumes. It's over only once that is recorded, and then `done` runs.
    func cancel(then done: @escaping () -> Void = {}) {
        guard let task else { return done() }
        task.cancel { data in
            DispatchQueue.main.async { [self] in
                resumeData = data
                finish(.cancelled)
                done()
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

    func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
        onChange?(.waiting)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten written: Int64, totalBytesExpectedToWrite _: Int64) {
        onChange?(.downloading(Double(written) / Double(current.size)))
    }

    /// The system deletes `location` when this returns, so it moves first. Hashing gigabytes then happens off the main thread.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        self.task = nil  // Past cancelling: the session stays until the hash is done, so nothing else starts.
        resumeData = nil  // Spent, whatever comes of it: a bad file must not be resumed from.
        onChange?(.verifying)
        let model = current, destination = path(model), unverified = directory.appendingPathComponent(model.file + ".unverified")
        do {
            if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, ![200, 206].contains(status) {
                return finish(.failed("Hugging Face answered \(status). Try again later."))
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
