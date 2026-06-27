import Foundation

/// Manages the local Python runtime used by the analysis bridge.
///
/// Direct builds keep the legacy standalone installer path.
/// APPSTORE builds never install system tools or Python packages at runtime; they only
/// use a runtime already bundled inside the app.
@MainActor
@Observable
final class PythonEnvironment {

    // MARK: - State

    enum SetupState: Equatable, Sendable {
        case notStarted
        case checking
        case installing(detail: String)
        case ready(pythonPath: String, modulePath: String)
        case failed(message: String)

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    private(set) var state: SetupState = .notStarted

    /// Overall progress 0.0 – 1.0 during installation.
    private(set) var progress: Double = 0.0

    // MARK: - Constants

    /// Version stamp — bump this when dependencies change to force reinstall.
    private static let envVersion = "6"

    #if !APPSTORE
    /// pip packages required for the server mode.
    private static let serverDependencies: [String] = [
        "numpy<2",
        "soundfile>=0.12.0",
        "faster-whisper>=1.0.0",
        "torch>=2.0.0",
        "torchaudio",
        "silero-vad>=5.1.2",
        "mlx>=0.22.0",
        "mlx-audio>=0.3.0",
        "webrtcvad",
        "scipy",
        "scikit-learn",
        "soynlp",
    ]
    #endif

    // MARK: - Paths

    /// App support directory. In a sandboxed build this resolves inside the app container.
    private var supportDir: URL {
        AppPaths.appSupportDir
    }

    /// ~/Library/Application Support/Silenci/venv/
    private var venvDir: URL {
        supportDir.appendingPathComponent("venv")
    }

    /// ~/Library/Application Support/Silenci/venv/bin/python
    private var venvPython: URL {
        venvDir.appendingPathComponent("bin/python")
    }

    /// Version stamp file inside the venv.
    private var versionFile: URL {
        venvDir.appendingPathComponent(".sc-version")
    }

