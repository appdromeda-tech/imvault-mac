import SwiftUI

struct FDAOnboardingView: View {
    /// Called when the user clicks "I've granted it — recheck".
    /// Parent should re-probe `Permissions.checkFullDiskAccess()`; if it now
    /// returns `.granted`, parent switches away from this view.
    let onRecheck: () -> Void

    @State private var didRecheck = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Full Disk Access required")
                .font(.title)
                .bold()

            Text("imvault needs Full Disk Access to read your iMessage history (\(Permissions.chatDBPath)). macOS requires you to grant this in System Settings — apps can't request it automatically.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label("Click **Open System Settings** below.", systemImage: "1.circle")
                Label("Click **+** and add **imvault.app**, then toggle it on.", systemImage: "2.circle")
                Label("Quit imvault (**⌘Q**) and relaunch — Full Disk Access only takes effect at app start.", systemImage: "3.circle")
            }

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    Permissions.openFullDiskAccessSettings()
                }
                .keyboardShortcut(.defaultAction)

                Button("I've granted it — recheck") {
                    didRecheck = true
                    onRecheck()
                }
            }

            if didRecheck {
                Text("Still not detected. macOS usually only picks up Full Disk Access at app launch — please quit (⌘Q) and relaunch.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
        .padding(32)
        .frame(minWidth: 600, minHeight: 460, alignment: .topLeading)
    }
}

#Preview {
    FDAOnboardingView(onRecheck: {})
}
