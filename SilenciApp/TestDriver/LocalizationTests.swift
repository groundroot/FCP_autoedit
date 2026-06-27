import Foundation
import Testing
@testable import SilenciCore

@Suite("Localization — App Store launch markets") @MainActor
struct LocalizationTests {
    private var packageRoot: URL {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<5 {
            if fm.fileExists(atPath: dir.appendingPathComponent("Sources/Resources").path) {
                return dir
            }
            dir.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: fm.currentDirectoryPath)
    }

    private var resourcesURL: URL {
        packageRoot.appendingPathComponent("Sources/Resources", isDirectory: true)
    }

    private var expectedAppLocales: Set<String> {
        Set(L10n.AppLanguage.allCases.compactMap { language in
            language == .system ? nil : language.rawValue
        })
    }

    private let topNonGamingAppSpendMarketLocales: [String: Set<String>] = [
        "United States": ["en"],
        "China": ["zh-Hans"],
        "Japan": ["ja"],
        "United Kingdom": ["en"],
        "Germany": ["de"],
        "Canada": ["en", "fr"],
        "Australia": ["en"],
        "South Korea": ["ko"],
        "France": ["fr"],
        "Brazil": ["pt-BR"],
    ]

    private let additionalVideoEditingMarketLocales: [String: Set<String>] = [
        "Taiwan": ["zh-Hant"],
        "Spain": ["es"],
        "Italy": ["it"],
    ]

    @Test func appLanguageEnumMatchesResourceFolders() throws {
        let folders = try FileManager.default.contentsOfDirectory(
            at: resourcesURL,
            includingPropertiesForKeys: nil
        )
        let lprojLocales = Set(folders.compactMap { url -> String? in
            url.pathExtension == "lproj" ? url.deletingPathExtension().lastPathComponent : nil
        })

        #expect(lprojLocales == expectedAppLocales)
    }

    @Test func infoPlistDeclaresAllAppLocales() throws {
        let infoURL = packageRoot.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let dict = try #require(plist as? [String: Any])
        let declared = try #require(dict["CFBundleLocalizations"] as? [String])

        #expect(Set(declared) == expectedAppLocales)
    }

    @Test func everyLocalizationHasSameKeysAsEnglish() throws {
        let baseKeys = try localizationKeys(for: "en")

        for locale in expectedAppLocales.sorted() {
            let keys = try localizationKeys(for: locale)
            #expect(keys == baseKeys, "Missing or extra localization keys in \(locale)")
        }
    }

    @Test func speechLanguagesHaveLocalizedLabels() throws {
        let baseKeys = try localizationKeys(for: "en")
        for language in AnalysisSettings.languages {
            let key = "speech_language." + language
                .replacingOccurrences(of: " ", with: "_")
                .lowercased()
            #expect(baseKeys.contains(key))
        }
    }

    @Test func topNonGamingAppSpendMarketsHaveUILocaleCoverage() {
        for market in topNonGamingAppSpendMarketLocales {
            #expect(!market.value.isDisjoint(with: expectedAppLocales), "\(market.key) is not covered")
        }
    }

    @Test func additionalVideoEditingMarketsHaveUILocaleCoverage() {
        for market in additionalVideoEditingMarketLocales {
            #expect(!market.value.isDisjoint(with: expectedAppLocales), "\(market.key) is not covered")
        }
    }

    private func localizationKeys(for locale: String) throws -> Set<String> {
        let url = resourcesURL
            .appendingPathComponent("\(locale).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        let strings = try #require(plist as? [String: String])
        return Set(strings.keys)
    }
}
