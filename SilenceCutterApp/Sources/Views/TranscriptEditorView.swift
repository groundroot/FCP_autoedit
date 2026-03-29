import SwiftUI

/// Interactive transcript editor replacing the read-only SegmentListView.
/// Shows each segment as a row with a checkbox (keep/discard), time range, and tappable text that seeks.
struct TranscriptEditorView: View {
    @Bindable var analysisService: AnalysisService
    var onSeek: (TimeInterval) -> Void

    var body: some View {
        if analysisService.segments.isEmpty {
            ContentUnavailableView(
                "분석 결과가 없습니다",
                systemImage: "text.magnifyingglass",
                description: Text("음성이 감지되지 않았습니다.")
            )
        } else {
            List(Array(analysisService.segments.enumerated()), id: \.element.id) { index, segment in
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: $analysisService.segments[index].isKept)
                        .toggleStyle(.checkbox)
                        .labelsHidden()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 2) {
                            TimeField(seconds: $analysisService.segments[index].start)
                            Text("–")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            TimeField(seconds: $analysisService.segments[index].end)
                            Button {
                                onSeek(segment.start)
                            } label: {
                                Image(systemName: "play.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        // Word-level editing if words exist, otherwise text field
                        if segment.words.isEmpty {
                            TextField("자막 텍스트", text: $analysisService.segments[index].text, axis: .vertical)
                                .font(.body)
                                .lineLimit(1...5)
                                .textFieldStyle(.plain)
                                .strikethrough(!segment.isKept)
                        } else {
                            WordFlowView(
                                words: $analysisService.segments[index].words,
                                disabled: !segment.isKept
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
                .opacity(segment.isKept ? 1.0 : 0.5)
                .contextMenu {
                    Button("클립 분할") {
                        analysisService.splitSegment(at: index)
                    }
                    if index < analysisService.segments.count - 1 {
                        Button("다음 클립과 병합") {
                            analysisService.mergeWithNext(at: index)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Time formatting

/// Format seconds as MM:SS.s (e.g. 01:23.4)
private func formatTime(_ seconds: Double) -> String {
    let totalSeconds = max(0, seconds)
    let minutes = Int(totalSeconds) / 60
    let secs = totalSeconds.truncatingRemainder(dividingBy: 60)
    return String(format: "%02d:%04.1f", minutes, secs)
}

/// Parse MM:SS.s format back to seconds. Returns nil if invalid.
private func parseTime(_ string: String) -> Double? {
    let parts = string.split(separator: ":")
    guard parts.count == 2,
          let minutes = Double(parts[0]),
          let secs = Double(parts[1]),
          minutes >= 0, secs >= 0, secs < 60 else {
        return nil
    }
    return minutes * 60 + secs
}

/// Editable time field that displays and parses MM:SS.s format.
private struct TimeField: View {
    @Binding var seconds: Double
    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("00:00.0", text: $text)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textFieldStyle(.plain)
            .frame(width: 52)
            .focused($isFocused)
            .onAppear { text = formatTime(seconds) }
            .onChange(of: seconds) { _, newValue in
                if !isFocused { text = formatTime(newValue) }
            }
            .onSubmit {
                if let parsed = parseTime(text) {
                    seconds = parsed
                } else {
                    text = formatTime(seconds)
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    if let parsed = parseTime(text) {
                        seconds = parsed
                    } else {
                        text = formatTime(seconds)
                    }
                }
            }
    }
}

#Preview("With Segments") {
    @Previewable @State var service = AnalysisService()
    TranscriptEditorView(analysisService: service, onSeek: { _ in })
        .frame(width: 300, height: 300)
        .onAppear {
            service.segments = [
                Segment(start: 0.5, end: 3.2, text: "안녕하세요, 오늘은 날씨가 좋습니다."),
                Segment(start: 5.0, end: 8.1, text: "테스트 세그먼트입니다.", isKept: false),
                Segment(start: 62.3, end: 65.7, text: "1분이 넘는 타임스탬프 예시"),
            ]
        }
}

#Preview("Empty") {
    @Previewable @State var service = AnalysisService()
    TranscriptEditorView(analysisService: service, onSeek: { _ in })
        .frame(width: 300, height: 300)
}
