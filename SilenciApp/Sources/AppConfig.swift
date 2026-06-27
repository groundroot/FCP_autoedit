import Foundation

enum AppConfig {
    static let appName = "JaMak"
    static let bundleIdentifier = "com.daeyoung.jamak"

    #if APPSTORE
    static let isAppStoreBuild = true
    static let allowsExternalRuntimeInstall = false
    static let allowsModelDownload = true
    static let showsProFeatures = false
    static let allowsMP4Export = false
    #else
    static let isAppStoreBuild = false
    static let allowsExternalRuntimeInstall = true
    static let allowsModelDownload = true
    static let showsProFeatures = true
    static let allowsMP4Export = true
    #endif

    static var enabledExportFormats: [ExportFormat] {
        #if APPSTORE
        return [.fcpxml, .srt]
        #else
        return ExportFormat.allCases
        #endif
    }
}

enum AppPaths {
    static var appSupportDir: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppConfig.appName, isDirectory: true)
    }

    static var huggingFaceHomeDir: URL {
        appSupportDir.appendingPathComponent("HuggingFace", isDirectory: true)
    }

    static var huggingFaceHubDir: URL {
        huggingFaceHomeDir.appendingPathComponent("hub", isDirectory: true)
    }

    static var modelDir: URL {
        appSupportDir.appendingPathComponent("Models", isDirectory: true)
    }

    static func createRuntimeDirectoriesIfNeeded() {
        let fm = FileManager.default
        try? fm.createDirectory(at: appSupportDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: huggingFaceHomeDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: modelDir, withIntermediateDirectories: true)
    }
}
