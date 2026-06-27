import SwiftUI

/// Pre-analysis settings dialog — shown when a video is loaded or "Analyze" is clicked.
/// Lets the user configure language, model, VAD sensitivity, etc. before starting analysis.
struct AnalyzeDialogView: View {
    @Bindable var settings: AnalysisSettings
    @Binding var isPresented: Bool
    var onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .foregroundStyle(.cyan)
                    .font(.title2)
                Text(L10n.tr("dialog.title"))
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
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Settings content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsSection(L10n.tr("dialog.speech_recognition"), systemImage: "waveform") {
                        settingsRow(L10n.tr("dialog.language")) {
                            Picker("", selection: $settings.language) {
                                ForEach(AnalysisSettings.languages, id: \.self) { lang in
                                    Text(AnalysisSettings.localizedLanguageName(lang)).tag(lang)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        settingsRow(L10n.tr("dialog.model")) {
                            Picker("", selection: $settings.asrModel) {
                                ForEach(AnalysisSettings.ASRModel.allCases) { model in
                                    Text(model.displayName).tag(model)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Divider()

                    settingsSection(L10n.tr("dialog.silence_detection"), systemImage: "speaker.wave.2") {
                        settingsRow(L10n.tr("dialog.sensitivity")) {
                            HStack(spacing: 10) {
                                Slider(value: $settings.vadThreshold, in: 0.1...0.9, step: 0.05)
                                Text(String(format: "%.2f", settings.vadThreshold))
                                    .font(.caption.monospaced())
                                    .frame(width: 36)
                            }
                        }

                        settingsHint(L10n.tr("dialog.sensitivity_hint"))

                        settingsRow(L10n.tr("dialog.min_silence")) {
                            HStack(spacing: 6) {
                                numberField(value: $settings.minSilenceMs)
                                Text("ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }

                        settingsRow(L10n.tr("dialog.padding")) {
                            HStack(spacing: 6) {
                                numberField(value: $settings.speechPadMs)
                                Text("ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }

                    Divider()

                    settingsSection(L10n.tr("dialog.subtitle"), systemImage: "captions.bubble") {
                        settingsRow(L10n.tr("dialog.max_clip")) {
                            HStack(spacing: 10) {
                                Slider(value: $settings.maxSegmentSeconds, in: 3...20, step: 1)
                                Text(L10n.tr("dialog.seconds_unit", Int(settings.maxSegmentSeconds)))
                                    .font(.caption.monospaced())
                                    .frame(width: 34, alignment: .trailing)
                            }
                        }

                        settingsRow(L10n.tr("dialog.font")) {
                            HStack(spacing: 6) {
                                numberField(value: $settings.fontSizeExport)
                                Text("pt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                    }

                    Divider()

                    settingsSection(L10n.tr("subtitle.section_title"), systemImage: "text.bubble") {
                        settingsRow(L10n.tr("subtitle.density")) {
                            HStack(spacing: 10) {
                                Slider(value: Binding(
                                    get: { Double(settings.maxSubtitleChars) },
                                    set: { settings.maxSubtitleChars = Int($0) }
                                ), in: 10...44, step: 2)
                                Text("\(settings.maxSubtitleChars)")
                                    .font(.caption.monospaced())
                                    .frame(width: 28, alignment: .trailing)
                            }
                        }

                        settingsHint(L10n.tr("subtitle.density_hint"))

                        settingsRow(L10n.tr("subtitle.lines")) {
                            Picker("", selection: $settings.subtitleLines) {
                                Text(L10n.tr("subtitle.lines_one")).tag(1)
                                Text(L10n.tr("subtitle.lines_two")).tag(2)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 160)
                        }

                        settingsRow(L10n.tr("subtitle.speakers")) {
                            Picker("", selection: $settings.numSpeakers) {
                                Text(L10n.tr("subtitle.speakers_auto")).tag(0)
                                Text(L10n.tr("subtitle.speakers_1")).tag(1)
                                Text(L10n.tr("subtitle.speakers_2")).tag(2)
                                Text(L10n.tr("subtitle.speakers_3")).tag(3)
                                Text(L10n.tr("subtitle.speakers_4")).tag(4)
                            }
                            .labelsHidden()
                            .frame(width: 160, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Action buttons
            HStack {
                Button(L10n.tr("dialog.defaults")) {
                    settings.resetToDefaults()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button(L10n.tr("dialog.cancel")) {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button(L10n.tr("dialog.start")) {
                    isPresented = false
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 640)
        .background(.ultraThinMaterial)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(.cyan)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                content()
            }
        }
    }

    private func settingsRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 104, alignment: .leading)
            content()
        }
    }

    private func settingsHint(_ text: String) -> some View {
        GridRow {
            Color.clear
                .frame(width: 104, height: 0)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func numberField(value: Binding<Int>) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
    }
}
