import AppKit
import QuickLookUI

/// Quick Look preview for Markdown files.
///
/// Pressing space in the Finder lands here. The rendering is not reimplemented:
/// this hosts the very same `MarkdownPreviewController` the app uses, so the
/// preview and the window show identical output from identical assets.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private let controller = MarkdownPreviewController()

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let webView = controller.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        view = container
    }

    /// Quick Look takes the preview's snapshot once this calls back, so the
    /// handler fires only after the first render has actually landed.
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        controller.onInitialRender = { error in
            handler(error)
        }

        do {
            // A preview is discarded as soon as it closes; watching the file
            // would be work with nobody left to see it.
            try controller.open(fileURL: url, watchForChanges: false)
        } catch {
            handler(error)
        }
    }
}
