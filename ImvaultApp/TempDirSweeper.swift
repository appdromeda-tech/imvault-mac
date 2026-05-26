import Foundation

/// Cleans up `imvault_*` temp directories that previous viewer sessions may
/// have left behind after a force-quit. The CLI's `view` command uses
/// `tempfile.TemporaryDirectory(prefix="imvault_")` which lives under
/// `NSTemporaryDirectory()` (same `/var/folders/.../T/` per-user tmp); the
/// directory is normally cleaned up when Python exits cleanly via SIGINT, but
/// SIGKILL or sudden parent-process death leaves it behind. macOS does sweep
/// these eventually but not promptly, and at multi-GB they're worth claiming
/// back.
///
/// Conservatism: we only delete entries older than 5 minutes so we never race
/// a session that's currently starting up on another launch.
enum TempDirSweeper {
    private static let prefix = "imvault_"
    private static let minimumAge: TimeInterval = 5 * 60

    static func sweepOrphanedViewerTempDirs() {
        let tmp = NSTemporaryDirectory()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: tmp) else { return }

        let now = Date()
        for entry in entries where entry.hasPrefix(prefix) {
            let path = tmp + entry
            guard
                let attrs = try? fm.attributesOfItem(atPath: path),
                let mtime = (attrs[.modificationDate] as? Date)
                    ?? (attrs[.creationDate] as? Date)
            else { continue }

            guard now.timeIntervalSince(mtime) >= minimumAge else { continue }
            try? fm.removeItem(atPath: path)
        }
    }
}
