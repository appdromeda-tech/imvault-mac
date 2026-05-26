import AppKit
import SwiftUI

struct ExportSheet: View {
    enum Phase: Sendable {
        case configuring
        case running(progress: Double, label: String)
        case completed(URL)
        case failed(String)
    }

    let chats: [Chat]
    let selectedChatIDs: [Int]
    let onDismiss: () -> Void

    @State private var outputURL: URL = ExportSheet.defaultOutputURL()
    @State private var password: String = ""
    @State private var passwordConfirm: String = ""
    @State private var phase: Phase = .configuring
    @State private var exportTask: Task<Void, Never>?
    @State private var cancellable = CancellableProcessRef()
    @State private var registryToken: SubprocessRegistry.Token?
    @State private var didCancel = false

    private var chatsByID: [Int: Chat] {
        Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    /// Free space on the volume holding the chosen output path, in bytes.
    /// nil if it can't be determined (e.g. parent dir doesn't exist yet).
    private var freeSpaceOnTarget: Int64? {
        let dir = outputURL.deletingLastPathComponent()
        let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    private var lowDiskSpace: Bool {
        guard let free = freeSpaceOnTarget else { return false }
        return free < 1_000_000_000 // 1 GB
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .configuring:
                configuringView
            case .running(let progress, let label):
                runningView(progress: progress, label: label)
            case .completed(let url):
                completedView(url: url)
            case .failed(let message):
                failedView(message: message)
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(isRunning)
    }

    // MARK: - Configuring

    @ViewBuilder private var configuringView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Back up \(selectedChatIDs.count) conversation\(selectedChatIDs.count == 1 ? "" : "s")")
                .font(.title2)
                .bold()
            Text("Your backup will be encrypted with the password below. Pick a strong one — and write it down somewhere safe.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Save to:")
                        .frame(width: 100, alignment: .trailing)
                    Text(outputURL.path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Button("Choose…") { showSavePanel() }
                }

                HStack {
                    Text("Password:")
                        .frame(width: 100, alignment: .trailing)
                    SecureField("", text: $password, prompt: Text("Required"))
                }

                if !password.isEmpty {
                    HStack(spacing: 8) {
                        Spacer().frame(width: 100)
                        passwordStrengthMeter
                    }
                }

                HStack {
                    Text("Confirm:")
                        .frame(width: 100, alignment: .trailing)
                    SecureField("", text: $passwordConfirm)
                }

                if !passwordConfirm.isEmpty && password != passwordConfirm {
                    HStack {
                        Spacer().frame(width: 100)
                        Text("Passwords don't match.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        // The most important sentence in the entire app. Red, bold, hard to miss.
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.red)
            Text("**Write this password down.** If you forget it, the backup can't be opened — by anyone. There is no way to recover it.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

        if lowDiskSpace, let free = freeSpaceOnTarget {
            warningBanner(
                "Less than \(ExportSheet.formatBytes(free)) free on the target volume — backups of large chats may fail mid-write."
            )
        }

        HStack {
            Spacer()
            Button("Cancel") { onDismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Back Up") { startExport() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
        }
    }

    @ViewBuilder private var passwordStrengthMeter: some View {
        let score = ExportSheet.passwordStrength(for: password)
        HStack(spacing: 4) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i < score ? strengthColor(for: score) : Color.secondary.opacity(0.2))
                    .frame(width: 32, height: 4)
            }
            Text(strengthLabel(for: score))
                .font(.caption)
                .foregroundStyle(strengthColor(for: score))
                .padding(.leading, 6)
            Spacer()
        }
    }

    private func strengthLabel(for score: Int) -> String {
        switch score {
        case 0...1: return "Weak"
        case 2: return "Fair"
        case 3: return "Strong"
        default: return "Very strong"
        }
    }

    private func strengthColor(for score: Int) -> Color {
        switch score {
        case 0...1: return .red
        case 2: return .orange
        case 3: return .green
        default: return .green
        }
    }

    /// 0–4 score based on length + character variety. Deliberately simple —
    /// the goal is to surface obviously weak passwords, not enforce policy.
    static func passwordStrength(for password: String) -> Int {
        guard !password.isEmpty else { return 0 }
        var score = 0
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }
        if password.count >= 16 { score += 1 }
        if password.range(of: "[A-Z]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[0-9]", options: .regularExpression) != nil { score += 1 }
        if password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil { score += 1 }
        // Map 0-6 internal points down to 0-4 visible segments.
        return min(score, 4)
    }

    @ViewBuilder private func warningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private var canExport: Bool {
        !selectedChatIDs.isEmpty
            && !password.isEmpty
            && password == passwordConfirm
    }

    private func showSavePanel() {
        let panel = NSSavePanel()
        panel.title = "Save Backup"
        panel.prompt = "Save"
        panel.message = "Choose where to save your encrypted backup."
        panel.nameFieldStringValue = outputURL.lastPathComponent
        panel.directoryURL = outputURL.deletingLastPathComponent()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url
        }
    }

