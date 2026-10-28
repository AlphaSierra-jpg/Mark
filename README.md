# Mark

Mark is a lightweight Markdown reader for macOS. Double-click a .md file and it opens fully formatted, just like a PDF in Preview: headings, lists, tables, code, and images, with no editor and no setup.

- **GitHub styling** via `github-markdown-css`, following the system light/dark appearance.
- **Syntax highlighting** via `highlight.js`, with matching light and dark themes.
- **Live reload** — edit the file in any editor and the window updates in place, keeping your scroll position. Atomic saves (write-then-rename) are handled.
- **Relative images and links** resolve against the document's own folder.
- **Quick Look** — select a .md file in the Finder, press space, and get the same rendering.

Everything is embedded in the app. There is no CDN and no network request; Mark works entirely offline.

## Build

The Xcode project is generated, not committed. You need [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project Mark.xcodeproj -scheme Mark -configuration Release \
    -derivedDataPath build CODE_SIGN_IDENTITY="-" build
```

## Release

```sh
./scripts/make-dmg.sh            # builds Release, writes dist/Mark-<version>.dmg
./scripts/make-dmg.sh --no-build # repackage what is already built
```

The DMG holds `Mark.app` next to an `Applications` shortcut, and is ad hoc
signed like the app. Bump `MARKETING_VERSION` in `project.yml` to version it.

## Icon

Drop a square source image (1024x1024) through:

```sh
./scripts/make-icon.sh path/to/logo.png
```

It writes every macOS size into `Mark/Assets.xcassets/AppIcon.appiconset`, so
the next build picks it up.

## Install

```sh
ditto build/Build/Products/Release/Mark.app /Applications/Mark.app
open -a /Applications/Mark.app          # registers the Quick Look extension
qlmanage -r && qlmanage -r cache        # reload Quick Look
pluginkit -m -p com.apple.quicklook.preview | grep Mark   # verify
```

To make Mark the default reader, select a `.md` file in the Finder, press ⌘I, and choose Mark under *Open with* → *Change All*.

## Layout

| Path | What |
| ---- | ---- |
| `Shared/` | The renderer: HTML shell, file watcher, `WKWebView` controller — compiled into both targets |
| `Shared/Resources/web/` | Embedded marked.js, highlight.js, github-markdown-css |
| `Mark/` | The SwiftUI app (`DocumentGroup(viewing:)`) |
| `MarkQuickLook/` | The Quick Look preview extension |
| `scripts/` | `make-dmg.sh` (release artifact), `make-icon.sh` (app icon) |

## Notes

The app runs **unsandboxed** on purpose: it renders a generated HTML shell from a temporary directory while the document's images sit next to the document, and granting WebKit read access across both is what makes relative paths work without a folder prompt per document. The Quick Look extension *is* sandboxed, as the system requires.
