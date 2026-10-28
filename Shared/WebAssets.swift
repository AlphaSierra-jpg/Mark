import Foundation

/// Locates the bundle that carries the embedded web assets.
///
/// `Bundle.main` is the app when this code runs in Mark and the appex when it
/// runs in the Quick Look extension, so resolving through a class in the
/// current binary is what keeps one implementation correct in both.
private final class BundleToken {}

enum WebAssets {
    enum Error: Swift.Error, LocalizedError {
        case missingResource(String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name):
                return "Missing embedded resource “\(name)” in \(WebAssets.bundle.bundleURL.lastPathComponent)."
            }
        }
    }

    static let bundle = Bundle(for: BundleToken.self)

    /// Reads a file that ships inside the bundle. Everything Mark renders with
    /// is embedded, so there is never a network request.
    static func string(_ name: String) throws -> String {
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "web") else {
            throw Error.missingResource(name)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