    // MARK: - Running

    @ViewBuilder private func runningView(progress: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Backing up…")
                .font(.title2)
                .bold()
            Text(outputURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
                .lineLimit(1)
        }

        ProgressView(value: progress.isNaN ? nil : progress) {
            Text(label)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .progressViewStyle(.linear)

        HStack {
            Text("\(Int((progress.isNaN ? 0 : progress) * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Cancel", role: .destructive) {
                cancelExport()
            }
            .disabled(didCancel)
        }
    }

    // MARK: - Completed

    @ViewBuilder private func completedView(url: URL) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                Text("Your backup has been saved")
                    .font(.title2)
                    .bold()
                Text(url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        HStack {
            Spacer()
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Button("Done") { onDismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Failed

    @ViewBuilder private func failedView(message: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 4) {
                Text("Couldn't save the backup")
                    .font(.title2)
                    .bold()
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        HStack {
            Spacer()
            Button("Try again") { phase = .configuring }
            Button("Close") { onDismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Export driver

    private func startExport() {
        phase = .running(progress: 0, label: "Preparing…")
        didCancel = false

        let chatIDs = selectedChatIDs
        let url = outputURL
        let pwd = password
        let nameLookup = chatsByID
        let handle = cancellable

        // Survives an app crash / force-quit between now and the catch block:
        // RootView's orphan check on next launch will pick this up and offer
        // to delete the partial file.
        PartialExportTracker.markStarted(url)

        // Register so the app-quit shutdown path can SIGINT us cleanly.
        registryToken = SubprocessRegistry.shared.register(
            interrupt: { handle.interrupt() },
            isRunning: { handle.isRunning }
        )

        exportTask = Task {
            do {
                try await IMVaultCLI.export(
                    chatIDs: chatIDs,
                    to: url,
                    password: pwd,
                    cancellation: handle,
                    progress: { event in
                        Task { @MainActor in
                            applyProgress(event, nameLookup: nameLookup)
                        }
                    }
                )
                await MainActor.run {
                    registryToken = nil
                    PartialExportTracker.markFinished(url)
                    NSApp.dockTile.badgeLabel = nil
                    phase = .completed(url)
                }
            } catch {
                await MainActor.run {
                    registryToken = nil
                    NSApp.dockTile.badgeLabel = nil
                    // Best-effort cleanup of the partial output file; the
                    // CLI was either interrupted or threw mid-write.
                    try? FileManager.default.removeItem(at: url)
                    PartialExportTracker.markFinished(url)
                    if didCancel {
                        // User asked for this — just close the sheet.
                        onDismiss()
                    } else {
                        phase = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func cancelExport() {
        didCancel = true
        cancellable.interrupt()
        // The export task will catch the non-zero exit (or CLI cancel error),
        // do partial-file cleanup, see didCancel = true, and dismiss the sheet.
    }

    @MainActor
    private func applyProgress(_ event: ExportEvent, nameLookup: [Int: Chat]) {
        let progress = event.total > 0
            ? Double(event.processed) / Double(event.total)
            : 0

        let chatName: String? = event.chatId.flatMap { nameLookup[$0]?.displayName }
        let label: String
        switch event.event {
        case .chatStarted:
            label = "Backing up \(chatName ?? "conversation")…"
        case .chatDone:
            label = "Finished \(chatName ?? "conversation") (\(event.processed)/\(event.total))"
        case .attachment:
            label = "Copying attachments (\(event.processed)/\(event.total))"
        case .encryptProgress:
            // CLI v0.4.1+: emitted after the last chat_done while the tar.gz
            // is being stream-encrypted. processed/total counts ciphertext
            // chunks here — a different denominator than the chat events,
            // so the progress bar resets visually. That's honest: it's a
            // distinct sub-phase, and the label says so.
            label = "Encrypting (\(event.processed)/\(event.total) chunks)…"
        }
        phase = .running(progress: progress, label: label)

        // Surface progress on the dock tile so the user can see it from
        // outside the app.
        if event.total > 0 {
            NSApp.dockTile.badgeLabel = "\(Int(progress * 100))%"
        }
    }

    // MARK: - Defaults

    static func defaultOutputURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        return documents.appendingPathComponent("imvault_export.imv")
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview("Configuring") {
    ExportSheet(
        chats: [
            Chat(chatId: 1, displayName: "Mom", participantCount: 2, messageCount: 4123, lastMessageAt: "2026-05-20"),
            Chat(chatId: 2, displayName: "Work group chat", participantCount: 8, messageCount: 12041, lastMessageAt: "2026-05-24"),
        ],
        selectedChatIDs: [1, 2],
        onDismiss: {}
    )
}
