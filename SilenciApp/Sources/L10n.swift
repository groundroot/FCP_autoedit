import Foundation

/// Localization helper — finds the resource bundle manually to avoid SwiftPM Bundle.module crashes
/// when the app is distributed as a standalone .app bundle.
enum L10n {
    /// Supported app languages.
    enum AppLanguage: String, CaseIterable, Identifiable {
        case system = "system"
        case ko = "ko"
        case en = "en"
        case ja = "ja"
        case zhHans = "zh-Hans"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: return "시스템 기본"
            case .ko: return "한국어"
            case .en: return "English"
            case .ja: return "日本語"
            case .zhHans: return "中文"
            }
        }
    }

    /// Current app language override. "system" means follow system locale.
    static var currentLanguage: AppLanguage {
        get {
            let raw = UserDefaults.standard.string(forKey: "sc_appLanguage") ?? "system"
            return AppLanguage(rawValue: raw) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "sc_appLanguage")
            // Invalidate cached bundle
            _overrideBundle = nil
        }
    }

    /// Cached language-specific bundle.
    nonisolated(unsafe) private static var _overrideBundle: Bundle?

    /// The effective bundle for the current language setting.
    ///
    /// - system: Bundle.main을 그대로 사용 — macOS가 CFBundleLocalizations 목록에서
    ///   사용자 시스템 언어와 가장 잘 맞는 .lproj를 자동 선택함.
    /// - 특정 언어: Bundle.main.resourceURL 아래의 {lang}.lproj 번들을 직접 사용.
    private static var bundle: Bundle {
        if let cached = _overrideBundle { return cached }

        let lang = currentLanguage
        if lang == .system {
            _overrideBundle = Bundle.main
            return Bundle.main
        }

        if let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"),
           let b = Bundle(path: path) {
            _overrideBundle = b
            return b
        }

        _overrideBundle = Bundle.main
        return Bundle.main
    }

    static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        return String(format: format, arguments: args)
    }
}
