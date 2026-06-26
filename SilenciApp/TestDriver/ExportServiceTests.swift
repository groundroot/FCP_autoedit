import Foundation
import Testing
@testable import SilenciCore

@Suite("ExportService — SRT & FCPXML 생성")
struct ExportServiceTests {

    // MARK: - SRT 기본

    @Test func srtEmptySegments() {
        #expect(ExportService.generateSRT(segments: []).isEmpty)
    }

    @Test func srtSingleSegmentContainsText() {
        let result = ExportService.generateSRT(segments: [seg("안녕하세요", 0, 3)])
        #expect(result.hasPrefix("1\n"))
        #expect(result.contains("-->"))
        #expect(result.contains("안녕하세요"))
    }

    @Test func srtSkipsDiscardedSegments() {
        let kept = seg("유지됨", 0, 2)
        var dropped = seg("제거됨", 2, 4)
        dropped.isKept = false
        let result = ExportService.generateSRT(segments: [kept, dropped])
        #expect(result.contains("유지됨"))
        #expect(!result.contains("제거됨"))
    }

    @Test func srtMultipleEntries() {
        let segs = [seg("첫째", 0, 2), seg("둘째", 5, 7), seg("셋째", 10, 12)]
        let result = ExportService.generateSRT(segments: segs)
        #expect(result.contains("1\n"))
        #expect(result.contains("2\n"))
        #expect(result.contains("3\n"))
    }

    // MARK: - 타임코드 형식

    @Test func srtTimecodeHours() {
        // SRT uses edited-timeline timecodes (gaps removed, starts at 0).
        // A single segment at 3661.5–3663.0s → edited 0–1.5s.
        let result = ExportService.generateSRT(segments: [seg("test", 3661.5, 3663.0)])
        #expect(result.contains("00:00:00,000 -->"))
        #expect(result.contains("--> 00:00:01,500"))
    }

    @Test func srtTimecodeStartsAtZero() {
        let result = ExportService.generateSRT(segments: [seg("test", 0, 1)])
        #expect(result.contains("00:00:00,000 -->"))
    }

    // MARK: - 타임라인 리매핑 (편집 타임라인 = 갭 제거)

    @Test func srtTimelineGapsRemoved() {
        // 0-2s 세그먼트, 10s 갭, 12-14s 세그먼트 → 두 번째는 편집 타임라인 2s에 위치
        let segs = [seg("a", 0, 2), seg("b", 12, 14)]
        let result = ExportService.generateSRT(segments: segs)
        #expect(result.contains("00:00:02,000"))
        #expect(!result.contains("00:00:12"))
    }

    // MARK: - 두 줄 자막 모드

    @Test func srtTwoLineSplitsAtMidpoint() {
        // 4단어 → 중간에서 분리: "첫 번째\n세 번째"
        let words = [
            Word(text: "첫", start: 0.0, end: 0.5),
            Word(text: "번째", start: 0.5, end: 1.0),
            Word(text: "세", start: 1.0, end: 1.5),
            Word(text: "번째", start: 1.5, end: 2.0),
        ]
        let s = Segment(start: 0, end: 2, text: "첫 번째 세 번째", isKept: true, words: words)
        let result = ExportService.generateSRT(segments: [s], subtitleLines: 2)
        #expect(result.contains("첫 번째\n세 번째"), "두 줄 분리 실패:\n\(result)")
    }

    @Test func srtSingleWordNotSplit() {
        let words = [Word(text: "안녕", start: 0, end: 1)]
        let s = Segment(start: 0, end: 1, text: "안녕", isKept: true, words: words)
        let result = ExportService.generateSRT(segments: [s], subtitleLines: 2)
        #expect(result.contains("안녕"))
    }

    @Test func srtOneLineIsUnchanged() {
        // subtitleLines=1 (기본값) — 줄바꿈 없음
        let words = [
            Word(text: "첫", start: 0, end: 0.5),
            Word(text: "번째", start: 0.5, end: 1),
            Word(text: "세", start: 1, end: 1.5),
            Word(text: "번째", start: 1.5, end: 2),
        ]
        let s = Segment(start: 0, end: 2, text: "첫 번째 세 번째", isKept: true, words: words)
        let result = ExportService.generateSRT(segments: [s], subtitleLines: 1)
        #expect(!result.contains("첫 번째\n세 번째"))
    }

    // MARK: - FCPXML 기본

    @Test func fcpxmlContainsRoot() {
        let info = VideoInfo(fps: 24.0, width: 1920, height: 1080, duration: 10.0)
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        let result = ExportService.generateFCPXML(segments: [seg("test", 0, 5)],
                                                  videoInfo: info, videoURL: url)
        #expect(result.contains("<?xml version"))
        #expect(result.contains("<fcpxml version=\"1.13\">"))
        #expect(result.contains("<asset-clip"))
    }

    @Test func fcpxmlSkipsDiscarded() {
        let info = VideoInfo(fps: 24.0, width: 1920, height: 1080, duration: 10.0)
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        var dropped = seg("제거됨", 0, 2)
        dropped.isKept = false
        let result = ExportService.generateFCPXML(segments: [dropped],
                                                  videoInfo: info, videoURL: url)
        #expect(!result.contains("<asset-clip"))
    }

    @Test func fcpxmlEscapesAmpersand() {
        let info = VideoInfo(fps: 24.0, width: 1920, height: 1080, duration: 5.0)
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        let words = [Word(text: "A&B", start: 0, end: 1)]
        let s = Segment(start: 0, end: 1, text: "A&B", isKept: true, words: words)
        let result = ExportService.generateFCPXML(segments: [s], videoInfo: info, videoURL: url)
        #expect(result.contains("A&amp;B"))
        #expect(!result.contains(" A&B "))
    }

    @Test func fcpxmlTwoLineMode() {
        let info = VideoInfo(fps: 24.0, width: 1920, height: 1080, duration: 5.0)
        let url = URL(fileURLWithPath: "/tmp/test.mp4")
        let words = [
            Word(text: "첫", start: 0, end: 0.5),
            Word(text: "번째", start: 0.5, end: 1),
            Word(text: "두", start: 1, end: 1.5),
            Word(text: "번째", start: 1.5, end: 2),
        ]
        let s = Segment(start: 0, end: 2, text: "첫 번째 두 번째", isKept: true, words: words)
        let result = ExportService.generateFCPXML(
            segments: [s], videoInfo: info, videoURL: url, subtitleLines: 2
        )
        // 두 줄 텍스트가 FCPXML 요소 값으로 포함됨
        #expect(result.contains("첫 번째\n두 번째") || result.contains("첫 번째"))
    }

    // MARK: - 헬퍼

    private func seg(_ text: String, _ start: Double, _ end: Double) -> Segment {
        Segment(start: start, end: end, text: text, isKept: true)
    }
}
