import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var pythonEnv: PythonEnvironment
    var appActions: AppActions
    @State private var bridge = PythonBridge()
    @State private var videoModel = VideoPlayerModel()
    @State private var analysisService = AnalysisService()
    @State private var settings = AnalysisSettings()
    @State private var isPro: Bool = false
    @State private var bridgeStatus: String = ""
    @State private var isTesting = false
    @State private var showFindReplace = false
    @State private var showSettings = false
    @State private var showAnalyzeDialog = false
    @State private var retranscribeItem: RetranscribeItem?
    @State private var retranscribeState: RetranscribeState = .idle
    @State private var isDroppingFCPXML = false

    struct RetranscribeItem: Identifiable {
        let id = UUID()
        let inputURL: URL
        let defaultOutputURL: URL
    }

    enum RetranscribeState {
        case idle
        case running
        case done(outputPath: String)
        case error(String)
    }

    var body: some View {
        ZStack {
            mainContent
                .disabled(!pythonEnv.state.isReady)
                .opacity(pythonEnv.state.isReady ? 1 : 0.3)

            if !pythonEnv.state.isReady {
                setupOverlay
            }

            // 드래그앤드롭 오버레이 — FCPXMLD 파일을 창 위로 드래그할 때 표시
            if isDroppingFCPXML {
                ZStack {
                    Color.black.opacity(0.55)
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.cyan, lineWidth: 3)
                        .padding(24)
                    VStack(spacing: 14) {
                        Image(systemName: "doc.badge.arrow.up")
                            .font(.system(size: 52))
                            .foregroundStyle(.cyan)
                        Text(L10n.tr("preview.fcpxml_drop"))
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text(".fcpxmld  /  .fcpxml")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        // ① 드래그앤드롭 — Finder나 다른 앱에서 창으로 파일을 드래그
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: {
                ["fcpxmld", "fcpxml"].contains($0.pathExtension.lowercased())
            }) else { return false }
            handleImportedURL(url)
            return true
        } isTargeted: { targeted in
            isDroppingFCPXML = targeted
        }
        // ② 메뉴바 "FCPXML 가져오기…" → AppActions.showImportPanel
        .onChange(of: appActions.showImportPanel) { _, show in
            if show {
                appActions.showImportPanel = false
                importFCPXML()
            }
        }
        // ③ Dock 아이콘/Finder 연결 파일 열기 → SilenciAppDelegate → Notification
        .onReceive(NotificationCenter.default.publisher(for: .openFCPXMLFile)) { note in
            guard let url = note.object as? URL else { return }
            handleImportedURL(url)
        }
        .sheet(item: $retranscribeItem) { item in
            RetranscribeSheetView(
                inputURL: item.inputURL,
                defaultOutputURL: item.defaultOutputURL,
                settings: settings,
                state: $retranscribeState,
                analysisService: analysisService,
                pythonEnv: pythonEnv,
                onDismiss: { retranscribeItem = nil }
            )
        }
    }

    // MARK: - Setup Overlay

    @ViewBuilder
    private var setupOverlay: some View {
        VStack(spacing: 20) {
            switch pythonEnv.state {
            case .notStarted, .checking:
                ProgressView()
                    .scaleEffect(1.5)
                Text(L10n.tr("setup.checking"))
                    .font(.headline)

            case .installing(let detail):
                VStack(spacing: 12) {
                    Text(L10n.tr("setup.installing_title"))
                        .font(.title2.bold())
                    Text(L10n.tr("setup.installing_subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ProgressView(value: pythonEnv.progress)
                        .frame(width: 300)

                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text(L10n.tr("setup.failed_title"))
                        .font(.title2.bold())
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)

                    Button(L10n.tr("setup.retry")) {
                        Task { await pythonEnv.retry() }
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .ready:
                EmptyView()
            }
        }
        .padding(40)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 0) {
            topToolbarView
            Divider()
            HSplitView {
                textEditorPanel
                    .frame(minWidth: 360)
                videoPanel
                    .frame(minWidth: 260, idealWidth: 380, maxWidth: 520)
            }
            if showFindReplace {
                Divider()
                FindReplaceView(analysisService: analysisService, isVisible: $showFindReplace)
            }
        }
        .background {
            Button("") { showFindReplace.toggle() }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings, isPresented: $showSettings)
        }
        .sheet(isPresented: $showAnalyzeDialog) {
            AnalyzeDialogView(settings: settings, isPresented: $showAnalyzeDialog) {
                guard let url = videoModel.videoURL else { return }
                settings.save()
                analysisService.startAnalysis(videoURL: url, environment: pythonEnv, settings: settings)
            }
        }
        .onAppear { settings.load() }
    }

    // MARK: - Top Toolbar

    private var topToolbarView: some View {
        HStack(spacing: 10) {
            // Brand
            HStack(spacing: 6) {
                Image(systemName: "scissors")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.cyan)
                Text("TEXT BASED EDIT")
                    .font(.system(.headline, design: .rounded, weight: .black))
                Text(isPro ? "PRO" : "FREE")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        isPro ? Color.cyan.opacity(0.8) : Color.orange.opacity(0.85),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }

            Divider().frame(height: 22).padding(.horizontal, 2)

            // Open video
            Button {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .audio, .mp3, .mpeg4Audio, .wav, .aiff]
                panel.allowsMultipleSelection = false
                panel.begin { response in
                    if response == .OK, let url = panel.url {
                        videoModel.loadVideo(url: url)
                        showAnalyzeDialog = true
                    }
                }
            } label: {
                Label(L10n.tr("toolbar.open"), systemImage: "folder")
            }

            // Analyze
            Button { showAnalyzeDialog = true } label: {
                Label(L10n.tr("toolbar.analyze"), systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(videoModel.videoURL == nil || analysisService.isAnalyzing)

            // Import FCPXML (resub)
            Button { importFCPXML() } label: {
                Label(L10n.tr("toolbar.import_fcpxml"), systemImage: "doc.badge.arrow.up")
            }
            .disabled(analysisService.isAnalyzing)

            Spacer()

            if !analysisService.segments.isEmpty {
                Button { showFindReplace.toggle() } label: {
                    Label(L10n.tr("toolbar.find"), systemImage: "magnifyingglass")
                }

                Menu {
                    ForEach(ExportFormat.allCases) { format in
                        Button(format.displayName) { exportFile(format: format) }
                    }
                } label: {
                    Label(L10n.tr("toolbar.export"), systemImage: "square.and.arrow.up")
                }
            }

            Button { showSettings.toggle() } label: {
                Label(L10n.tr("toolbar.settings"), systemImage: "gearshape")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    // MARK: - Text Editor Panel (left)

    private var textEditorPanel: some View {
        Group {
            if analysisService.isAnalyzing {
                AnalysisProgressView(progress: analysisService.progress) {
                    analysisService.cancelAnalysis()
                }
            } else if !analysisService.segments.isEmpty {
                TextBasedEditorView(
                    analysisService: analysisService,
                    currentTime: videoModel.currentTime,
                    onSeek: { videoModel.seek(to: $0) }
                )
            } else {
                editorEmptyState
            }
        }
        .overlay(alignment: .bottom) {
            if let err = analysisService.error {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(err).lineLimit(2)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(8)
            }
        }
    }

    private var editorEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.cursor")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.3))
            Text(L10n.tr("editor.empty_title"))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(L10n.tr("editor.empty_subtitle"))
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Video Panel (right)

    private var videoPanel: some View {
        VStack(spacing: 0) {
            VideoPreviewView(model: videoModel, onFCPXMLDrop: handleImportedURL)
                .frame(maxHeight: .infinity)
            Divider()
            TimelineBarWrapper(
                segments: analysisService.segments,
                videoModel: videoModel,
                timelineDuration: analysisService.timelineDuration,
                onSeek: { videoModel.seek(to: $0) }
            )
            .frame(height: 56)
        }
    }

    // MARK: - Import FCPXML (Retranscribe to file)

    /// ① Import 버튼 — NSOpenPanel을 열어 파일 선택 후 handleImportedURL로 넘김.
    private func importFCPXML() {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true   // .fcpxmld is a directory bundle
        openPanel.canChooseFiles = true
        openPanel.treatsFilePackagesAsDirectories = false
        openPanel.message = L10n.tr("toolbar.import_fcpxml_message")
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "fcpxmld") ?? .directory,
            UTType(filenameExtension: "fcpxml") ?? .xml,
        ]

        let response = openPanel.runModal()
        guard response == .OK, let url = openPanel.url else { return }
        handleImportedURL(url)
    }

    /// 드래그앤드롭 / Dock 열기 / 메뉴바 선택 결과 URL을 공통 처리.
    private func handleImportedURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "fcpxmld" || ext == "fcpxml" || ext == "xml" else {
            print("[Silenci] Unsupported file: \(url.lastPathComponent)")
            return
        }

        // .fcpxmld 번들 → 내부 Info.fcpxml 경로로 resolve
        let resolvedURL: URL
        if ext == "fcpxmld" {
            resolvedURL = url.appendingPathComponent("Info.fcpxml")
            guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
                print("[Silenci] Error: Info.fcpxml not found inside .fcpxmld bundle")
                return
            }
        } else {
            resolvedURL = url
        }

        retranscribeState = .idle
        let dir = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let outURL = dir.appendingPathComponent(baseName + "_resub.fcpxml")
        retranscribeItem = RetranscribeItem(inputURL: resolvedURL, defaultOutputURL: outURL)
    }

    /// Parse FCPXML to find the source video file path.
    private static func findVideoInFCPXML(_ fcpxmlURL: URL) -> URL? {
        guard let data = try? Data(contentsOf: fcpxmlURL),
              let xmlString = String(data: data, encoding: .utf8) else { return nil }

        // Find file:// URL in media-rep src attribute
        if let range = xmlString.range(of: #"file://[^"]*\.(mov|mp4|m4v|avi|mkv|MOV|MP4)"#, options: .regularExpression) {
            let urlString = String(xmlString[range])
            // URL decode percent-encoded paths (e.g. Korean filenames)
            if let decoded = urlString.removingPercentEncoding,
               let _ = URL(string: decoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString) {
                let path = decoded.replacingOccurrences(of: "file://", with: "")
                if FileManager.default.fileExists(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
            // Fallback: try direct URL construction
            if let url = URL(string: urlString), FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    // MARK: - Export

    private func exportFile(format: ExportFormat) {
        let panel = NSSavePanel()

        switch format {
        case .srt:
            panel.allowedContentTypes = []
        case .fcpxml:
            panel.allowedContentTypes = []
        case .itt:
            panel.allowedContentTypes = []
        }

        let baseName: String
        if let videoURL = videoModel.videoURL {
            baseName = videoURL.deletingPathExtension().lastPathComponent
        } else {
            baseName = "export"
        }
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
        panel.allowsOtherFileTypes = true

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let content: String
            switch format {
            case .srt:
                content = ExportService.generateSRT(segments: analysisService.segments, maxSubtitleChars: settings.maxSubtitleChars)
            case .fcpxml:
                let info = analysisService.videoInfo ?? VideoInfo(
                    fps: 30,
                    width: 1920,
                    height: 1080,
                    duration: 0
                )
                content = ExportService.generateFCPXML(
                    segments: analysisService.segments,
                    videoInfo: info,
                    videoURL: videoModel.videoURL ?? URL(fileURLWithPath: "/unknown"),
                    fontSize: settings.fontSizeExport,
                    maxSubtitleChars: settings.maxSubtitleChars
                )
            case .itt:
                content = ExportService.generateITT(segments: analysisService.segments, fps: analysisService.videoInfo?.fps ?? 24.0, maxSubtitleChars: settings.maxSubtitleChars)
            }

            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("[ExportService] Failed to write \(format.fileExtension): \(error)")
            }
        }
    }

    // MARK: - Bridge test

    private func findProjectRoot() -> String {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: fm.currentDirectoryPath)
        for _ in 0..<5 {
            if fm.fileExists(atPath: dir.appendingPathComponent("silence_cutter").path) {
                return dir.path
            }
            dir = dir.deletingLastPathComponent()
        }
        return fm.currentDirectoryPath
    }

    private func testBridge() async {
        isTesting = true
        bridgeStatus = "Starting Python process…"

        bridge.projectRoot = findProjectRoot()

        do {
            try bridge.start()
            bridgeStatus = "Sending ping…"

            let result = try await bridge.call("ping", timeout: 10)
            if case .string(let value) = result, value == "pong" {
                bridgeStatus = "✅ ping → pong round-trip OK"
            } else {
                bridgeStatus = "⚠️ Unexpected response: \(result)"
            }

            bridge.stop()
        } catch {
            bridgeStatus = "❌ Error: \(error)"
            bridge.stop()
        }

        isTesting = false
    }
}

