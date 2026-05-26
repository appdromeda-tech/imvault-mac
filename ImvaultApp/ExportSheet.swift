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
            Text("Export \(selectedChatIDs.count) conversation\(selectedChatIDs.count == 1 ? "" : "s")")
                .font(.title2)
                .bold()
            Text("imvault encrypts the archive with Argon2id + AES-256-GCM. The password is required to open it later — there is no recovery.")
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

        if lowDiskSpace, let free = freeSpaceOnTarget {
            warningBanner(
                "Less than \(ExportSheet.formatBytes(free)) free on the target volume — exports of large chats may fail mid-write."
            )
        }

        HStack {
            Spacer()
            Button("Cancel") { onDismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Export") { startExport() }
                .keyboardShortcut(.defaultAction)
                .disabled(!canExport)
        }
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
        panel.title = "Save imvault Archive"
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
            Text("Exporting…")
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
                Text("Export complete")
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
                Text("Export failed")
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
            label = "Exporting \(chatName ?? "conversation")…"
        case .chatDone:
            label = "Finished \(chatName ?? "conversation") (\(event.processed)/\(event.total))"
        case .attachment:
            label = "Copying attachments (\(event.processed)/\(event.total))"
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
