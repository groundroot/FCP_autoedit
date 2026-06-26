import Foundation
import AppKit

extension Notification.Name {
    static let openFCPXMLFile = Notification.Name("com.textbasededit.openFCPXMLFile")
}

/// App 레벨 메뉴바 명령을 ContentView로 전달하는 상태 브리지.
@Observable
@MainActor
final class AppActions {
    /// 메뉴바 "FCPXML 가져오기…" 클릭 시 true. ContentView가 감지 후 즉시 false로 리셋.
    var showImportPanel: Bool = false
}

/// Finder/Dock에서 .fcpxmld/.fcpxml 파일을 열 때 NSApplicationDelegate 콜백을 받아 Notification으로 전달.
@MainActor
final class SilenciAppDelegate: NSObject, NSApplicationDelegate {
    nonisolated func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                let ext = url.pathExtension.lowercased()
                if ext == "fcpxmld" || ext == "fcpxml" {
                    NotificationCenter.default.post(name: .openFCPXMLFile, object: url)
                    return
                }
            }
        }
    }
}
