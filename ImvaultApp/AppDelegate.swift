import AppKit

/// Hooks `applicationShouldTerminate` so we can interrupt every live
/// subprocess (and let it clean up its tempdirs) before macOS reaps us.
/// Without this, ⌘Q while a viewer was open would leak its decrypted-archive
/// tempdir, and ⌘Q mid-export would leave a partial `.imv` on disk.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Best-effort sweep of any orphaned tempdirs from a previous force-quit.
        TempDirSweeper.sweepOrphanedViewerTempDirs()
        // Orphaned partial exports are surfaced by ContentView itself, in its
        // .task — that lets us defer the prompt until the user is past any
        // FDA onboarding (no point asking about ghost files behind a gate).
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clear any lingering dock-tile state.
        NSApp.dockTile.badgeLabel = nil
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let registry = SubprocessRegistry.shared
        registry.beginShutdown {
            // beginShutdown's completion runs off-main; hop back so the
            // AppKit reply happens on the main thread.
            DispatchQueue.main.async {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    /// Quit when the last window closes — single-window app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
