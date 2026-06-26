import Testing
@testable import SilenciCore

@Suite("ProManager — 무료 제한 & PRO 상태") @MainActor
struct ProManagerTests {

    // MARK: - keptDuration

    @Test func keptDurationEmpty() {
        #expect(ProManager.keptDuration([]) == 0.0)
    }

    @Test func keptDurationAllKept() {
        let segs = [seg(0, 10), seg(10, 20), seg(20, 30)]
        #expect(abs(ProManager.keptDuration(segs) - 30.0) < 0.001)
    }

    @Test func keptDurationSkipsDiscarded() {
        let segs = [seg(0, 10), seg(10, 20, kept: false), seg(20, 30)]
        #expect(abs(ProManager.keptDuration(segs) - 20.0) < 0.001)
    }

    // MARK: - clampedSegments (무료 티어)

    @Test func noClampUnderLimit() {
        let pm = makeProManager()
        let (result, wasClamped) = pm.clampedSegments([seg(0, 30)])
        #expect(!wasClamped)
        #expect(abs(result[0].end - 30.0) < 0.001)
    }

    @Test func noClampExactlyAtLimit() {
        let pm = makeProManager()
        let (result, wasClamped) = pm.clampedSegments([seg(0, 60)])
        #expect(!wasClamped)
        #expect(abs(result[0].end - 60.0) < 0.001)
    }

    @Test func clampSingleOverLimitSegment() {
        let pm = makeProManager()
        let (result, wasClamped) = pm.clampedSegments([seg(0, 90)])
        #expect(wasClamped)
        let kept = ProManager.keptDuration(result)
        #expect(kept <= ProManager.freeLimitSeconds + 0.001)
        #expect(kept > 0)
    }

    @Test func clampTwoSegmentsPartialTruncation() {
        // 50s + 50s = 100s; 50s + 10s = 60s 유지
        let pm = makeProManager()
        let (result, wasClamped) = pm.clampedSegments([seg(0, 50), seg(50, 100)])
        #expect(wasClamped)
        #expect(abs(ProManager.keptDuration(result) - 60.0) < 0.001)
        let second = result.first(where: { $0.start == 50 })
        #expect(second != nil)
        #expect(abs((second?.end ?? 0) - 60.0) < 0.001)
    }

    @Test func discardedSegmentsPassThroughBetweenKept() {
        // kept(0-30) → discarded(30-50) → kept(50-80) = 60s 유지, wasClamped = false
        let pm = makeProManager()
        let segs = [seg(0, 30), seg(30, 50, kept: false), seg(50, 80)]
        let (result, wasClamped) = pm.clampedSegments(segs)
        #expect(!wasClamped)
        #expect(result.count == 3)
        #expect(result.contains(where: { !$0.isKept }))
    }

    // MARK: - PRO 상태

    @Test func proUserNotClamped() {
        let pm = makeProManager()
        pm.unlock()
        let (result, wasClamped) = pm.clampedSegments([seg(0, 120)])
        #expect(!wasClamped)
        #expect(abs(result[0].end - 120.0) < 0.001)
        pm.revoke()
    }

    @Test func unlockPersistsToNewInstance() {
        let pm = makeProManager()
        #expect(!pm.isPro)
        pm.unlock()
        #expect(pm.isPro)
        pm.revoke()
    }

    @Test func revoke() {
        let pm = makeProManager()
        pm.unlock()
        pm.revoke()
        #expect(!pm.isPro)
    }

    @Test func freeLimitIs60Seconds() {
        #expect(ProManager.freeLimitSeconds == 60.0)
    }

    // MARK: - 헬퍼

    private func makeProManager() -> ProManager {
        let pm = ProManager()
        pm.revoke()  // 테스트 시작 전 반드시 무료 상태로 초기화
        return pm
    }

    private func seg(_ start: Double, _ end: Double, kept: Bool = true) -> Segment {
        Segment(start: start, end: end, text: "test", isKept: kept)
    }
}
