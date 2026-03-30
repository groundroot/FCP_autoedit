import SwiftUI

/// Vrew-style transcript editor with card-based clip layout.
/// Shows each segment as a ClipCardView. Discarded clips collapse.
/// Supports current-clip highlighting via currentTime.
struct TranscriptEditorView: View {
    @Bindable var analysisService: AnalysisService
    var onSeek: (TimeInterval) -> Void
    var currentTime: TimeInterval = 0

    /// The clip index that is visually highlighted.
    /// Updated via onChange(of: currentTime) — only fires when the clip actually changes,
    /// so the body is NOT re-evaluated on every 0.1s time tick.
    @State private var highlightedIndex: Int?

    var body: some View {
        if analysisService.segments.isEmpty {
            ContentUnavailableView(
                L10n.tr("transcript.no_results"),
                systemImage: "text.magnifyingglass",
                description: Text(L10n.tr("transcript.no_speech"))
            )
        } else {
            scrollContent
                // Compute active clip outside body — only update @State when clip changes
                .onChange(of: currentTime) { _, time in
                    let newIndex = analysisService.segments.firstIndex { seg in
                        seg.isKept && time >= seg.start && time < seg.end
                    }
                    if newIndex != highlightedIndex {
                        highlightedIndex = newIndex
                    }
                }
        }
    }

    /// The scroll content is a separate computed property so that it only re-evaluates
    /// when highlightedIndex (@State) changes — NOT when currentTime changes.
    @ViewBuilder
    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(analysisService.segments.enumerated()), id: \.element.id) { index, segment in
                    ClipCardView(
                        index: index,
                        segment: $analysisService.segments[index],
                        onSeek: onSeek,
                        onSplit: {
                            analysisService.splitSegment(at: index)
                        },
                        onSplitAtWord: { wordIndex in
                            analysisService.splitSegment(at: index, wordIndex: wordIndex)
                        },
                        onMerge: index < analysisService.segments.count - 1 ? {
                            analysisService.mergeWithNext(at: index)
                        } : nil,
                        isActive: highlightedIndex == index
                    )
                    .id(segment.id)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Time formatting (shared)

/// Format seconds as MM:SS.s (e.g. 01:23.4)
func formatTime(_ seconds: Double) -> String {
    let totalSeconds = max(0, seconds)
    let minutes = Int(totalSeconds) / 60
    let secs = totalSeconds.truncatingRemainder(dividingBy: 60)
    return String(format: "%02d:%04.1f", minutes, secs)
}

/// Parse MM:SS.s format back to seconds. Returns nil if invalid.
func parseTime(_ string: String) -> Double? {
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
struct TimeField: View {
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
                if !isFocused {
                    text = formatTime(newValue)
                }
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
                    }
                    text = formatTime(seconds)
                }
            }
    }
}

// MARK: - Previews

#Preview("With segments") {
    let service = AnalysisService()
    service.segments = [
        Segment(start: 0.0, end: 2.5, text: "Hello world", isKept: true),
        Segment(start: 3.0, end: 5.5, text: "This is a test segment", isKept: true),
        Segment(start: 6.0, end: 8.0, text: "Deleted segment", isKept: false),
    ]
    return TranscriptEditorView(analysisService: service, onSeek: { _ in }, currentTime: 1.0)
        .frame(width: 300, height: 400)
}
