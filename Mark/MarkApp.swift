import SwiftUI

@main
struct MarkApp: App {
    var body: some Scene {
        // `viewing:` is the whole point: Mark opens documents and never offers
        // to save, create or edit one.
        DocumentGroup(viewing: MarkdownFile.self) { configuration in
            MarkdownDocumentView(
                fileURL: configuration.fileURL,
                fallbackText: configuration.document.text
            )
        }
        .defaultSize(width: 900, height: 1040)
        .commands {
            ReaderCommands()
        }
    }
}

/// Reloading is automatic, but a manual command is still worth having when a
/// file changes somewhere the watcher cannot see it (a network share, say).
private struct ReaderCommands: Commands {
    @FocusedValue(\.reloadAction) private var reload

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Reload") { reload?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(reload == nil)
        }
    }
}

// MARK: - Focused values

private struct ReloadActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var reloadAction: (() -> Void)? {
        get { self[ReloadActionKey.self] }
        set { self[ReloadActionKey.self] = newValue }
    }
}
