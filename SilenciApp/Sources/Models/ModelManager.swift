import Foundation

/// Manages available MLX ASR models — download state, availability check, and on-demand download.
/// Models are stored in the HuggingFace cache (~/.cache/huggingface/hub/).
@MainActor
@Observable
final class ModelManager {

    // MARK: - Model catalog (add new models here for future app updates)

    struct MLXModel: Identifiable {
        let id: String
        let huggingFaceId: String
        let displayName: String
        let description: String
        let approxSizeMB: Int
        var isDownloaded: Bool = false
        var downloadProgress: Double? = nil  // nil = not downloading, 0.0-1.0 = in progress
        var downloadError: String? = nil
    }

    private(set) var models: [MLXModel] = [
        MLXModel(
            id: "small",
            huggingFaceId: "mlx-community/Qwen3-ASR-0.6B-8bit",
            displayName: "Qwen3-ASR 0.6B",
            description: "빠른 인식 / Fast",
            approxSizeMB: 500
        ),
        MLXModel(
            id: "large",
            huggingFaceId: "mlx-community/Qwen3-ASR-1.7B-8bit",
            displayName: "Qwen3-ASR 1.7B",
            description: "고품질 인식 / High Quality",
            approxSizeMB: 1500
        ),
    ]

    // MARK: - HuggingFace cache

    private let hfCacheDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hfHome = ProcessInfo.processInfo.environment["HF_HOME"]
        if let hfHome {
            return URL(fileURLWithPath: hfHome)
        }
        return home.appendingPathComponent(".cache/huggingface/hub")
    }()

    // MARK: - Availability (Swift-native, no bridge required)

    /// Check which models are locally cached. Runs synchronously — safe to call at startup.
    func refreshAvailability() {
        let fm = FileManager.default
        for i in models.indices {
            let folderName = "models--" + models[i].huggingFaceId.replacingOccurrences(of: "/", with: "--")
            let snapshotsURL = hfCacheDir.appendingPathComponent(folderName).appendingPathComponent("snapshots")
            let available = fm.fileExists(atPath: snapshotsURL.path) &&
                ((try? fm.contentsOfDirectory(atPath: snapshotsURL.path))?.isEmpty == false)
            models[i].isDownloaded = available
        }
    }

    // MARK: - Download (requires PythonEnvironment to be ready)

    func downloadModel(id: String, environment: PythonEnvironment) async {
        guard let idx = models.firstIndex(where: { $0.id == id }) else { return }
        guard models[idx].downloadProgress == nil else { return }  // already in progress

        models[idx].downloadProgress = 0.0
        models[idx].downloadError = nil

        let hfId = models[idx].huggingFaceId

        let bridge = PythonBridge()
        if case .ready(let pythonPath, let modulePath) = environment.state {
            bridge.pythonPath = pythonPath
            bridge.projectRoot = modulePath
        }

        do {
            try bridge.start()

            // Progress poll timer
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let i = self.models.firstIndex(where: { $0.id == id }) else { return }
                    if let p = bridge.currentProgress {
                        let pct = p.percent >= 0 ? Double(p.percent) / 100.0 : self.models[i].downloadProgress ?? 0
                        self.models[i].downloadProgress = pct
                    }
                }
            }

            let response = try await bridge.call(
                "download_model",
                params: ["model_id": .string(hfId)],
                timeout: 3600
            )

            timer.invalidate()
            bridge.stop()

            if case .object(let obj) = response, case .string(let path) = obj["path"] {
                print("[ModelManager] ✅ Model downloaded: \(path)")
            }

            models[idx].isDownloaded = true
            models[idx].downloadProgress = nil

        } catch {
            bridge.stop()
            models[idx].downloadError = error.localizedDescription
            models[idx].downloadProgress = nil
            print("[ModelManager] ❌ Download failed: \(error)")
        }
    }

    func cancelDownload(id: String) {
        guard let idx = models.firstIndex(where: { $0.id == id }) else { return }
        models[idx].downloadProgress = nil
        models[idx].downloadError = "다운로드 취소됨"
    }

    // MARK: - Helpers

    func model(for asrModel: AnalysisSettings.ASRModel) -> MLXModel? {
        models.first { $0.huggingFaceId == asrModel.rawValue }
    }

    func formattedSize(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }
}
