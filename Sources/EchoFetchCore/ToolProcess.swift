import Foundation

public struct ToolProcessResult: Sendable {
    public let exitCode: Int32
    public let wasCancelled: Bool
    /// Standard output lines, kept only when `collectOutput` was requested.
    public let standardOutput: [String]
    public let standardError: [String]
}

/// Runs one command-line tool, hands its output over line by line, and can stop it.
public final class ToolProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false

    public init(executableURL: URL, arguments: [String], currentDirectoryURL: URL? = nil) {
        process.executableURL = executableURL
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // yt-dlp is a Python program: make it read and write UTF-8 even when the app has no locale.
        environment["PYTHONIOENCODING"] = "utf-8"
        environment["PYTHONUTF8"] = "1"
        if environment["LANG"] == nil { environment["LANG"] = "en_US.UTF-8" }
        process.environment = environment
        if let currentDirectoryURL { process.currentDirectoryURL = currentDirectoryURL }
    }

    /// Starts the tool and waits for it to finish. `onLine` receives every standard-output line
    /// in order, on a background thread.
    public func run(
        collectOutput: Bool = false,
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> ToolProcessResult {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let outputReader = LineReader(keepLines: collectOutput, onLine: onLine)
        let errorReader = LineReader(keepLines: true, onLine: { _ in })
        let exitStatus = OneShot<Int32>()

        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { finished in
            exitStatus.finish(finished.terminationStatus)
        }
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                outputReader.finish()
            } else {
                outputReader.append(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                errorReader.finish()
            } else {
                errorReader.append(data)
            }
        }

        let started: Bool
        do {
            started = try startUnlessCancelled()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        guard started else {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            return ToolProcessResult(exitCode: -1, wasCancelled: true, standardOutput: [], standardError: [])
        }

        let status = await exitStatus.wait()
        let outputLines = await outputReader.wait()
        let errorLines = await errorReader.wait()
        return ToolProcessResult(
            exitCode: status,
            wasCancelled: isCancelled,
            standardOutput: outputLines,
            standardError: errorLines
        )
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Starts the tool unless `cancel()` came first. Holding the lock means a cancel that arrives
    /// at the same moment waits until the tool is running, and then stops it.
    private func startUnlessCancelled() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        try process.run()
        return true
    }

    /// Asks the tool to stop, and forces it after five seconds.
    public func cancel() {
        lock.lock()
        cancelled = true
        let running = process.isRunning
        lock.unlock()
        guard running else { return }
        let identifier = process.processIdentifier
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.process.isRunning else { return }
            kill(identifier, SIGKILL)
        }
    }
}

/// Splits a stream of bytes into lines and signals when the stream ends.
final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private let keepLines: Bool
    private let onLine: @Sendable (String) -> Void
    private var buffer = Data()
    private var lines: [String] = []
    private let done = OneShot<Bool>()

    init(keepLines: Bool, onLine: @escaping @Sendable (String) -> Void) {
        self.keepLines = keepLines
        self.onLine = onLine
    }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var complete: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            complete.append(Self.decode(buffer[buffer.startIndex..<newline]))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if keepLines { lines.append(contentsOf: complete) }
        lock.unlock()
        complete.forEach(onLine)
    }

    func finish() {
        lock.lock()
        var last: String?
        if !buffer.isEmpty {
            last = Self.decode(buffer[buffer.startIndex...])
            buffer.removeAll()
            if keepLines, let last { lines.append(last) }
        }
        lock.unlock()
        if let last { onLine(last) }
        done.finish(true)
    }

    /// Waits for the end of the stream and returns the kept lines.
    func wait() async -> [String] {
        _ = await done.wait()
        return keptLines
    }

    private var keptLines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    private static func decode(_ bytes: Data) -> String {
        var text = String(decoding: bytes, as: UTF8.self)
        if text.hasSuffix("\r") { text.removeLast() }
        return text
    }
}

/// A value that arrives once, which any number of callers can wait for.
final class OneShot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    private var waiters: [CheckedContinuation<Value, Never>] = []

    func finish(_ newValue: Value) {
        lock.lock()
        guard value == nil else {
            lock.unlock()
            return
        }
        value = newValue
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume(returning: newValue) }
    }

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let value {
                lock.unlock()
                continuation.resume(returning: value)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}
