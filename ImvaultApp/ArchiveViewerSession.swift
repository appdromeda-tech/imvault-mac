import Darwin
import Foundation

/// Owns the lifecycle of a single `imvault view <archive>` subprocess plus the
/// URL it's serving on. The UI binds to `state`; calling `stop()` (or `deinit`)
/// terminates the subprocess.
///
/// Spawns the CLI with `--no-browser --progress-json --password-fd 0` (v0.4.0+)
/// so we get structured event lines on stderr — decrypt and extract progress
/// for the loading UI, and a `ready` event carrying the URL once the local
/// HTTP server is up.
@MainActor
final class ArchiveViewerSession: ObservableObject {
    /// What the loading screen should display while `imvault view` is busy.
    struct Progress: Equatable, Sendable {
        enum Stage: Sendable {
            case decrypting
            case extracting
        }
        let stage: Stage
        let processed: Int
        let total: Int

        var fraction: Double? {
            total > 0 ? Double(processed) / Double(total) : nil
        }

        var label: String {
            switch stage {
            case .decrypting:
                return total > 0
                    ? "Decrypting… \(processed)/\(total)"
                    : "Decrypting…"
            case .extracting:
                return total > 0
                    ? "Extracting… \(processed)/\(total)"
                    : "Extracting…"
            }
        }
    }

    enum State: Equatable {
        case idle
        case starting(Progress?)
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var process: Process?
    private var registryToken: SubprocessRegistry.Token?

    deinit {
        // Deinit runs nonisolated. interrupt() is SIGINT — Python's
        // serve_forever catches KeyboardInterrupt and runs the finally block
        // to clean up the TemporaryDirectory. AppDelegate (via
        // SubprocessRegistry) takes care of waiting for that cleanup before
        // AppKit returns. terminate() (SIGTERM) is a last-resort fallback.
        process?.interrupt()
    }

    func start(archive: URL, password: String) async {
        // Defensive: if a previous run is still around, tear it down first.
        await stop()
        state = .starting(nil)

        let binary = IMVaultCLI.binaryURL
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            state = .failed("Bundled imvault binary missing at \(binary.path).")
            return
        }

        let process = Process()
        self.process = process
        process.executableURL = binary
        process.arguments = [
            "view",
            "--no-browser",
            "--progress-json",
            "--password-fd", "0",
            archive.path,
        ]

