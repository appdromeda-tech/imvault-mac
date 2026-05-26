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
    }
}
