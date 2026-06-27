import SwiftUI

/// Settings panel — collapsible section in the sidebar or a sheet.
struct SettingsView: View {
    @Bindable var settings: AnalysisSettings
    var proManager: ProManager
    var storeService: StoreService
    var modelManager: ModelManager
    var pythonEnv: PythonEnvironment
    @Binding var isPresented: Bool
    @State private var showModelManager = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                appLanguageSection
                if AppConfig.showsProFeatures || AppConfig.allowsModelDownload {
                    Divider()
                    proSection
                }
                Divider()
                languageSection
                Divider()
                vadSection
                Divider()
                segmentSection
                Divider()
                subtitleSection
                Divider()
                resetSection
            }
            .padding(20)
        }
        .frame(width: 420, height: 780)
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showModelManager) {
            ModelDownloadView(
                modelManager: modelManager,
                pythonEnv: pythonEnv,
                isPresented: $showModelManager
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .foregroundStyle(.cyan)
            Text(L10n.tr("settings.title"))
                .font(.title3.bold())
            Spacer()
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - App Language

    @State private var appLanguage: L10n.AppLanguage = L10n.currentLanguage

    private var appLanguageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.tr("settings.app_language"), systemImage: "globe")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Picker("", selection: $appLanguage) {
                ForEach(L10n.AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: appLanguage) { _, newValue in
                L10n.currentLanguage = newValue
            }

            if appLanguage != L10n.currentLanguage || appLanguage != .system {
                Text(L10n.tr("settings.restart_hint"))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Language & Model

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.tr("settings.speech_recognition"), systemImage: "waveform")
                .font(.headline)
                .foregroundStyle(.cyan)

            HStack {
                Text(L10n.tr("settings.language"))
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $settings.language) {
                    ForEach(AnalysisSettings.languages, id: \.self) { lang in
                        Text(AnalysisSettings.localizedLanguageName(lang)).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            HStack {
                Text(L10n.tr("settings.asr_model"))
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $settings.asrModel) {
                    ForEach(AnalysisSettings.ASRModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - VAD Settings

    private var vadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.tr("settings.vad"), systemImage: "speaker.wave.2")
                .font(.headline)
                .foregroundStyle(.cyan)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.tr("settings.sensitivity"))
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $settings.vadThreshold, in: 0.1...0.9, step: 0.05)
                    Text(String(format: "%.2f", settings.vadThreshold))
                        .font(.caption.monospaced())
                        .frame(width: 40)
                }
                Text(L10n.tr("settings.sensitivity_hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Text(L10n.tr("settings.min_silence"))
                    .frame(width: 80, alignment: .leading)
                TextField("", value: $settings.minSilenceMs, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Text(L10n.tr("settings.min_speech"))
                    .frame(width: 80, alignment: .leading)
                TextField("", value: $settings.minSpeechMs, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack {
                Text(L10n.tr("settings.padding"))
                    .frame(width: 80, alignment: .leading)
                TextField("", value: $settings.speechPadMs, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Segment Settings

    private var segmentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.tr("settings.segment"), systemImage: "scissors")
                .font(.headline)
                .foregroundStyle(.cyan)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.tr("settings.max_length"))
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $settings.maxSegmentSeconds, in: 3...20, step: 1)
                    Text(L10n.tr("settings.seconds_unit", Int(settings.maxSegmentSeconds)))
                        .font(.caption.monospaced())
                        .frame(width: 35)
                }
                Text(L10n.tr("settings.max_length_hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Subtitle Settings

    private var subtitleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.tr("settings.subtitle"), systemImage: "captions.bubble")
                .font(.headline)
                .foregroundStyle(.cyan)

            // Density slider
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(L10n.tr("subtitle.density"))
                        .frame(width: 80, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(settings.maxSubtitleChars) },
                        set: { settings.maxSubtitleChars = Int($0) }
                    ), in: 10...44, step: 2)
                    Text("\(settings.maxSubtitleChars)")
                        .font(.caption.monospaced())
                        .frame(width: 28)
                }
                Text(L10n.tr("subtitle.density_hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 84)
            }

            // Lines picker
            HStack {
                Text(L10n.tr("subtitle.lines"))
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $settings.subtitleLines) {
                    Text(L10n.tr("subtitle.lines_one")).tag(1)
                    Text(L10n.tr("subtitle.lines_two")).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Speaker count picker
            HStack {
                Text(L10n.tr("subtitle.speakers"))
                    .frame(width: 80, alignment: .leading)
                Picker("", selection: $settings.numSpeakers) {
                    Text(L10n.tr("subtitle.speakers_auto")).tag(0)
                    Text(L10n.tr("subtitle.speakers_1")).tag(1)
                    Text(L10n.tr("subtitle.speakers_2")).tag(2)
                    Text(L10n.tr("subtitle.speakers_3")).tag(3)
                    Text(L10n.tr("subtitle.speakers_4")).tag(4)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Font size
            HStack {
                Text(L10n.tr("settings.font_size"))
                    .frame(width: 80, alignment: .leading)
                TextField("", value: $settings.fontSizeExport, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Text("pt (FCPXML)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - PRO / Model

    private var proSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if AppConfig.showsProFeatures {
                Label(proManager.isPro ? L10n.tr("pro.pro_badge") : L10n.tr("pro.free_badge"),
                      systemImage: proManager.isPro ? "star.fill" : "star")
                    .font(.headline)
                    .foregroundStyle(proManager.isPro ? .cyan : .orange)

                if proManager.isPro {
                    Text("PRO — 무제한 내보내기 활성화")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.tr("pro.limit_banner"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            Task { await storeService.purchase(proManager: proManager) }
                        } label: {
                            Label(storeService.isPurchasing
                                  ? L10n.tr("store.purchasing")
                                  : L10n.tr("store.buy", storeService.proPrice),
                                  systemImage: "star.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(storeService.isPurchasing)

                        Button(L10n.tr("store.restore")) {
                            Task { await storeService.restoreIfNeeded(proManager: proManager) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if AppConfig.showsProFeatures && AppConfig.allowsModelDownload {
                Divider()
            }

            if AppConfig.allowsModelDownload {
                Button {
                    showModelManager = true
                } label: {
                    Label(L10n.tr("model.manage"), systemImage: "cpu")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        HStack {
            Spacer()
            Button(L10n.tr("settings.reset")) {
                settings.resetToDefaults()
            }
            .foregroundStyle(.red)
        }
    }
}