        // PYTHONUNBUFFERED keeps event lines from sitting in Python's stdio
        // buffer. v0.4.0's --no-browser flag replaces the BROWSER=true hack.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        // Stderr is the event stream now (one JSON object per line). Stdout
        // is unused under --progress-json — drain it so the pipe buffer never
        // fills.
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            }
            // Discard.
        }

        let eventScanner = LineScanner { [weak self] line in
            guard let self else { return }
            guard let event = Self.parseEvent(from: line) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.apply(event: event)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                eventScanner.feed(data)
            }
        }

        process.terminationHandler = { [weak eventScanner] proc in
            // Any tail data lingering in the stderr pipe before the OS
            // closed it.
            let tail = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            if !tail.isEmpty, let scanner = eventScanner {
                scanner.feed(tail)
                // The OS won't fire the readabilityHandler again, so make
                // sure any unterminated final line is parsed too.
                scanner.flush()
            }
            let exitCode = proc.terminationStatus
            let stderrTranscript = eventScanner?.transcriptCopy ?? ""

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.registryToken = nil

                switch self.state {
                case .ready:
                    if exitCode == 0 || exitCode == SIGINT {
                        self.state = .idle
                    } else {
                        let detail = Self.extractFailureMessage(
                            from: stderrTranscript,
                            exitCode: exitCode
                        )
                        self.state = .failed("Viewer ended unexpectedly:\n\(detail)")
                    }
                case .starting, .idle, .failed:
                    let message = Self.extractFailureMessage(
                        from: stderrTranscript,
                        exitCode: exitCode
                    )
                    self.state = .failed(message)
                }
            }
        }

        do {
            try process.run()
        } catch {
            state = .failed("Couldn't launch imvault view: \(error.localizedDescription)")
            return
        }

        registryToken = SubprocessRegistry.shared.register(
            interrupt: { [weak process] in
                if let p = process, p.isRunning {
                    p.interrupt()
                }
            },
            isRunning: { [weak process] in
                process?.isRunning ?? false
            }
        )

        // Feed the password through stdin (--password-fd 0).
        let stdin = stdinPipe.fileHandleForWriting
        if let data = (password + "\n").data(using: .utf8) {
            try? stdin.write(contentsOf: data)
        }
        try? stdin.close()
    }

    func stop() async {
        if let process = process, process.isRunning {
            // SIGINT → Python's KeyboardInterrupt → tempdir cleanup.
            process.interrupt()
        }
        process = nil
        if case .idle = state { return }
        state = .idle
    }

    // MARK: - Event handling

    private func apply(event: ViewEvent) {
        switch event {
        case .decryptProgress(let processed, let total):
            if case .starting = state {
                state = .starting(Progress(stage: .decrypting, processed: processed, total: total))
            }
        case .extractProgress(let processed, let total):
            if case .starting = state {
                state = .starting(Progress(stage: .extracting, processed: processed, total: total))
            }
        case .ready(let url):
            if case .starting = state {
                state = .ready(url)
            }
        case .error(let message):
            state = .failed(message)
        }
    }

    private enum ViewEvent {
        case decryptProgress(processed: Int, total: Int)
        case extractProgress(processed: Int, total: Int)
        case ready(URL)
        case error(String)
    }

    nonisolated private static func parseEvent(from line: String) -> ViewEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = raw["error"] as? String {
            return .error(error)
        }

        guard let event = raw["event"] as? String else { return nil }

        switch event {
        case "decrypt_progress":
            let processed = (raw["processed"] as? Int) ?? 0
            let total = (raw["total"] as? Int) ?? 0
            return .decryptProgress(processed: processed, total: total)
        case "extract_progress":
            let processed = (raw["processed"] as? Int) ?? 0
            let total = (raw["total"] as? Int) ?? 0
            return .extractProgress(processed: processed, total: total)
        case "ready":
            guard let urlString = raw["url"] as? String,
                  let url = URL(string: urlString) else { return nil }
            return .ready(url)
        default:
            return nil
        }
    }

    /// Picks the most useful failure string out of the stderr transcript:
    /// a JSON error envelope if there is one, otherwise the last non-JSON
    /// line (often a Python exception), otherwise a fallback.
    nonisolated private static func extractFailureMessage(
        from transcript: String,
        exitCode: Int32
    ) -> String {
        var lastHumanReadable: String?
        for raw in transcript.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("{"), line.hasSuffix("}"),
               let data = line.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = dict["error"] as? String {
                    return error
                }
                // Skip progress events.
                continue
            }
            lastHumanReadable = line
        }
        if let lastHumanReadable, !lastHumanReadable.isEmpty {
            return lastHumanReadable
        }
        return "imvault view exited with code \(exitCode)."
    }
}

// MARK: - Helpers

/// Buffers Pipe bytes into newline-terminated lines and invokes a callback
/// for each. Thread-safe.
private final class LineScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var transcript = ""
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        buffer += chunk
        transcript += chunk
        var lines: [String] = []
        while let newline = buffer.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            lines.append(line)
        }
        lock.unlock()
        for line in lines {
            onLine(line)
        }
    }

    /// Force any buffered partial line through `onLine`. Call once when the
    /// stream is known to be closed.
    func flush() {
        lock.lock()
        let leftover = buffer
        buffer = ""
        lock.unlock()
        if !leftover.isEmpty {
            onLine(leftover)
        }
    }

    var transcriptCopy: String {
        lock.lock()
        defer { lock.unlock() }
        return transcript
    }
}
