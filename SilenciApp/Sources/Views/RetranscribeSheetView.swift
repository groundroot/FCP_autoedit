import SwiftUI
import UniformTypeIdentifiers

/// Sheet for retranscribing an edited FCPXML — settings + progress + completion.
struct RetranscribeSheetView: View {
    let inputURL: URL
    let defaultOutputURL: URL
    let settings: AnalysisSettings
    @Binding var state: ContentView.RetranscribeState
    let analysisService: AnalysisService
    var pythonEnv: PythonEnvironment
    let onDismiss: () -> Void

    // Local settings for this retranscribe run
    @State private var language: String = "Korean"
    @State private var asrModel: AnalysisSettings.ASRModel = .small
    @State private var subtitleLines: Int = 1
    @State private var numSpeakers: Int = 0
    @State private var exportITT: Bool = true
    @State private var outputURL: URL?
    @State private var outputInitialized = false
    @State private var retranscribeTask: Task<Void, Never>?

    // Timer for progress polling
    @State private var progressDetail: String = ""
    @State private var progressTimer: Timer?

    /// The output URL to use — local override or the default passed from parent.
    private var effectiveOutputURL: URL {
        outputURL ?? defaultOutputURL
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.tr("retranscribe.title"))
                    .font(.headline)
                Spacer()
                if case .running = state {
                    // No close button while running
                } else {
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()

            Divider()

            switch state {
            case .idle:
                settingsContent
            case .running:
                progressContent
            case .done(let path):
                doneContent(path: path)
            case .error(let msg):
                errorContent(message: msg)
            }
        }
        .frame(width: 420)
        .onAppear {
            language = settings.language
            asrModel = settings.asrModel
            subtitleLines = settings.subtitleLines
            numSpeakers = settings.numSpeakers
            if !outputInitialized {
                outputURL = defaultOutputURL
                outputInitialized = true
            }
        }
        .onDisappear {
            progressTimer?.invalidate()
        }
    }

    // MARK: - Settings (before start)

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Input file
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.cyan)
                Text(L10n.tr("retranscribe.input"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text(inputURL.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal)

            // Output path
            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.cyan)
                Text(L10n.tr("retranscribe.output"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Text(effectiveOutputURL.lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(L10n.tr("retranscribe.change")) {
                    chooseOutputPath()
                }
                .font(.subheadline)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            // Language picker
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("retranscribe.language"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Picker("", selection: $language) {
                    ForEach(AnalysisSettings.languages, id: \.self) { lang in
                        Text(AnalysisSettings.localizedLanguageName(lang)).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            // ASR model picker
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("retranscribe.ai_model"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Picker("", selection: $asrModel) {
                    ForEach(AnalysisSettings.ASRModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            // Subtitle lines picker
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("subtitle.lines"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Picker("", selection: $subtitleLines) {
                    Text(L10n.tr("subtitle.lines_one")).tag(1)
                    Text(L10n.tr("subtitle.lines_two")).tag(2)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            // Speaker count picker
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("subtitle.speakers"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Picker("", selection: $numSpeakers) {
                    Text(L10n.tr("subtitle.speakers_auto")).tag(0)
                    Text(L10n.tr("subtitle.speakers_1")).tag(1)
                    Text(L10n.tr("subtitle.speakers_2")).tag(2)
                    Text(L10n.tr("subtitle.speakers_3")).tag(3)
                    Text(L10n.tr("subtitle.speakers_4")).tag(4)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            // iTT export toggle
            Toggle(L10n.tr("retranscribe.export_itt"), isOn: $exportITT)
                .padding(.horizontal)

            // Start button
            HStack {
                Spacer()
                Button(L10n.tr("retranscribe.start")) {
                    startRetranscribe()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                Spacer()
            }
            .padding()
        }
        .padding(.top, 12)
    }

    // MARK: - Progress (while running)

    private var progressContent: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .scaleEffect(1.3)

            Text(L10n.tr("retranscribe.in_progress"))
                .font(.headline)

            Text(progressDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 40)

            Button(role: .destructive) {
                cancelRetranscribe()
            } label: {
                Label(L10n.tr("retranscribe.cancel"), systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .frame(minHeight: 200)
        .onAppear { startProgressPolling() }
        .onDisappear { progressTimer?.invalidate() }
    }

    // MARK: - Done

    private func doneContent(path: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text(L10n.tr("retranscribe.done"))
                .font(.headline)

            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(L10n.tr("retranscribe.show_in_finder")) {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button(L10n.tr("retranscribe.close")) {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .frame(minHeight: 200)
    }

    // MARK: - Error

    private func errorContent(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(L10n.tr("retranscribe.error"))
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(L10n.tr("retranscribe.retry")) {
                    state = .idle
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button(L10n.tr("retranscribe.close")) {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .frame(minHeight: 200)
    }

    // MARK: - Actions

    private func chooseOutputPath() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: "fcpxml")!]
        if let existing = outputURL {
            savePanel.directoryURL = existing.deletingLastPathComponent()
            savePanel.nameFieldStringValue = existing.lastPathComponent
        }

        savePanel.beginSheetModal(for: window) { response in
            if response == .OK, let url = savePanel.url {
                outputURL = url
            }
        }
    }

    private func startRetranscribe() {
        let outURL = effectiveOutputURL

        state = .running
        progressDetail = ""

        retranscribeTask = Task {
            do {
                let result = try await analysisService.retranscribeToFile(
                    fcpxmlURL: inputURL,
                    outputURL: outURL,
                    environment: pythonEnv,
                    language: language,
                    asrModel: asrModel.rawValue,
                    fontSize: settings.fontSizeExport,
                    maxSubtitleChars: settings.maxSubtitleChars,
                    subtitleLines: subtitleLines,
                    numSpeakers: numSpeakers,
                    exportITT: exportITT
                )
                await MainActor.run {
                    state = .done(outputPath: result.outputPath)
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run { state = .idle }
                } else {
                    await MainActor.run {
                        state = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func cancelRetranscribe() {
        retranscribeTask?.cancel()
        analysisService.cancelRetranscribe()
        state = .idle
    }

    private func startProgressPolling() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in
                if let p = analysisService.retranscribeProgress {
                    progressDetail = p.detail
                }
            }
        }
    }
}
