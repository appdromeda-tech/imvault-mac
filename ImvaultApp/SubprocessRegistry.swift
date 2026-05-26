import Foundation

/// Tracks live `imvault` subprocesses (viewer sessions, export runs) so the app
/// can shut them down cleanly on ⌘Q. Without this, force-quitting while a
/// viewer was open would leak its decrypted-archive tempdir under /var/folders,
/// and quitting mid-export would leave a partial `.imv` on disk.
///
/// Each owner registers an `interrupt` closure (SIGINT — Python catches this
/// and runs its finally blocks) and an `isRunning` probe. On
/// `applicationShouldTerminate`, AppDelegate calls `beginShutdown` which
/// interrupts all handles, waits up to 2 s for them to exit, then signals the
/// system to finish termination.
@MainActor
final class SubprocessRegistry {
    static let shared = SubprocessRegistry()

    private struct Handle {
        let interrupt: @Sendable () -> Void
        let isRunning: @Sendable () -> Bool
    }

    private var handles: [UUID: Handle] = [:]

    /// Holding the returned token unregisters automatically on deinit.
    final class Token {
        fileprivate let id: UUID
        private let onDeinit: @Sendable (UUID) -> Void
        fileprivate init(id: UUID, onDeinit: @escaping @Sendable (UUID) -> Void) {
            self.id = id
            self.onDeinit = onDeinit
        }
        deinit { onDeinit(id) }
    }

    @discardableResult
    func register(
        interrupt: @escaping @Sendable () -> Void,
        isRunning: @escaping @Sendable () -> Bool
    ) -> Token {
        let id = UUID()
        handles[id] = Handle(interrupt: interrupt, isRunning: isRunning)
        return Token(id: id) { [weak self] removed in
            Task { @MainActor [weak self] in
                self?.handles.removeValue(forKey: removed)
            }
        }
    }

    /// Interrupts every live subprocess and calls `completion` once they've all
    /// exited (or after 2 s, whichever is sooner). Safe to call when the
    /// registry is empty — completes immediately.
    func beginShutdown(completion: @escaping @Sendable () -> Void) {
        let snapshot = Array(handles.values)
        guard !snapshot.isEmpty else {
            completion()
            return
        }
        for handle in snapshot {
            handle.interrupt()
        }
        Task.detached(priority: .userInitiated) {
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline {
                let stillAlive = snapshot.contains { $0.isRunning() }
                if !stillAlive { break }
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
            }
            completion()
        }
    }
}
