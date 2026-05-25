import SwiftUI

struct ContentView: View {
    enum SmokeResult {
        case idle
        case loading
        case version(String)
        case chats([Chat])
        case failure(String)
    }

    @State private var result: SmokeResult = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("imvault")
                .font(.largeTitle)
            Text("Phase 2b — sidecar smoke test")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Check sidecar version") {
                    Task { await runCheckVersion() }
                }
                Button("List chats") {
                    Task { await runListChats() }
                }
            }
            .disabled(isLoading)

            Divider()

            resultView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }

    private var isLoading: Bool {
        if case .loading = result { return true }
        return false
    }

    @ViewBuilder private var resultView: some View {
        switch result {
        case .idle:
            Text("Tap a button to call the bundled CLI.")
                .foregroundStyle(.secondary)
        case .loading:
            ProgressView()
        case .version(let v):
            Text(v)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
        case .chats(let chats):
            chatList(chats)
        case .failure(let message):
            errorView(message)
        }
    }

    @ViewBuilder private func chatList(_ chats: [Chat]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(chats.count) conversation\(chats.count == 1 ? "" : "s")")
                .font(.headline)
            List(chats) { chat in
                HStack {
                    VStack(alignment: .leading) {
                        Text(chat.displayName).bold()
                        if let last = chat.lastMessageAt {
                            Text(last)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(chat.messageCount) msgs")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
    }

    @ViewBuilder private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Error")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            if looksLikeFDA(message) {
                Text("imvault needs Full Disk Access to read iMessage history. Grant it in System Settings → Privacy & Security → Full Disk Access, then quit and relaunch.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func looksLikeFDA(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("permission denied")
            || lower.contains("operation not permitted")
            || lower.contains("chat.db")
    }

    @MainActor
    private func runCheckVersion() async {
        result = .loading
        do {
            let v = try await IMVaultCLI.version()
            result = .version(v)
        } catch {
            result = .failure(error.localizedDescription)
        }
    }

    @MainActor
    private func runListChats() async {
        result = .loading
        do {
            let chats = try await IMVaultCLI.listChats()
            result = .chats(chats)
        } catch {
            result = .failure(error.localizedDescription)
        }
    }
}

#Preview {
    ContentView()
}