    /// Path to the bundled `silence_cutter` module.
    private var modulePath: String {
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = (resourcePath as NSString).appendingPathComponent("silence_cutter")
            if FileManager.default.fileExists(atPath: bundled) {
                return resourcePath
            }
        }
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("silence_cutter").path
            if fm.fileExists(atPath: candidate) {
                return dir.path
            }
            dir = dir.deletingLastPathComponent()
        }
        return FileManager.default.currentDirectoryPath
    }

    // MARK: - Setup

    func ensureReady() async {
        guard case .notStarted = state else { return }
        state = .checking
        progress = 0.0

        do {
            AppPaths.createRuntimeDirectoriesIfNeeded()

            #if APPSTORE
            let pythonPath = try prepareBundledRuntime()
            #else
            // Step 1: Ensure system prerequisites (Homebrew, Python3, ffmpeg)
            try await ensurePrerequisites()

            // Step 2: Setup Python venv + install packages
            let pythonPath = try await setupVenv()
            #endif

            let modPath = modulePath
            state = .ready(pythonPath: pythonPath, modulePath: modPath)
            progress = 1.0
            print("[PythonEnvironment] ✅ Ready — python: \(pythonPath), module: \(modPath)")
        } catch {
            state = .failed(message: error.localizedDescription)
            print("[PythonEnvironment] ❌ Setup failed: \(error)")
        }
    }

    func retry() async {
        state = .notStarted
        await ensureReady()
    }

    private func prepareBundledRuntime() throws -> String {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw PythonEnvError.runtimeMissing
        }

        let runtimeURL = resourceURL.appendingPathComponent("JaMakRuntime", isDirectory: true)
        let pythonCandidates = [
            runtimeURL.appendingPathComponent("bin/python3"),
            runtimeURL.appendingPathComponent("bin/python"),
        ]

        guard let python = pythonCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw PythonEnvError.runtimeMissing
        }

        let moduleURL = resourceURL.appendingPathComponent("silence_cutter", isDirectory: true)
        guard FileManager.default.fileExists(atPath: moduleURL.path) else {
            throw PythonEnvError.runtimeMissing
        }

        return python.path
    }

    // MARK: - Prerequisites (Homebrew, Python3, ffmpeg)

    #if !APPSTORE
    /// Check and auto-install missing system dependencies.
    private func ensurePrerequisites() async throws {
        // 1. Homebrew
        if !isCommandAvailable("/opt/homebrew/bin/brew") && !isCommandAvailable("/usr/local/bin/brew") {
            state = .installing(detail: "Installing Homebrew…")
            progress = 0.02
            print("[PythonEnvironment] Homebrew not found — installing…")
            try await runShell("""
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            """)
            // Add Homebrew to PATH for this session
            if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
                print("[PythonEnvironment] ✅ Homebrew installed at /opt/homebrew/bin/brew")
            }
        }

        let brewPath = findBrew()

        // 2. Python3 (need 3.10+ for mlx-audio)
        if let pythonPath = findSystemPython() {
            // Check version — mlx-audio requires 3.10+
            let versionOk = await checkPythonVersion(pythonPath, minMajor: 3, minMinor: 10)
            if !versionOk {
                state = .installing(detail: "Upgrading Python3 (3.10+ required)…")
                progress = 0.04
                print("[PythonEnvironment] Python found but too old — upgrading via Homebrew…")
                try await run(brewPath, arguments: ["install", "python@3"])
            }
        } else {
            state = .installing(detail: "Installing Python3…")
            progress = 0.04
            print("[PythonEnvironment] Python3 not found — installing via Homebrew…")
            try await run(brewPath, arguments: ["install", "python@3"])
        }

        // Verify Python3 is now available
        guard findSystemPython() != nil else {
            throw PythonEnvError.pythonNotFound
        }

        // 3. ffmpeg
        if !isCommandAvailable("/opt/homebrew/bin/ffmpeg") && !isCommandAvailable("/usr/local/bin/ffmpeg") {
            state = .installing(detail: "Installing ffmpeg…")
            progress = 0.06
            print("[PythonEnvironment] ffmpeg not found — installing via Homebrew…")
            try await run(brewPath, arguments: ["install", "ffmpeg"])
        }

        print("[PythonEnvironment] ✅ All prerequisites satisfied")
    }

    /// Check if a command exists at the given path.
    private func isCommandAvailable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// Check Python version meets minimum requirement.
    private func checkPythonVersion(_ pythonPath: String, minMajor: Int, minMinor: Int) async -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-c", "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            return await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let parts = output.split(separator: ".").compactMap { Int($0) }
                    if parts.count >= 2 {
                        let ok = parts[0] > minMajor || (parts[0] == minMajor && parts[1] >= minMinor)
                        print("[PythonEnvironment] Python version: \(output) (need \(minMajor).\(minMinor)+) → \(ok ? "OK" : "too old")")
                        continuation.resume(returning: ok)
                    } else {
                        continuation.resume(returning: false)
                    }
                }
            }
        } catch {
            return false
        }
    }

    /// Find Homebrew binary.
    private func findBrew() -> String {
        if isCommandAvailable("/opt/homebrew/bin/brew") { return "/opt/homebrew/bin/brew" }
        if isCommandAvailable("/usr/local/bin/brew") { return "/usr/local/bin/brew" }
        return "brew"
    }
    #endif

    // MARK: - Cleanup

    var installedSize: Int64 {
        guard FileManager.default.fileExists(atPath: venvDir.path) else { return 0 }
        return Self.directorySize(url: venvDir)
    }

    var installedSizeString: String {
        let bytes = installedSize
        guard bytes > 0 else { return "Not installed" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: venvPython.path)
    }

    func removeEnvironment() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: supportDir.path) {
            try fm.removeItem(at: supportDir)
        }
        state = .notStarted
        progress = 0.0
        print("[PythonEnvironment] 🗑️ Environment removed: \(supportDir.path)")
    }

    var supportDirPath: String {
        supportDir.path
    }

    private static func directorySize(url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Venv Setup

    #if !APPSTORE
    private func setupVenv() async throws -> String {
        let fm = FileManager.default

        try fm.createDirectory(at: supportDir, withIntermediateDirectories: true)

        // Check if venv already exists with correct version
        if fm.fileExists(atPath: venvPython.path),
           let stamp = try? String(contentsOf: versionFile, encoding: .utf8),
           stamp.trimmingCharacters(in: .whitespacesAndNewlines) == Self.envVersion {
            print("[PythonEnvironment] Existing venv is up-to-date (v\(Self.envVersion))")
            progress = 1.0
            return venvPython.path
        }

        guard let systemPython = findSystemPython() else {
            throw PythonEnvError.pythonNotFound
        }
        print("[PythonEnvironment] Using system Python: \(systemPython)")

        // Create venv (or recreate if version mismatch)
        if fm.fileExists(atPath: venvDir.path) {
            state = .installing(detail: "Cleaning up existing environment…")
            try fm.removeItem(at: venvDir)
        }

        state = .installing(detail: "Creating Python virtual environment…")
        progress = 0.10
        try await run(systemPython, arguments: ["-m", "venv", venvDir.path])

        // Upgrade pip first — old pip versions can't find newer packages
        let pipPath = venvDir.appendingPathComponent("bin/pip").path
        state = .installing(detail: "Upgrading pip…")
        progress = 0.12
        try await run(pipPath, arguments: ["install", "--upgrade", "pip"])

        // Install dependencies
        let totalDeps = Self.serverDependencies.count

        for (index, dep) in Self.serverDependencies.enumerated() {
            let pct = Double(index) / Double(totalDeps)
            progress = 0.15 + pct * 0.80
            state = .installing(detail: "\(dep) 설치 중… (\(index + 1)/\(totalDeps))")
            print("[PythonEnvironment] Installing \(dep) (\(index + 1)/\(totalDeps))")
            try await run(pipPath, arguments: ["install", dep])
        }

        // Write version stamp
        progress = 0.98
        state = .installing(detail: "Finishing environment setup…")
        try Self.envVersion.write(to: versionFile, atomically: true, encoding: .utf8)

        return venvPython.path
    }

    /// Find a usable system python3 — prefers Homebrew, then Xcode CLT, then PATH.
    /// Returns nil if not found.
    private func findSystemPython() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Run a subprocess and wait for it to complete. Throws on non-zero exit.
    private func run(_ executable: String, arguments: [String]) async throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments

        // Ensure Homebrew paths are in PATH
        var env = ProcessInfo.processInfo.environment
        let brewPaths = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = brewPaths + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env

        let stderrPipe = Pipe()
        let stdoutPipe = Pipe()
        proc.standardError = stderrPipe
        proc.standardOutput = stdoutPipe

        try proc.run()

        let (status, errorOutput) = await withCheckedContinuation { (continuation: CheckedContinuation<(Int32, String), Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                proc.waitUntilExit()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMsg = String(data: errorData, encoding: .utf8) ?? ""
                continuation.resume(returning: (proc.terminationStatus, errorMsg))
            }
        }

        if status != 0 {
            throw PythonEnvError.commandFailed(
                command: "\(executable) \(arguments.joined(separator: " "))",
                message: errorOutput
            )
        }
    }

    /// Run a shell command string via /bin/bash.
    private func runShell(_ command: String) async throws {
        try await run("/bin/bash", arguments: ["-c", command])
    }
    #endif
}

// MARK: - Errors

enum PythonEnvError: Error, LocalizedError {
    case commandFailed(command: String, message: String)
    case pythonNotFound
    case runtimeMissing

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let msg):
            "Command failed: \(cmd)\n\(msg)"
        case .pythonNotFound:
            "Python 3 not found. Please install Python 3.10+ first."
        case .runtimeMissing:
            "JaMak runtime is not bundled in this build. Reinstall JaMak or install the App Store runtime package."
        }
    }
}
