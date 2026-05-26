import Darwin
import Foundation

/// Owns the lifecycle of a single `imvault view <archive>` subprocess plus the
/// URL it's serving on. The UI binds to `state`; calling `stop()` (or `deinit`)
/// terminates the subprocess.
///
/// Why this is its own type (rather than a static method on IMVaultCLI):
/// the viewer process is long-lived — it stays up for the duration of the
/// SwiftUI view that's hosting the WKWebView. Modelling it as state makes the
/// lifecycle obvious in the SwiftUI dependency graph.
@MainActor
final class ArchiveViewerSession: ObservableObject {
    enum State: Equatable {
        case idle
        case starting(detail: String)
        case ready(URL)
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private var process: Process?

    deinit {
        // Deinit runs nonisolated. terminate() is SIGTERM — last-resort cleanup
        // if the user force-quit while the sheet is up; tempdirs may leak.
        // Normal Close uses stop() which sends SIGINT for clean shutdown.
        process?.terminate()
    }

    func start(archive: URL, password: String) async {
        // Defensive: if a previous run is still around, tear it down first.
        await stop()
        state = .starting(detail: "Decrypting archive…")

        let binary = IMVaultCLI.binaryURL
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            state = .failed("Bundled imvault binary missing at \(binary.path).")
            return
        }

        let process = Process()
        self.process = process
        process.executableURL = binary
        process.arguments = ["view", "--password-fd", "0", archive.path]

        // PYTHONUNBUFFERED keeps `print()` lines from sitting in the Python
        // stdio buffer while we're scanning for the "Serving archive at …"
        // line. BROWSER=true silences Python's webbrowser.open() so the
        // system browser doesn't launch alongside our WKWebView.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["BROWSER"] = "true"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        // Scan stdout for the "Serving archive at http://…" line; once seen,
        // resolve state to .ready(url). LineCollector below is line-buffered.
        let stdoutCollector = LineScanner { [weak self] line in
            guard let self else { return }
            if let url = Self.parseServingURL(from: line) {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .starting = self.state {
                        self.state = .ready(url)
                    }
                }
            } else if !line.isEmpty {
                // Surface human-readable progress like "Extracting files… 1234/5000 (24%)"
                // so big-archive loads don't look hung.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .starting = self.state {
                        self.state = .starting(detail: line)
                    }
                }
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stdoutCollector.feed(data)
            }
        }

        // Stderr is small for this command (an error line or two), so drain it
        // synchronously in the terminationHandler instead of streaming it.
        process.terminationHandler = { proc in
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            let exitCode = proc.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .ready = self.state {
                    // The subprocess exited after we were already serving —
                    // user closed the viewer; nothing to surface.
                    self.state = .idle
                    return
                }
                let trimmed = stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = trimmed.isEmpty
                    ? "imvault view exited with code \(exitCode)."
                    : trimmed
                self.state = .failed(message)
            }
        }

        do {
            try process.run()
        } catch {
            state = .failed("Couldn't launch imvault view: \(error.localizedDescription)")
            return
        }

        // Feed the password through stdin (--password-fd 0).
        let stdin = stdinPipe.fileHandleForWriting
        if let data = (password + "\n").data(using: .utf8) {
            try? stdin.write(contentsOf: data)
        }
        try? stdin.close()
    }

    func stop() async {
        if let process = process, process.isRunning {
            // SIGINT — Python's serve_forever catches KeyboardInterrupt and runs
            // its finally block to clean up the TemporaryDirectory.
            process.interrupt()
        }
        process = nil
        if case .idle = state { return }
        state = .idle
    }

    nonisolated private static func parseServingURL(from line: String) -> URL? {
        // viewer.py prints exactly: "Serving archive at http://127.0.0.1:NNNN/index.html"
        let pattern = #"http://127\.0\.0\.1:\d+/[^\s]*"#
        guard let range = line.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return URL(string: String(line[range]))
    }
}

// MARK: - Helpers

/// Buffers Pipe bytes into newline-terminated lines and invokes a callback
/// for each. Thread-safe.
private final class LineScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        buffer += chunk
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
}
