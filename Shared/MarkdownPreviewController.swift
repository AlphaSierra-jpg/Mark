import Foundation
import WebKit

#if canImport(AppKit)
import AppKit
#endif

/// Owns the `WKWebView` that renders a Markdown file, plus the file watcher
/// that keeps it in sync with the disk.
///
/// Both Mark and the Quick Look extension drive this same object: the app wraps
/// `webView` in an `NSViewRepresentable`, the extension installs it as its
/// view. Only the app asks for watching — a Quick Look panel is short-lived.
@MainActor
final class MarkdownPreviewController: NSObject {
    /// WebKit needs read access to both the generated shell (in a temporary
    /// directory) and the author's images (next to the document). Granting the
    /// filesystem root is what covers both in one call; what it actually
    /// resolves to is still whatever the process is allowed to read, which is
    /// everything for the unsandboxed app and the Quick Look grant inside the
    /// sandboxed extension.
    private static let readAccessRoot = URL(fileURLWithPath: "/", isDirectory: true)

    let webView: WKWebView

    /// Called when a link is activated. The app opens it in the default
    /// handler; leaving it `nil` makes links inert, which is what a Quick Look
    /// panel wants.
    var linkHandler: ((URL) -> Void)?

    /// Called once the first render has finished, or failed.
    var onInitialRender: ((Swift.Error?) -> Void)?

    private let temporaryDirectory: URL
    private var fileURL: URL?
    private var watcher: FileWatcher?
    private var hasReportedInitialRender = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Nothing is persisted: every render is rebuilt from the file on disk.
        configuration.websiteDataStore = .nonPersistent()

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        // Matches the page background in both appearances, so overscroll and
        // the first frame never flash the wrong colour.
        webView.underPageBackgroundColor = .textBackgroundColor

        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Mark", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        super.init()
        webView.navigationDelegate = self
    }

    deinit {
        let directory = temporaryDirectory
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Loading

    /// Renders the file, and optionally keeps the rendering in sync with it.
    func open(fileURL: URL, watchForChanges: Bool) throws {
        self.fileURL = fileURL

        let shell = try MarkdownRenderer.writeHTML(forDocumentAt: fileURL, in: temporaryDirectory)
        webView.loadFileURL(shell, allowingReadAccessTo: Self.readAccessRoot)

        if watchForChanges {
            let watcher = FileWatcher(url: fileURL) { [weak self] in
                self?.refreshContents()
            }
            self.watcher = watcher
            watcher.start()
        }
    }

    /// Re-reads the file and hands the new source to the renderer. The page is
    /// never reloaded, so the scroll position survives.
    func refreshContents() {
        guard let fileURL else { return }
        guard let markdown = Self.readMarkdown(at: fileURL) else { return }
        webView.evaluateJavaScript(MarkdownRenderer.setMarkdownScript(markdown))
    }

    private func renderInitialContents() {
        guard let fileURL else { return }

        guard let markdown = Self.readMarkdown(at: fileURL) else {
            reportInitialRender(CocoaError(.fileReadUnknown))
            return
        }

        webView.evaluateJavaScript(MarkdownRenderer.setMarkdownScript(markdown)) { [weak self] _, error in
            self?.reportInitialRender(error)
        }
    }

    private func reportInitialRender(_ error: Swift.Error?) {
        guard !hasReportedInitialRender else { return }
        hasReportedInitialRender = true
        onInitialRender?(error)
        onInitialRender = nil
    }

    /// Markdown files are UTF-8 in practice, but a file saved by an older tool
    /// should still be readable rather than showing nothing.
    private static func readMarkdown(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return latin1 }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - WKNavigationDelegate

extension MarkdownPreviewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        renderInitialContents()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Swift.Error) {
        reportInitialRender(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Swift.Error
    ) {
        reportInitialRender(error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Heading anchors are the one link that stays inside the document.
        if isFragmentJump(to: url) {
            decisionHandler(.allow)
            return
        }

        // Otherwise a reader never navigates away from what it is showing.
        decisionHandler(.cancel)
        linkHandler?(url)
    }

    private func isFragmentJump(to url: URL) -> Bool {
        guard url.fragment != nil, let current = webView.url else { return false }
        var target = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var here = URLComponents(url: current, resolvingAgainstBaseURL: true)
        target?.fragment = nil
        here?.fragment = nil
        return target?.url == here?.url
    }
}
