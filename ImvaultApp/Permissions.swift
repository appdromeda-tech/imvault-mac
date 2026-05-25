import AppKit
import Contacts
import Darwin
import Foundation

enum FDAStatus: Equatable, Sendable {
    case granted
    case missing
}

enum Permissions {
    static var chatDBPath: String {
        (("~/Library/Messages/chat.db") as NSString).expandingTildeInPath
    }

    /// Probe Full Disk Access by attempting to open ~/Library/Messages/chat.db.
    /// Returns `.granted` if open() succeeds or the file genuinely doesn't exist
    /// (a Mac that's never used iMessage — nothing to gate). Returns `.missing`
    /// on EPERM / EACCES.
    static func checkFullDiskAccess() -> FDAStatus {
        let fd = open(chatDBPath, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return .granted
        }
        // ENOENT: no Messages db on this Mac. Treat as "FDA not the blocker."
        if errno == ENOENT { return .granted }
        return .missing
    }

    /// Opens System Settings → Privacy & Security → Full Disk Access.
    /// FDA cannot be granted programmatically — the user must add the app and toggle it on.
    static func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    static func contactsStatus() -> CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Prompts the user for Contacts access. Resolves with the post-prompt status.
    /// The system only shows the prompt the first time; subsequent calls return immediately.
    @discardableResult
    static func requestContacts() async -> CNAuthorizationStatus {
        await withCheckedContinuation { cont in
            CNContactStore().requestAccess(for: .contacts) { _, _ in
                cont.resume(returning: CNContactStore.authorizationStatus(for: .contacts))
            }
        }
    }
}
