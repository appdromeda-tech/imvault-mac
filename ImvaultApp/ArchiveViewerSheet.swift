import SwiftUI
import WebKit

/// Hosts a single archive's reader UI: spawns `imvault view`, then displays the
/// resulting localhost URL in a WKWebView. Dismiss tears the subprocess down.
struct ArchiveViewerSheet: View {
    let archive: URL
    let password: String
    let onDismiss: () -> Void

    @StateObject private var session = ArchiveViewerSession()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 900, minHeight: 600)
        .task {
            await session.start(archive: archive, password: password)
        }
    }

    @ViewBuilder private var header: some View {
        HStack {
            Image(systemName: "lock.doc")
                .foregroundStyle(.tint)
            Text(archive.lastPathComponent)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Close") {
                Task {
                    await session.stop()
                    onDismiss()
                }
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                    Text("Couldn't open archive")
                        .font(.title2)
                        .bold()
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("Close") {
                    Task {
                        await session.stop()
                        onDismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
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
