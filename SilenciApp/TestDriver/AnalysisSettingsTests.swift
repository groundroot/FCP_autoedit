import Foundation
import Testing
@testable import SilenciCore

@Suite("AnalysisSettings — 기본값 · 저장/복원 · 초기화") @MainActor
struct AnalysisSettingsTests {

    private let testKeys = [
        "sc_language", "sc_asrModel", "sc_vadThreshold", "sc_minSpeechMs",
        "sc_minSilenceMs", "sc_speechPadMs", "sc_maxSegmentSeconds",
        "sc_maxSubtitleChars", "sc_subtitleLines", "sc_numSpeakers", "sc_fontSizeExport",
    ]

    private func cleanUD() {
        testKeys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    // MARK: - 기본값

    @Test func defaults() {
        cleanUD()
        let s = AnalysisSettings()
        #expect(s.language == "Korean")
        #expect(s.asrModel == .small)
        #expect(abs(s.vadThreshold - 0.5) < 0.001)
        #expect(s.minSpeechMs == 250)
        #expect(s.minSilenceMs == 200)
        #expect(s.speechPadMs == 100)
        #expect(abs(s.maxSegmentSeconds - 8.0) < 0.001)
        #expect(s.maxSubtitleChars == 20)
        #expect(s.subtitleLines == 1)
        #expect(s.numSpeakers == 0)
        #expect(s.fontSizeExport == 42)
    }

    // MARK: - 저장 / 복원 라운드트립

    @Test func saveLoadRoundtrip() {
        cleanUD()
        let s = AnalysisSettings()
        s.language = "English"
        s.asrModel = .large
        s.vadThreshold = 0.7
        s.minSpeechMs = 300
        s.maxSubtitleChars = 30
        s.subtitleLines = 2
        s.numSpeakers = 3
        s.fontSizeExport = 52
        s.save()

        let r = AnalysisSettings()
        r.load()

        #expect(r.language == "English")
        #expect(r.asrModel == .large)
        #expect(abs(r.vadThreshold - 0.7) < 0.001)
        #expect(r.minSpeechMs == 300)
        #expect(r.maxSubtitleChars == 30)
        #expect(r.subtitleLines == 2)
        #expect(r.numSpeakers == 3)
        #expect(r.fontSizeExport == 52)

        cleanUD()
    }

    @Test func loadWithoutSaveReturnsDefaults() {
        cleanUD()
        let s = AnalysisSettings()
        s.load()
        #expect(s.language == "Korean")
        #expect(s.subtitleLines == 1)
    }

    @Test func speechLanguageCatalogCoversLaunchMarkets() {
        #expect(AnalysisSettings.languages == [
            "Korean",
            "English",
            "Japanese",
            "Chinese",
            "German",
            "French",
            "Spanish",
            "Italian",
            "Portuguese",
        ])
    }

    // MARK: - resetToDefaults

    @Test func resetToDefaults() {
        cleanUD()
        let s = AnalysisSettings()
        s.language = "Japanese"
        s.subtitleLines = 2
        s.numSpeakers = 4
        s.fontSizeExport = 64
        s.resetToDefaults()

        #expect(s.language == "Korean")
        #expect(s.subtitleLines == 1)
        #expect(s.numSpeakers == 0)
        #expect(s.fontSizeExport == 42)
        cleanUD()
    }

    @Test func resetPersistsDefaults() {
        cleanUD()
        let s = AnalysisSettings()
        s.subtitleLines = 2
        s.resetToDefaults()  // 내부적으로 save() 호출

        let r = AnalysisSettings()
        r.load()
        #expect(r.subtitleLines == 1)
        cleanUD()
    }

    // MARK: - ASRModel

    @Test func asrModelRawValues() {
        #expect(AnalysisSettings.ASRModel.small.rawValue == "mlx-community/Qwen3-ASR-0.6B-8bit")
        #expect(AnalysisSettings.ASRModel.whisperSmall.rawValue == "Systran/faster-whisper-small")
        #expect(AnalysisSettings.ASRModel.large.rawValue == "mlx-community/Qwen3-ASR-1.7B-8bit")
    }

    @Test func asrModelRoundtripViaRawValue() {
        let raw = AnalysisSettings.ASRModel.whisperSmall.rawValue
        let restored = AnalysisSettings.ASRModel(rawValue: raw)
        #expect(restored == .whisperSmall)
    }
}
