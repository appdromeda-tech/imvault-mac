import AppKit
import Contacts
import SwiftUI

struct ContentView: View {
    enum LoadState {
        case loading
        case loaded([Chat])
        case failure(String)
    }

    enum ActiveSheet: Identifiable {
        case export
        case openArchivePassword(URL)
        case viewer(URL, String)

        var id: String {
            switch self {
            case .export: return "export"
            case .openArchivePassword(let url): return "open-pw:\(url.path)"
            case .viewer(let url, _): return "viewer:\(url.path)"
            }
        }
    }

    let contactsStatus: CNAuthorizationStatus

    @State private var loadState: LoadState = .loading
    @State private var selection: Set<Int> = []
    @State private var searchText: String = ""
    @State private var activeSheet: ActiveSheet?
    @State private var sidecarVersion: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("imvault")
        .toolbar { toolbarContent }
        .frame(minWidth: 820, minHeight: 520)
        .task {
            sidecarVersion = try? await IMVaultCLI.version()
            await loadChats()
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openArchiveRequested)) { _ in
            presentOpenArchivePicker()
        }
    }

    @ViewBuilder private var sidebar: some View {
        switch loadState {
        case .loading:
            ProgressView("Loading conversations…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let chats):
            ChatSidebar(
                chats: chats,
                selection: $selection,
                searchText: $searchText,
                contactsStatus: contactsStatus
            )
        case .failure(let message):
            ErrorView(message: message) {
                Task { await loadChats() }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if case .loaded(let chats) = loadState {
            ChatDetailPlaceholder(
                selectedCount: selection.count,
                totalCount: chats.count,
                sidecarVersion: sidecarVersion
            )
        } else {
            // Match sidebar's loading/error state — keep the detail pane empty.
            Color.clear
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                presentOpenArchivePicker()
            } label: {
                Label("Open Archive…", systemImage: "lock.doc")
            }
            .help("Open and decrypt an existing .imv archive")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                activeSheet = .export
            } label: {
                Label(
                    selection.isEmpty
                        ? "Export…"
                        : "Export \(selection.count) selected…",
                    systemImage: "square.and.arrow.down"
                )
            }
            .disabled(selection.isEmpty)
        }
    }

    @ViewBuilder private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .export:
            if case .loaded(let chats) = loadState {
                ExportSheet(
                    chats: chats,
                    selectedChatIDs: selection.sorted(),
                    onDismiss: { activeSheet = nil }
                )
            }
        case .openArchivePassword(let url):
            OpenArchivePasswordSheet(
                archive: url,
                onSubmit: { password in
                    activeSheet = .viewer(url, password)
                },
                onCancel: {
                    activeSheet = nil
                }
            )
        case .viewer(let url, let password):
            ArchiveViewerSheet(
                archive: url,
                password: password,
                onDismiss: { activeSheet = nil }
            )
        }
    }

    private func presentOpenArchivePicker() {
        let panel = NSOpenPanel()
        panel.title = "Open imvault Archive"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // .imv has no registered UTI; let users pick anything.
        panel.allowedContentTypes = []
        if panel.runModal() == .OK, let url = panel.url {
            activeSheet = .openArchivePassword(url)
        }
    }

    @MainActor
    private func loadChats() async {
        loadState = .loading
        do {
            let chats = try await IMVaultCLI.listChats()
            loadState = .loaded(chats)
        } catch {
            loadState = .failure(error.localizedDescription)
        }
    }
}

extension Notification.Name {
    /// Posted by the File → Open Archive… menu command. ContentView listens.
    static let openArchiveRequested = Notification.Name("imvault.openArchiveRequested")
}

#Preview {
    ContentView(contactsStatus: .authorized)
}
