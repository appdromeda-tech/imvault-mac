import Foundation

// JSON shapes emitted by `imvault` v0.3.0.
// All snake_case keys are mapped via JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase.

struct Chat: Codable, Identifiable, Hashable, Sendable {
    let chatId: Int
    let displayName: String
    let participantCount: Int
    let messageCount: Int
    let lastMessageAt: String?

    var id: Int { chatId }
}

struct ChatBreakdown: Codable, Hashable, Sendable {
    let chatId: Int
    let displayName: String
    let messages: Int
    let attachmentEntries: Int
    let attachmentPresent: Int
    let attachmentMissing: Int
}

struct ArchiveInfo: Codable, Hashable, Sendable {
    let path: String
    let chats: [ChatBreakdown]
    let chatCount: Int
    let messages: Int
    let attachmentEntries: Int
    let attachmentPresent: Int
    let attachmentMissing: Int
    let uniqueAttachmentFiles: Int
    let missingAttachmentFiles: Int
}

struct CompareAttachments: Codable, Hashable, Sendable {
    let source: String
    let target: String
    let sourceUniqueAttachments: Int
    let targetUniqueAttachments: Int
    let sourcePresentInTarget: Int
    let missingFromTarget: Int
}

struct InspectResult: Codable, Hashable, Sendable {
    let archives: [ArchiveInfo]
    let compareAttachments: CompareAttachments?
}

struct ExportEvent: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case chatStarted = "chat_started"
        case chatDone = "chat_done"
        case attachment
    }
    let event: Kind
    let chatId: Int?
    let processed: Int
    let total: Int
}

// Error envelope used by the CLI when `--json` is set and something fails.
// e.g. {"error": "Permission denied: ~/Library/Messages/chat.db"}.
struct CLIErrorPayload: Codable, Sendable {
    let error: String
    let path: String?
}
