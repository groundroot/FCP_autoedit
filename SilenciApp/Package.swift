// swift-tools-version: 6.0

import PackageDescription

let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let cltLibs       = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let cltPlugin     = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"

let package = Package(
    name: "SilenciApp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Library: all logic — importable by tests
        .target(
            name: "SilenciCore",
            path: "Sources",
            exclude: ["Resources"],
            swiftSettings: [
                // Allow @testable import SilenciCore from test driver
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug)),
            ]
        ),
        // Executable: entry point only
        .executableTarget(
            name: "SilenciApp",
            dependencies: ["SilenciCore"],
            path: "AppEntry"
        ),
        // Test driver executable — bypasses swift test CLT limitation.
        // Run with: swift run SilenciTestDriver
        .executableTarget(
            name: "SilenciTestDriver",
            dependencies: ["SilenciCore"],
            path: "TestDriver",
            swiftSettings: [
                .unsafeFlags([
                    "-F", cltFrameworks,
                    "-load-plugin-library", cltPlugin,
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", cltFrameworks,
                    "-framework", "Testing",
                    "-L", cltLibs,
                    "-Xlinker", "-rpath", "-Xlinker", cltFrameworks,
                    "-Xlinker", "-rpath", "-Xlinker", cltLibs,
                ]),
            ]
        ),
    ]
)
