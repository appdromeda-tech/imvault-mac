import SwiftUI

/// Small modal that takes a password for an `.imv` archive the user just picked.
/// Submit fires `onSubmit(password)`; cancel fires `onCancel()`.
struct OpenArchivePasswordSheet: View {
    let archive: URL
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "lock.doc")
                    .foregroundStyle(.tint)
                    .font(.title3)
                Text("Open archive")
                    .font(.title2)
                    .bold()
            }

            Text(archive.lastPathComponent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
                .lineLimit(1)

            HStack {
                Text("Password:")
                    .frame(width: 80, alignment: .trailing)
                SecureField("", text: $password)
                    .onSubmit(submit)
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
        .frame(width: 420)
    }

    private func submit() {
        guard !password.isEmpty else { return }
        onSubmit(password)
    }
}

#Preview {
    OpenArchivePasswordSheet(
        archive: URL(fileURLWithPath: "/tmp/example.imv"),
        onSubmit: { _ in },
        onCancel: {}
    )
}
