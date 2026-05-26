import SwiftUI

@main
struct ImvaultApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Archive…") {
                    NotificationCenter.default.post(name: .openArchiveRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        // Archive viewer — each open .imv gets its own resizable window.
        // The UUID parameter looks up a live session in `ViewerStore.shared`;
        // the password never enters the window-restoration state stream.
        WindowGroup(id: "viewer", for: UUID.self) { $id in
            if let id {
                ArchiveViewerWindowContainer(id: id)
            }
        }
        .defaultSize(width: 1000, height: 700)
    }
}
