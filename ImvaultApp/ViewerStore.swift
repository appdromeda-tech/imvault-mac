import Foundation

/// Holds live `ArchiveViewerSession` instances keyed by UUID so the viewer
/// `WindowGroup` can look one up by ID without the password ever leaving
/// memory.
///
/// SwiftUI's `WindowGroup(for:)` parameters get persisted into window state
/// restoration, so we can't pass the password directly — instead we pass a
/// UUID, and the actual session (with its password-backed subprocess) lives
/// in this store. ContentView calls `open(archive:password:)` to register a
/// session, then `openWindow(id: "viewer", value: id)` to surface a window.
@MainActor
final class ViewerStore: ObservableObject {
    static let shared = ViewerStore()

    private var sessions: [UUID: ArchiveViewerSession] = [:]

    /// Register a new session and start its subprocess. Returns the ID to
    /// hand to `openWindow`.
    func open(archive: URL, password: String) -> UUID {
        let id = UUID()
        let session = ArchiveViewerSession()
        sessions[id] = session
        Task { await session.start(archive: archive, password: password) }
        return id
    }

    func session(for id: UUID) -> ArchiveViewerSession? {
        sessions[id]
    }

    /// Stop and forget the session. Called by ArchiveViewerWindow's
    /// `.onDisappear` when the user closes the window.
    func close(_ id: UUID) {
        if let session = sessions[id] {
            Task { await session.stop() }
        }
        sessions.removeValue(forKey: id)
    }
}
