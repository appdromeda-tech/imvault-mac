import Contacts
import SwiftUI

struct ContentView: View {
    enum LoadState {
        case loading
        case loaded([Chat])
        case failure(String)
    }

    let contactsStatus: CNAuthorizationStatus

    @State private var loadState: LoadState = .loading
    @State private var selection: Set<Int> = []
    @State private var searchText: String = ""
    @State private var showingExportPlaceholder = false
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
        .alert("Export coming in Phase 4b", isPresented: $showingExportPlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The export sheet (output path + password + progress) lands in Phase 4b. For now you can run from Terminal:\n\nimvault export \(selection.sorted().map { "--chat \($0)" }.joined(separator: " "))")
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
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingExportPlaceholder = true
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

#Preview {
    ContentView(contactsStatus: .authorized)
}
