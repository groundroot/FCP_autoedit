import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var pythonEnv: PythonEnvironment
    var appActions: AppActions
    var proManager: ProManager
    var storeService: StoreService
    var modelManager: ModelManager
    @State private var bridge = PythonBridge()
    @State private var videoModel = VideoPlayerModel()
    @State private var analysisService = AnalysisService()
    @State private var settings = AnalysisSettings()
    @State private var showUpgradeAlert = false
    @State private var pendingExportFormat: ExportFormat?
    @State private var showModelManager = false
    @State private var mp4RenderState: MP4RenderState = .idle

    enum MP4RenderState: Equatable {
        case idle
        case rendering(progress: String)
        case done(path: String)
        case error(String)
    }
    @State private var bridgeStatus: String = ""
    @State private var isTesting = false
    @State private var showFindReplace = false
    @State private var showSettings = false
    @State private var showAnalyzeDialog = false
    @State private var retranscribeItem: RetranscribeItem?
    @State private var retranscribeState: RetranscribeState = .idle
    @State private var isDroppingFCPXML = false
    @State private var speakerNames: [Int: String] = [:]
    @State private var hiddenSpeakers: Set<Int> = []

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
        .toolbar {
            // ── 왼쪽: 브랜드 + 핵심 액션 ──────────────────────────
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 6) {
                    Image(systemName: "scissors")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.cyan)
                    Text(AppConfig.appName)
                        .font(.system(.subheadline, design: .rounded, weight: .black))
                    if AppConfig.showsProFeatures {
                        Text(proManager.isPro ? L10n.tr("pro.pro_badge") : L10n.tr("pro.free_badge"))
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                proManager.isPro ? Color.cyan.opacity(0.8) : Color.orange.opacity(0.85),
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                    }
                }
            }
            ToolbarItem(placement: .navigation) {
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
            }
            ToolbarItem(placement: .navigation) {
                Button { showAnalyzeDialog = true } label: {
                    Label(L10n.tr("toolbar.analyze"), systemImage: "waveform.badge.magnifyingglass")
                }
                .disabled(videoModel.videoURL == nil || analysisService.isAnalyzing)
            }
            ToolbarItem(placement: .navigation) {
                Button { importFCPXML() } label: {
                    Label(L10n.tr("toolbar.import_fcpxml"), systemImage: "doc.badge.arrow.up")
                }
                .disabled(analysisService.isAnalyzing)
            }

            // ── 오른쪽: 세그먼트 있을 때 조건부 ──────────────────
            if !analysisService.segments.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button { showFindReplace.toggle() } label: {
                        Label(L10n.tr("toolbar.find"), systemImage: "magnifyingglass")
                    }
                    .keyboardShortcut("f", modifiers: .command)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(AppConfig.enabledExportFormats) { format in
                            Button(format.displayName) { exportFile(format: format) }
                        }
                    } label: {
                        Label(L10n.tr("toolbar.export"), systemImage: "square.and.arrow.up")
                    }
                }
                if AppConfig.showsProFeatures,
                   !proManager.isPro,
                   ProManager.keptDuration(analysisService.segments) > ProManager.freeLimitSeconds {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showUpgradeAlert = true } label: {
                            Label(L10n.tr("pro.upgrade_button"), systemImage: "star.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            // ── 오른쪽: 항상 표시 ──────────────────────────────────
            if AppConfig.allowsModelDownload {
                ToolbarItem(placement: .primaryAction) {
                    Button { showModelManager = true } label: {
                        Label(L10n.tr("model.manage"), systemImage: "cpu")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showSettings.toggle() } label: {
                    Label(L10n.tr("toolbar.settings"), systemImage: "gearshape")
                }
            }
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
            HSplitView {
                textEditorPanel
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
                videoPanel
                    .frame(minWidth: 520, idealWidth: 900, maxWidth: .infinity)
            }
            if showFindReplace {
                Divider()
                FindReplaceView(analysisService: analysisService, isVisible: $showFindReplace)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                settings: settings,
                proManager: proManager,
                storeService: storeService,
                modelManager: modelManager,
                pythonEnv: pythonEnv,
                isPresented: $showSettings
            )
        }
        .sheet(isPresented: $showAnalyzeDialog) {
            AnalyzeDialogView(settings: settings, isPresented: $showAnalyzeDialog) {
                guard let url = videoModel.videoURL else { return }
                settings.save()
                analysisService.startAnalysis(videoURL: url, environment: pythonEnv, settings: settings)
            }
        }
        .alert(L10n.tr("pro.upgrade_title"), isPresented: $showUpgradeAlert) {
            Button(storeService.isPurchasing
                   ? L10n.tr("store.purchasing")
                   : L10n.tr("store.buy", storeService.proPrice),
                   role: .none) {
                Task { await storeService.purchase(proManager: proManager) }
            }
            .disabled(storeService.isPurchasing)

            Button(L10n.tr("pro.export_anyway"), role: .none) {
                if let fmt = pendingExportFormat {
                    performExport(format: fmt, clamp: true)
                    pendingExportFormat = nil
                }
            }
            Button(L10n.tr("pro.cancel"), role: .cancel) {
                pendingExportFormat = nil
            }
        } message: {
            Text(L10n.tr("pro.upgrade_body"))
        }
        .sheet(isPresented: $showModelManager) {
            ModelDownloadView(
                modelManager: modelManager,
                pythonEnv: pythonEnv,
                isPresented: $showModelManager
            )
        }
        .onAppear { settings.load() }
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
                    onSeek: { videoModel.seek(to: $0) },
                    speakerNames: speakerNames,
                    hiddenSpeakers: hiddenSpeakers
                )
            } else {
                editorEmptyState
            }
        }
        .overlay(alignment: .top) {
            let keptDur = ProManager.keptDuration(analysisService.segments)
            if AppConfig.showsProFeatures,
               !proManager.isPro,
               !analysisService.segments.isEmpty,
               keptDur > ProManager.freeLimitSeconds {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                    Text(L10n.tr("pro.limit_banner"))
                        .font(.caption2.weight(.medium))
                    Spacer()
                    Button(L10n.tr("pro.upgrade_button")) {
                        showUpgradeAlert = true
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.orange.opacity(0.85))
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 4) {
                if let err = analysisService.error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text(err).lineLimit(2)
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
                switch mp4RenderState {
                case .idle:
                    EmptyView()
                case .rendering(let msg):
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text(msg).font(.caption).lineLimit(1)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                case .done(let path):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(URL(fileURLWithPath: path).lastPathComponent).font(.caption).lineLimit(1)
                        Button("Finder") { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.cyan)
                        Button { mp4RenderState = .idle } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                case .error(let msg):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(msg).font(.caption).lineLimit(2)
                        Button { mp4RenderState = .idle } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(8)
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

    private var currentSubtitleText: String? {
        guard videoModel.player != nil else { return nil }
        let t = videoModel.currentTime
        return analysisService.segments.first { $0.isKept && t >= $0.start && t < $0.end }?.text
    }

    private var videoPanel: some View {
        VStack(spacing: 0) {
            VideoPreviewView(
                model: videoModel,
                onFCPXMLDrop: handleImportedURL,
                subtitle: currentSubtitleText
            )
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 10) {
                Toggle(isOn: $videoModel.skipDiscardedSegments) {
                    Label("편집 미리보기", systemImage: "scissors.badge.ellipsis")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .help("재생 중 삭제된 구간을 자동으로 건너뜀")
                .disabled(analysisService.segments.isEmpty)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
            if !activeSpeakerIds.isEmpty {
                Divider()
                speakerPanel
            }
            Divider()
            TimelineBarWrapper(
                segments: analysisService.segments,
                videoModel: videoModel,
                timelineDuration: analysisService.timelineDuration,
                onSeek: { videoModel.seek(to: $0) }
            )
            .frame(height: 68)
        }
        .onChange(of: analysisService.segments.map(\.id)) { _, _ in
            videoModel.segments = analysisService.segments
            for id in activeSpeakerIds where speakerNames[id] == nil {
                speakerNames[id] = "화자\(id + 1)"
            }
        }
    }

    private var activeSpeakerIds: [Int] {
        Array(Set(analysisService.segments.compactMap(\.speakerId))).sorted()
    }

    private var speakerPanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeSpeakerIds, id: \.self) { spkId in
                    let name = speakerNames[spkId] ?? "화자\(spkId + 1)"
                    let isHidden = hiddenSpeakers.contains(spkId)
                    let color = TextBasedEditorView.speakerColor(spkId)
                    Button {
                        if isHidden { hiddenSpeakers.remove(spkId) }
                        else { hiddenSpeakers.insert(spkId) }
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(name).font(.caption.weight(.medium))
                            Image(systemName: isHidden ? "eye.slash" : "eye")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            isHidden
                                ? Color.secondary.opacity(0.15)
                                : color.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .foregroundStyle(isHidden ? .secondary : color)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
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
        let keptDur = ProManager.keptDuration(analysisService.segments)
        if AppConfig.showsProFeatures, !proManager.isPro && keptDur > ProManager.freeLimitSeconds {
            pendingExportFormat = format
            showUpgradeAlert = true
        } else {
            performExport(format: format, clamp: false)
        }
    }

    private func performExport(format: ExportFormat, clamp: Bool) {
        let rawSegments: [Segment]
        if clamp {
            rawSegments = proManager.clampedSegments(analysisService.segments).segments
        } else {
            rawSegments = analysisService.segments
        }
        // hidden speaker 세그먼트는 내보내기에서 제외
        let exportSegments: [Segment] = rawSegments.map { seg in
            guard let spk = seg.speakerId, hiddenSpeakers.contains(spk) else { return seg }
            var s = seg; s.isKept = false; return s
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true

        let baseName = videoModel.videoURL?.deletingPathExtension().lastPathComponent ?? "export"
        panel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            if format == .mp4 {
                guard let videoURL = videoModel.videoURL else { return }
                mp4RenderState = .rendering(progress: "렌더링 준비 중…")
                Task {
                    do {
                        let result = try await analysisService.renderMP4(
                            videoURL: videoURL,
                            outputURL: url,
                            segments: exportSegments,
                            environment: pythonEnv
                        )
                        mp4RenderState = .done(path: result.outputPath)
                    } catch {
                        mp4RenderState = .error(error.localizedDescription)
                    }
                }
                return
            }

            let content: String
            switch format {
            case .mp4:
                return // handled above
            case .srt:
                content = ExportService.generateSRT(
                    segments: exportSegments,
                    maxSubtitleChars: settings.maxSubtitleChars,
                    subtitleLines: settings.subtitleLines
                )
            case .fcpxml:
                let info = analysisService.videoInfo ?? VideoInfo(
                    fps: 30, width: 1920, height: 1080, duration: 0
                )
                content = ExportService.generateFCPXML(
                    segments: exportSegments,
                    videoInfo: info,
                    videoURL: videoModel.videoURL ?? URL(fileURLWithPath: "/unknown"),
                    fontSize: settings.fontSizeExport,
                    maxSubtitleChars: settings.maxSubtitleChars,
                    subtitleLines: settings.subtitleLines
                )
            case .itt:
                content = ExportService.generateITT(
                    segments: exportSegments,
                    fps: analysisService.videoInfo?.fps ?? 24.0,
                    maxSubtitleChars: settings.maxSubtitleChars
                )
            case .edl:
                let fps = analysisService.videoInfo?.fps ?? 30.0
                let base = videoModel.videoURL?.deletingPathExtension().lastPathComponent ?? "edit"
                content = ExportService.generateEDL(segments: exportSegments, fps: fps, title: base)
            case .premiereXml:
                let info = analysisService.videoInfo ?? VideoInfo(fps: 30, width: 1920, height: 1080, duration: 0)
                let base = videoModel.videoURL?.deletingPathExtension().lastPathComponent ?? "edit"
                content = ExportService.generatePremiereXML(
                    segments: exportSegments,
                    videoInfo: info,
                    videoURL: videoModel.videoURL ?? URL(fileURLWithPath: "/unknown"),
                    title: base
                )
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
