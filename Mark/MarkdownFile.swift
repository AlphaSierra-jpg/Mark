import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `net.daringfireball.markdown` is declared by the system, and imported
    /// again in Mark's Info.plist so the Finder offers Mark as a reader.
    static let markdownDocument = UTType("net.daringfireball.markdown") ?? .plainText
}

/// The document Mark opens. It is deliberately read-only: the text is loaded so
/// that `DocumentGroup` has something to hand the window, and writing back is
/// not supported.
struct MarkdownFile: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownDocument, .plainText] }

    /// Empty on purpose — an empty list is what makes the document read-only,
    /// so no Save, Duplicate or Rename commands appear.
    static var writableContentTypes: [UTType] { [] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else {
            text = String(decoding: data, as: UTF8.self)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}
