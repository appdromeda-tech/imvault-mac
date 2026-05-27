import SwiftUI

/// Small modal that takes a password for an `.imv` archive the user just picked.
/// Submit fires `onSubmit(password)`; cancel fires `onCancel()`. Shows a heads-up
/// for very large archives — the viewer decrypts via the CLI's streaming path
/// (CHUNK_SIZE-bounded memory), but a copy still gets extracted to the system
/// tempdir for the viewer session, so users need archive-size free disk space.
struct OpenArchivePasswordSheet: View {
    let archive: URL
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password: String = ""

    private var archiveSize: Int64? {
        let values = try? archive.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }

    /// 1 GB threshold. The CLI viewer reads the whole archive into memory
    /// before decrypting, so anything north of ~1 GB starts noticeably stressing
    /// 8-GB-class Macs.
    private var isLargeArchive: Bool {
        guard let size = archiveSize else { return false }
        return size > 1_000_000_000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.doc")
                    .foregroundStyle(.tint)
                    .font(.title3)
                Text("Open backup")
                    .font(.title2)
                    .bold()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(archive.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(1)
                if let size = archiveSize {
                    Text(OpenArchivePasswordSheet.formatBytes(size))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            HStack {
                Text("Password:")
                    .frame(width: 80, alignment: .trailing)
                SecureField("", text: $password)
                    .onSubmit(submit)
            }

            if isLargeArchive, let size = archiveSize {
                largeArchiveWarning(size: size)
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Open", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder private func largeArchiveWarning(size: Int64) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Large backup")
                    .font(.callout)
                    .bold()
                Text("Opening a backup this size takes a few minutes. About \(OpenArchivePasswordSheet.formatBytes(size)) of free disk space is needed temporarily while the viewer is open; it's cleaned up automatically when you close the backup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func submit() {
        guard !password.isEmpty else { return }
        onSubmit(password)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    OpenArchivePasswordSheet(
        archive: URL(fileURLWithPath: "/tmp/example.imv"),
        onSubmit: { _ in },
        onCancel: {}
    )
}
