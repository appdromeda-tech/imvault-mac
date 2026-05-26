import AppKit
import Contacts
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    enum LoadState {
        case loading
        case loaded([Chat])
        case failure(String)
    }

    enum ActiveSheet: Identifiable {
        case export
        case openArchivePassword(URL)

        var id: String {
            switch self {
            case .export: return "export"
            case .openArchivePassword(let url): return "open-pw:\(url.path)"
            }
        }
    }

    let contactsStatus: CNAuthorizationStatus

    @Environment(\.openWindow) private var openWindow

    @State private var loadState: LoadState = .loading
    @State private var selection: Set<Int> = []
    @State private var searchText: String = ""
    @State private var activeSheet: ActiveSheet?
    @State private var sidecarVersion: String?
    @State private var orphanedExports: [URL] = []
    @State private var didCheckOrphans = false
    @State private var showingWelcome = false

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
            // Welcome takes priority over orphan prompts — first-time users
            // need context before being asked to delete files.
            if !WelcomeSheet.hasBeenShown {
                showingWelcome = true
            } else {
                checkOrphanedExports()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .sheet(isPresented: $showingWelcome) {
            WelcomeSheet(onDismiss: {
                showingWelcome = false
                // Orphan check was skipped during welcome; do it now.
                checkOrphanedExports()
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: .openArchiveRequested)) { _ in
            presentOpenArchivePicker()
        }
        .onOpenURL { url in
            // Triggered when the user double-clicks a .imv file in Finder
            // (the file association in Info.plist routes it to us) or drops
            // it on the app icon.
            guard url.pathExtension.lowercased() == "imv" else { return }
            activeSheet = .openArchivePassword(url)
        }
        .alert(
            "Unfinished backup files",
            isPresented: orphansAlertBinding,
            presenting: orphanedExports
        ) { orphans in
            Button("Delete", role: .destructive) {
                deleteOrphans(orphans)
                orphanedExports = []
            }
            Button("Keep") {
                // Forget them so we don't re-prompt; leave the files on disk.
                for url in orphans { PartialExportTracker.forget(url) }
                orphanedExports = []
            }
        } message: { orphans in
            Text(orphansMessage(for: orphans))
        }
    }

    private var orphansAlertBinding: Binding<Bool> {
        Binding(
            get: { !orphanedExports.isEmpty },
            set: { newValue in
                if !newValue { orphanedExports = [] }
            }
        )
    }

    private func orphansMessage(for orphans: [URL]) -> String {
        if orphans.count == 1 {
            return "imvault was interrupted while saving:\n\n\(orphans[0].path)\n\nThis backup is incomplete and can't be opened. Delete it?"
        }
        let list = orphans.prefix(5).map { "  • \($0.lastPathComponent)" }.joined(separator: "\n")
        let extra = orphans.count > 5 ? "\n  …and \(orphans.count - 5) more" : ""
        return "Found \(orphans.count) unfinished backups from a previous session:\n\n\(list)\(extra)\n\nThese can't be opened. Delete them?"
    }

    private func checkOrphanedExports() {
        guard !didCheckOrphans else { return }
        didCheckOrphans = true
        let orphans = PartialExportTracker.detectOrphans()
        if !orphans.isEmpty {
            orphanedExports = orphans
        }
    }

    private func deleteOrphans(_ orphans: [URL]) {
        for url in orphans {
            try? FileManager.default.removeItem(at: url)
            PartialExportTracker.forget(url)
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
                Label("Open a Backup…", systemImage: "lock.doc")
            }
            .help("Open a saved imvault backup file")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                activeSheet = .export
            } label: {
                Label(
                    selection.isEmpty
                        ? "Back Up…"
                        : "Back Up \(selection.count) Selected…",
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
                    // Dismiss the password sheet first, then open the archive
                    // in its own resizable window. ViewerStore holds the live
                    // session in memory; the window restoration parameter is
                    // just a UUID, so the password never persists to disk.
                    activeSheet = nil
                    let id = ViewerStore.shared.open(archive: url, password: password)
                    openWindow(id: "viewer", value: id)
                },
                onCancel: {
                    activeSheet = nil
                }
            )
        }
    }

    private func presentOpenArchivePicker() {
        let panel = NSOpenPanel()
        panel.title = "Open Backup"
        panel.prompt = "Open"
        panel.message = "Choose an imvault backup file (.imv) to open."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        // Filter to the UTI we registered in Info.plist (com.appdromeda.imvault.backup).
        // Falls back to no filter on the off-chance the UTI isn't yet known.
        if let imvType = UTType("com.appdromeda.imvault.backup") {
            panel.allowedContentTypes = [imvType]
        }
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
