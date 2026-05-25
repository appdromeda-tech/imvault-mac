import Foundation

enum IMVaultCLIError: LocalizedError, Sendable {
    case binaryNotFound(URL)
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
    /// CLI emitted a JSON error envelope on stderr. Typically Full Disk Access missing.
    case cliReported(message: String, path: String?)
    case decodeFailed(String, raw: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let url):
            return "Bundled imvault binary not found at \(url.path)."
        case .launchFailed(let msg):
            return "Couldn't launch imvault: \(msg)"
        case .nonZeroExit(let code, let stderr):
            return "imvault exited with code \(code).\n\(stderr)"
        case .cliReported(let message, _):
            return message
        case .decodeFailed(let msg, _):
            return "Couldn't parse imvault output: \(msg)"
        }
    }
}

struct IMVaultCLI {
    /// Path to the bundled imvault binary inside the .app's Resources/.
    static var binaryURL: URL {
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        return resources
            .appendingPathComponent("python-runtime", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("imvault")
    }

    /// `imvault --version`. Cheap sanity check that the sidecar is present and runnable.
    static func version() async throws -> String {
        let result = try await run(arguments: ["--version"])
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `imvault list --json`. Requires Full Disk Access to read ~/Library/Messages/chat.db.
    /// On FDA-missing, throws `.cliReported`.
    static func listChats() async throws -> [Chat] {
        let result = try await run(arguments: ["list", "--json"])
        return try decode([Chat].self, from: result.stdout)
    }

    /// `imvault inspect --json <archive...>`. Password is fed via stdin and `--password-fd 0`.
    static func inspect(archives: [URL], password: String) async throws -> InspectResult {
        var args = ["inspect", "--json", "--password-fd", "0"]
        args.append(contentsOf: archives.map { $0.path })
        let result = try await run(arguments: args, stdin: password + "\n")
        return try decode(InspectResult.self, from: result.stdout)
    }

    /// `imvault export --progress-json -o <out> --password-fd 0 [--all | --chat ID ...]`.
    /// Streams `ExportEvent`s to `progress` as they arrive on stderr.
    static func export(
        chatIDs: [Int],
        to output: URL,
        password: String,
        progress: @escaping @Sendable (ExportEvent) -> Void
    ) async throws {
        var args = ["export", "--progress-json", "--password-fd", "0", "-o", output.path]
        if chatIDs.isEmpty {
            args.append("--all")
        } else {
            for id in chatIDs {
                args.append("--chat")
                args.append(String(id))
            }
        }
        _ = try await run(
            arguments: args,
            stdin: password + "\n",
            onStderrLine: { line in
                guard let data = line.data(using: .utf8) else { return }
                if let event = try? snakeDecoder.decode(ExportEvent.self, from: data) {
                    progress(event)
                }
            }
        )
    }

    // MARK: - Internals

    private struct RunResult {
        let stdout: String
        let stderr: String
    }

    private static let snakeDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    /// Run the bundled CLI, optionally feeding stdin and streaming stderr lines.
    /// Collects stdout fully; returns once the process exits.
    @discardableResult
    private static func run(
        arguments: [String],
        stdin: String? = nil,
        onStderrLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> RunResult {
        // Process.waitUntilExit blocks; hop off the caller's thread so we don't
        // stall a cooperative-pool thread (or the main actor, if called from one).
        try await Task.detached(priority: .userInitiated) {
            try runBlocking(arguments: arguments, stdin: stdin, onStderrLine: onStderrLine)
        }.value
    }

    private static func runBlocking(
        arguments: [String],
        stdin: String?,
        onStderrLine: (@Sendable (String) -> Void)?
    ) throws -> RunResult {
        let url = binaryURL
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw IMVaultCLIError.binaryNotFound(url)
        }

        let process = Process()
        process.executableURL = url
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe?
        if stdin != nil {
            let p = Pipe()
            stdinPipe = p
            process.standardInput = p
        } else {
            stdinPipe = nil
        }

        // Accumulate stderr (and optionally forward each line).
        let stderrCollector = LineCollector(forward: onStderrLine)
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                stderrCollector.feed(data)
            }
        }

        do {
            try process.run()
        } catch {
            throw IMVaultCLIError.launchFailed(error.localizedDescription)
        }

        if let stdinPipe, let stdin {
            let writer = stdinPipe.fileHandleForWriting
            if let data = stdin.data(using: .utf8) {
                try? writer.write(contentsOf: data)
            }
            try? writer.close()
        }

        // Drain stdout to completion (synchronously — Process pipes have small buffers).
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        let stderrText = stderrCollector.text

        if process.terminationStatus != 0 {
            // Try to extract a CLI-emitted JSON error envelope from stderr first.
            if let envelope = parseErrorEnvelope(from: stderrText) {
                throw IMVaultCLIError.cliReported(message: envelope.error, path: envelope.path)
            }
            throw IMVaultCLIError.nonZeroExit(
                code: process.terminationStatus,
                stderr: stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return RunResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: stderrText
        )
    }

    private static func decode<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        guard let data = raw.data(using: .utf8) else {
            throw IMVaultCLIError.decodeFailed("stdout was not UTF-8", raw: raw)
        }
        do {
            return try snakeDecoder.decode(type, from: data)
        } catch {
            throw IMVaultCLIError.decodeFailed(error.localizedDescription, raw: raw)
        }
    }

    private static func parseErrorEnvelope(from stderr: String) -> CLIErrorPayload? {
        // Scan stderr lines for a single JSON object with an "error" key.
        for line in stderr.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            if let envelope = try? snakeDecoder.decode(CLIErrorPayload.self, from: data) {
                return envelope
            }
        }
        return nil
    }
}

// Splits a Pipe's stream into lines, forwarding each to `onLine` and keeping a full transcript.
private final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var transcript = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(forward onLine: (@Sendable (String) -> Void)?) {
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        transcript += chunk
        buffer += chunk
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let onLine {
                onLine(line)
            }
        }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return transcript
    }
}
