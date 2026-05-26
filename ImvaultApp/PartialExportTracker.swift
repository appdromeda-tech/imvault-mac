import Foundation

/// Tracks `.imv` files that are mid-export so they can be detected and offered
/// for cleanup if the app dies before the export finishes.
///
/// ExportSheet calls `markStarted(url)` when the subprocess launches and
/// `markFinished(url)` on completion / explicit cancel. If the app crashes or
/// is force-quit before `markFinished` fires, the entry survives on disk. On
/// next launch, `detectOrphans()` returns the still-existing partial files —
/// AppDelegate surfaces them via NotificationCenter, RootView shows a prompt.
///
/// Storage: a single JSON array at
///   ~/Library/Application Support/imvault/in_progress_exports.json
/// containing the absolute paths. Reads/writes are best-effort; corrupt or
/// missing files are treated as empty.
enum PartialExportTracker {
    private static let dirName = "imvault"
    private static let fileName = "in_progress_exports.json"

    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let dir = appSupport.appendingPathComponent(dirName, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir.appendingPathComponent(fileName)
    }

    static func markStarted(_ url: URL) {
        modify { paths in
            paths.insert(url.path)
        }
    }

    static func markFinished(_ url: URL) {
        modify { paths in
            paths.remove(url.path)
        }
    }

    /// Returns the tracked paths that still exist on disk — i.e. partial
    /// outputs from a session that didn't unregister cleanly. Removes any
    /// tracked paths that no longer exist (likely deleted by the catch
    /// block on a normal failure).
    static func detectOrphans() -> [URL] {
        var orphans: [URL] = []
        modify { paths in
            let fm = FileManager.default
            var survivors: Set<String> = []
            for path in paths {
                if fm.fileExists(atPath: path) {
                    orphans.append(URL(fileURLWithPath: path))
                    survivors.insert(path)
                }
            }
            paths = survivors
        }
        return orphans
    }

    static func forget(_ url: URL) {
        modify { paths in
            paths.remove(url.path)
        }
    }

    // MARK: - I/O

    private static func read() -> Set<String> {
        guard let url = fileURL else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(array)
    }

    private static func write(_ paths: Set<String>) {
        guard let url = fileURL else { return }
        if paths.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let sorted = paths.sorted()
        guard let data = try? JSONEncoder().encode(sorted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static let lock = NSLock()

    private static func modify(_ mutate: (inout Set<String>) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var paths = read()
        mutate(&paths)
        write(paths)
    }
}

