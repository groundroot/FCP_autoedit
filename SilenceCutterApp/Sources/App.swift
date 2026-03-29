import SwiftUI
import Foundation

/// Check if `--test-bridge` was passed on the command line.
/// When true, the app runs a headless ping round-trip and exits.
private let isTestBridgeMode = CommandLine.arguments.contains("--test-bridge")

@main
struct SilenceCutterApp: App {
    var body: some Scene {
        WindowGroup {
            if isTestBridgeMode {
                BridgeTestRunner()
            } else {
                ContentView()
            }
        }
        .defaultSize(width: 1200, height: 800)
    }
}

/// Headless view that runs the bridge ping test and exits the process.
private struct BridgeTestRunner: View {
    @State private var bridge = PythonBridge()

    var body: some View {
        Text("Running bridge test…")
            .task {
                await runBridgeTest()
            }
    }

    private func runBridgeTest() async {
        // Find the project root by walking up from cwd looking for silence_cutter/.
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        var projectRoot = dir.path
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("silence_cutter").path
            if fm.fileExists(atPath: candidate) {
                projectRoot = dir.path
                break
            }
            dir = dir.deletingLastPathComponent()
        }
        print("[test-bridge] project root: \(projectRoot)")

        bridge.projectRoot = projectRoot

        do {
            try bridge.start()
            print("[test-bridge] Python process started")

            let result = try await bridge.call("ping", timeout: 10)
            if case .string(let value) = result, value == "pong" {
                print("[test-bridge] ✅ ping → pong round-trip OK")
            } else {
                print("[test-bridge] ❌ unexpected result: \(result)")
            }

            // Test echo
            let echoResult = try await bridge.call("echo", params: ["msg": "hello"], timeout: 10)
            print("[test-bridge] ✅ echo → \(echoResult)")

            bridge.stop()
            print("[test-bridge] Python process stopped")
            exit(0)
        } catch {
            print("[test-bridge] ❌ error: \(error)")
            bridge.stop()
            exit(1)
        }
    }
}
