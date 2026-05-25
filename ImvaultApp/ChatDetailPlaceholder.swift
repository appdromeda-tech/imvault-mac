import SwiftUI

/// Placeholder for the main detail pane. Phase 4 polish or a later phase may add
/// a per-conversation preview here; for now it surfaces selection state and a
/// subtle health indicator for the bundled CLI.
struct ChatDetailPlaceholder: View {
    let selectedCount: Int
    let totalCount: Int
    let sidecarVersion: String?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: selectedCount == 0 ? "tray" : "tray.full")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            if selectedCount == 0 {
                Text("Select conversations to export")
                    .font(.title2)
                Text("Tick the boxes in the sidebar, then click **Export** in the toolbar.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            } else {
                Text("\(selectedCount) of \(totalCount) selected")
                    .font(.title2)
                    .monospacedDigit()
                Text("Click **Export \(selectedCount) selected** in the toolbar when you're ready.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Spacer()

            if let version = sidecarVersion {
                Text(version)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
