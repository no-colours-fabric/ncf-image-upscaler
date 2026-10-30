import Foundation

/// The Python bridge is invoked directly, never via a shell or an HTTP server.
final class WorkerTask {
    private static var running: [UUID: WorkerTask] = [:]
    static var activeTasks: [WorkerTask] { Array(running.values) }
    private let identifier = UUID()
    private let process = Process()
    private let output = Pipe()
    private let errors = Pipe()
    private let queue = DispatchQueue(label: "local.ncf-image-upscaler.worker-output")
    private let errorQueue = DispatchQueue(label: "local.ncf-image-upscaler.worker-errors")
    private let errorsFinished = DispatchGroup()
    private var buffer = Data()
    private var diagnostics = Data()
    private var finished = false
    private var completionHandlers: [() -> Void] = []
    private(set) var cancelled = false
    private let session: TemporarySession
    var onEvent: (([String: Any]) -> Void)?
    var onExit: ((Int32, Bool, String) -> Void)?

    init(session: TemporarySession) { self.session = session }

    func start(input: URL, output destination: URL, scale: Int, model: String) throws {
        try start(arguments: ["-m", "ncf_image_upscaler.worker", "--input", input.path,
                             "--output", destination.path, "--scale", String(scale), "--model", model])
    }

    func start(arguments: [String]) throws {
        guard FileManager.default.isExecutableFile(atPath: AppPaths.python.path) else {
            throw AppFailure.message("The engine is not installed. Run the NCF Image Upscaler installer.")
        }
        process.executableURL = AppPaths.python
        process.arguments = ["-I", "-B"] + arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["NCF_IMAGE_UPSCALER_HOME"] = AppPaths.data.path
        process.environment = environment
        process.standardOutput = output
        process.standardError = errors
        // One reader per pipe avoids races between the last JSON message and exit.
        queue.async { [self] in
            while true {
                let bytes = output.fileHandleForReading.availableData
                if bytes.isEmpty { break }
                consume(bytes)
            }
            if !buffer.isEmpty { consume(Data([10])) }
        }
        errorsFinished.enter()
        errorQueue.async { [self] in
            defer { errorsFinished.leave() }
            while true {
                let bytes = errors.fileHandleForReading.availableData
                if bytes.isEmpty { break }
                diagnostics.append(bytes)
                if diagnostics.count > 32_768 { diagnostics = diagnostics.suffix(32_768) }
            }
        }
        process.terminationHandler = { [self] task in
            queue.async { [self] in
                errorsFinished.wait()
                let message = String(data: diagnostics, encoding: .utf8) ?? ""
                DispatchQueue.main.async { [self] in
                    finished = true
                    onExit?(task.terminationStatus, cancelled, message)
                    onEvent = nil
                    onExit = nil
                    process.terminationHandler = nil
                    Self.running.removeValue(forKey: identifier)
                    let handlers = completionHandlers
                    completionHandlers.removeAll()
                    handlers.forEach { $0() }
                }
            }
        }
        do {
            try process.run()
            Self.running[identifier] = self
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
        }
        catch {
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            process.terminationHandler = nil
            throw error
        }
    }

    private func consume(_ bytes: Data) {
        buffer.append(bytes)
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }
            DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
        }
    }

    func cancel() {
        guard !finished, process.isRunning, !cancelled else { return }
        cancelled = true
        process.interrupt()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.process.isRunning else { return }
            self.process.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.process.isRunning else { return }
            Darwin.kill(self.process.processIdentifier, SIGKILL)
        }
    }

    func cancelAndWait(_ completion: @escaping () -> Void) {
        if finished { completion(); return }
        completionHandlers.append(completion)
        cancel()
    }
}
