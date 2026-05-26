import SwiftUI
import WebKit

/// The root view of the archive-viewer `WindowGroup`. Looks up the session in
/// `ViewerStore.shared` by the UUID embedded in the window value; if there's
/// no live session (e.g., macOS restored the window after a relaunch — sessions
/// live only in memory, by design, so the password never persists), shows a
/// graceful placeholder.
struct ArchiveViewerWindowContainer: View {
    let id: UUID

    var body: some View {
        if let session = ViewerStore.shared.session(for: id) {
            ArchiveViewerWindow(id: id, session: session)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Viewer session ended")
                    .font(.headline)
                Text("Re-open the backup from the main window.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(minWidth: 480, minHeight: 240)
            .navigationTitle("imvault Backup")
        }
    }
}

/// Hosts a single archive's reader UI inside its own window. The window is
/// fully resizable, draggable, full-screenable. When the user closes the
/// window the `.onDisappear` modifier tears down the underlying subprocess
/// via `ViewerStore.close(id)`.
struct ArchiveViewerWindow: View {
    let id: UUID
    @ObservedObject var session: ArchiveViewerSession

    var body: some View {
        content
            .frame(minWidth: 700, minHeight: 500)
            .navigationTitle(session.archiveURL?.lastPathComponent ?? "imvault Backup")
            .onDisappear {
                ViewerStore.shared.close(id)
            }
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .idle, .starting:
            startingView
        case .ready(let url):
            WebView(url: url)
                .id(url)
        case .failed(let message):
            failureView(message)
        }
    }

    @ViewBuilder private var startingView: some View {
        VStack(spacing: 14) {
            Spacer()
            if let progress = currentProgress, let fraction = progress.fraction {
                ProgressView(value: fraction) {
                    Text(progress.label)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 460)
                Text("\(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                ProgressView()
                    .controlSize(.large)
                Text(currentProgress?.label ?? "Preparing…")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .lineLimit(2, reservesSpace: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentProgress: ArchiveViewerSession.Progress? {
        if case .starting(let progress) = session.state {
            return progress
        }
        return nil
    }

    @ViewBuilder private func failureView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 36))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't open backup")
                        .font(.title2)
                        .bold()
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - WKWebView wrapper

private struct WebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.url != url {
            view.load(URLRequest(url: url))
        }
    }
}
