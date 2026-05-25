import Contacts
import SwiftUI

struct ChatSidebar: View {
    let chats: [Chat]
    @Binding var selection: Set<Int>
    @Binding var searchText: String
    let contactsStatus: CNAuthorizationStatus

    private var filteredChats: [Chat] {
        guard !searchText.isEmpty else { return chats }
        return chats.filter { chat in
            chat.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Selected IDs that are present in the currently-filtered view.
    private var filteredSelectedCount: Int {
        let visibleIDs = Set(filteredChats.map(\.id))
        return selection.intersection(visibleIDs).count
    }

    var body: some View {
        VStack(spacing: 0) {
            if shouldShowContactsBanner {
                contactsBanner
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
            }

            List {
                ForEach(filteredChats) { chat in
                    ChatRow(
                        chat: chat,
                        isSelected: selection.contains(chat.id),
                        onToggle: { toggle(chat.id) }
                    )
                }
            }
            .listStyle(.sidebar)

            Divider()
            footer
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search conversations")
        .frame(minWidth: 280)
    }

    @ViewBuilder private var footer: some View {
        HStack {
            Button(filteredSelectedCount == filteredChats.count && !filteredChats.isEmpty
                   ? "Deselect all"
                   : "Select all") {
                if filteredSelectedCount == filteredChats.count {
                    selection.subtract(filteredChats.map(\.id))
                } else {
                    selection.formUnion(filteredChats.map(\.id))
                }
            }
            .buttonStyle(.borderless)
            .disabled(filteredChats.isEmpty)

            Spacer()

            Text("\(selection.count) of \(chats.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func toggle(_ id: Int) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private var shouldShowContactsBanner: Bool {
        contactsStatus == .denied || contactsStatus == .restricted
    }

    @ViewBuilder private var contactsBanner: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Contacts access denied. Names will show as phone numbers or emails.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ChatRow: View {
    let chat: Chat
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle(
                "",
                isOn: Binding(
                    get: { isSelected },
                    set: { _ in onToggle() }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(chat.displayName)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(chat.messageCount) msg\(chat.messageCount == 1 ? "" : "s")")
                    if let last = chat.lastMessageAt, !last.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        // The CLI emits ISO timestamps; show the date portion only.
                        Text(String(last.prefix(10)))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .padding(.vertical, 2)
    }
}
