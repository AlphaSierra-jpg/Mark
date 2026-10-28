import Foundation

/// Builds the self-contained HTML shell that renders a Markdown file.
///
/// The shell inlines marked.js, highlight.js and github-markdown-css, so the
/// only subresources left to fetch are the author's own relative images. The
/// Markdown itself is never baked into the HTML: the native side pushes it in
/// through `Mark.setMarkdown`, which is what lets a reload keep the scroll
/// position.
enum MarkdownRenderer {
    /// HTML shell for a document, with `<base>` pointing at the document's own
    /// directory so relative images and links resolve the way the author wrote
    /// them.
    static func html(forDocumentAt fileURL: URL) throws -> String {
        let directory = fileURL.deletingLastPathComponent()
        var html = try WebAssets.string("template.html")

        let substitutions: [String: String] = [
            "__BASE_HREF__": escapeAttribute(directory.absoluteString),
            "__TITLE__": escapeText(fileURL.lastPathComponent),
            "__MARKDOWN_CSS__": try WebAssets.string("github-markdown.css"),
            "__HLJS_LIGHT_CSS__": try WebAssets.string("highlight-light.css"),
            "__HLJS_DARK_CSS__": try WebAssets.string("highlight-dark.css"),
            "__APP_CSS__": try WebAssets.string("app.css"),
            "__MARKED_JS__": try WebAssets.string("marked.min.js"),
            "__HLJS_JS__": try WebAssets.string("highlight.min.js"),
            "__BOOT_JS__": try WebAssets.string("boot.js")
        ]

        for (token, value) in substitutions {
            html = html.replacingOccurrences(of: token, with: value)
        }
        return html
    }

    /// Writes the shell into a private temporary directory and returns its URL.
    ///
    /// Keeping the shell out of the document's folder means Mark never writes
    /// into the directory it is reading.
    static func writeHTML(forDocumentAt fileURL: URL, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("index.html")
        try html(forDocumentAt: fileURL).write(to: destination, atomically: true, encoding: .utf8)
        return destination
    }

    /// JavaScript that hands the current Markdown source to the renderer.
    static func setMarkdownScript(_ markdown: String) -> String {
        "Mark.setMarkdown(\(jsonStringLiteral(markdown)));"
    }

    // MARK: - Escaping

    /// Encodes a Swift string as a JavaScript string literal, so Markdown
    /// containing quotes, backslashes or line separators can never break out of
    /// the `evaluateJavaScript` call.
    private static func jsonStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
