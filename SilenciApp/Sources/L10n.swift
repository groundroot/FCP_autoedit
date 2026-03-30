import Foundation

/// Localization helper — finds the resource bundle manually to avoid SwiftPM Bundle.module crashes
/// when the app is distributed as a standalone .app bundle.
enum L10n {
    /// The resource bundle containing Localizable.strings.
    /// Searches multiple possible locations to work in both development (swift run) and distribution (.app).
    private static let bundle: Bundle = {
        let bundleName = "SilenciApp_SilenciApp"

        // 1. Next to the executable (Contents/MacOS/)
        let executableURL = Bundle.main.bundleURL
        if let b = Bundle(url: executableURL.appendingPathComponent("\(bundleName).bundle")) {
            return b
        }

        // 2. In Resources (Contents/Resources/)
        if let resourceURL = Bundle.main.resourceURL,
           let b = Bundle(url: resourceURL.appendingPathComponent("\(bundleName).bundle")) {
            return b
        }

        // 3. In the app bundle root
        if let b = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName).bundle")) {
            return b
        }

        // 4. Two levels up from executable (Contents/MacOS/../../Resources/)
        let twoUp = executableURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(bundleName).bundle")
        if let b = Bundle(path: twoUp.path) {
            return b
        }

        // 5. Fallback: use main bundle (strings won't be localized but app won't crash)
        print("[L10n] ⚠️ Resource bundle not found — falling back to Bundle.main")
        return Bundle.main
    }()

    static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return String(format: format, arguments: args)
    }
}
