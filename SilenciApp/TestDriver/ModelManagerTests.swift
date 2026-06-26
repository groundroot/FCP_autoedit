import Testing
@testable import SilenciCore

@Suite("ModelManager — 카탈로그 · 크기 포맷 · 가용성") @MainActor
struct ModelManagerTests {

    // MARK: - 카탈로그

    @Test func catalogHasTwoModels() {
        let mm = ModelManager()
        #expect(mm.models.count == 2)
    }

    @Test func catalogIds() {
        let mm = ModelManager()
        let ids = mm.models.map(\.id)
        #expect(ids.contains("small"))
        #expect(ids.contains("large"))
    }

    @Test func catalogHuggingFaceIds() {
        let mm = ModelManager()
        #expect(mm.models.first(where: { $0.id == "small" })?.huggingFaceId
                == "mlx-community/Qwen3-ASR-0.6B-8bit")
        #expect(mm.models.first(where: { $0.id == "large" })?.huggingFaceId
                == "mlx-community/Qwen3-ASR-1.7B-8bit")
    }

    // MARK: - formattedSize

    @Test func formattedSizeMB() {
        let mm = ModelManager()
        #expect(mm.formattedSize(500) == "500 MB")
        #expect(mm.formattedSize(999) == "999 MB")
    }

    @Test func formattedSizeGB() {
        let mm = ModelManager()
        #expect(mm.formattedSize(1000) == "1.0 GB")
        #expect(mm.formattedSize(1500) == "1.5 GB")
        #expect(mm.formattedSize(2000) == "2.0 GB")
    }

    // MARK: - model(for:)

    @Test func modelForSmall() {
        let mm = ModelManager()
        let m = mm.model(for: .small)
        #expect(m != nil)
        #expect(m?.id == "small")
    }

    @Test func modelForLarge() {
        let mm = ModelManager()
        let m = mm.model(for: .large)
        #expect(m != nil)
        #expect(m?.id == "large")
    }

    // MARK: - refreshAvailability

    @Test func refreshAvailabilityDoesNotCrash() {
        let mm = ModelManager()
        mm.refreshAvailability()
        // isDownloaded는 로컬 HF 캐시 상태에 따라 true/false — 크래시 없음을 검증
        for model in mm.models {
            // isDownloaded는 Bool — nil이 될 수 없음 (컴파일러 보장)
            _ = model.isDownloaded
        }
        #expect(mm.models.count == 2)
    }

    @Test func initialStateIsNotDownloading() {
        let mm = ModelManager()
        for model in mm.models {
            #expect(model.downloadProgress == nil)
            #expect(model.downloadError == nil)
        }
    }
}
