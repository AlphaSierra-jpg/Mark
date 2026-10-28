import AppKit
import SwiftUI
import WebKit

/// The window contents for one open Markdown file.
struct MarkdownDocumentView: View {
    let fileURL: URL?
    let fallbackText: String

    @StateObject private var model = MarkdownDocumentModel()

    var body: some View {
        ZStack {
            MarkdownWebView(controller: model.controller)

            if let message = model.errorMessage {
                FailureView(message: message)
            }
        }
        .frame(minWidth: 420, minHeight: 320)
        .navigationTitle(fileURL?.lastPathComponent ?? "Markdown")
        .focusedSceneValue(\.reloadAction) { model.controller.refreshContents() }
        .onAppear { model.open(fileURL: fileURL, fallbackText: fallbackText) }
        .onChange(of: fileURL) { _, newValue in
            model.open(fileURL: newValue, fallbackText: fallbackText)
        }
    }
}

private struct FailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Mark could not display this document.")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(.background)
    }
}

// MARK: - Model

@MainActor
final class MarkdownDocumentModel: ObservableObject {
    let controller = MarkdownPreviewController()

    @Published var errorMessage: String?

    private var openedURL: URL?
    private var temporaryDocument: URL?

    init() {
        controller.linkHandler = { url in
            // External links belong to whatever already handles them; another
            // Markdown file opens in Mark because Mark is its handler.
            NSWorkspace.shared.open(url)
        }
    }

    deinit {
        if let temporaryDocument {
            try? FileManager.default.removeItem(at: temporaryDocument.deletingLastPathComponent())
        }
    }

    func open(fileURL: URL?, fallbackText: String) {
        do {
            let url = try resolve(fileURL: fileURL, fallbackText: fallbackText)
            guard url != openedURL else { return }
            openedURL = url
            errorMessage = nil
            // A document with a real URL on disk is the only case worth
            // watching; the fallback copy never changes behind our back.
            try controller.open(fileURL: url, watchForChanges: fileURL != nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// `DocumentGroup` can in principle hand over a document with no URL. Mark
    /// renders from a file on disk, so spill the text into a temporary one
    /// rather than showing nothing.
    private func resolve(fileURL: URL?, fallbackText: String) throws -> URL {
        if let fileURL { return fileURL }
        if let temporaryDocument { return temporaryDocument }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mark", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let destination = directory.appendingPathComponent("Untitled.md")
        try fallbackText.write(to: destination, atomically: true, encoding: .utf8)
        temporaryDocument = destination
        return destination
    }
}

// MARK: - Web view

/// Hands the shared controller's web view to SwiftUI.
private struct MarkdownWebView: NSViewRepresentable {
    let controller: MarkdownPreviewController

    func makeNSView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
