import SwiftUI

/// One-time welcome shown after Full Disk Access is granted on first launch.
/// Explains in plain language what the app does and — critically — that the
/// backup password is unrecoverable.
///
/// Dismissal sets `welcome_shown_v1` in `UserDefaults` so this sheet doesn't
/// reappear. The `_v1` suffix lets a future release force the welcome again
/// (e.g. if onboarding meaningfully changes).
struct WelcomeSheet: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "lock.doc.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to imvault")
                        .font(.title)
                        .bold()
                    Text("Back up your iMessage conversations")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("imvault makes encrypted backups of your iMessage history. Pick the chats you want, choose a password, and you get a single backup file you can keep anywhere — an external drive, a USB stick, cloud storage, another Mac.")
                    .fixedSize(horizontal: false, vertical: true)

                Text("Open a saved backup any time to read your messages in a familiar conversation view, without needing the Messages app.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The most important screen in the app — the password warning.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your password is the only key.")
                        .font(.callout)
                        .bold()
                    Text("If you forget the password you choose for a backup, the backup can't be opened — not by you, not by us, not by anyone. **Write your passwords down somewhere safe.**")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Spacer()
                Button("Got it") {
                    UserDefaults.standard.set(true, forKey: "welcome_shown_v1")
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 540)
    }

    /// Whether the welcome has already been shown on this Mac.
    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: "welcome_shown_v1")
    }
}

#Preview {
    WelcomeSheet(onDismiss: {})
}
