import SwiftUI

/// Vrew-style transcript editor with card-based clip layout.
/// Shows each segment as a ClipCardView. Discarded clips collapse.
/// Observes videoModel directly for current-clip highlighting.
struct TranscriptEditorView: View {
    @Bindable var analysisService: AnalysisService
    var onSeek: (TimeInterval) -> Void
    /// Video model for playback time — observed only for clip-change detection.
    var videoModel: VideoPlayerModel

    /// The clip index that is visually highlighted.
    @State private var highlightedIndex: Int?
    /// Timer to poll currentTime at a lower rate than the 10Hz observer.
    @State private var pollTimer: Timer?

    var body: some View {
        if analysisService.segments.isEmpty {
            ContentUnavailableView(
                L10n.tr("transcript.no_results"),
                systemImage: "text.magnifyingglass",
                description: Text(L10n.tr("transcript.no_speech"))
            )
        } else {
            scrollContent
                .onAppear { startPolling() }
                .onDisappear { stopPolling() }
        }
    }

    /// The scroll list — only re-evaluates when highlightedIndex or segments change.
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

    // MARK: - Polling (avoids @Observable dependency on currentTime)

    /// Poll at ~2Hz instead of 10Hz to find active clip. This does NOT
    /// trigger SwiftUI body re-evaluation — it only mutates @State when the clip changes.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                let time = videoModel.currentTime
                let newIndex = analysisService.segments.firstIndex { seg in
                    seg.isKept && time >= seg.start && time < seg.end
                }
                if newIndex != highlightedIndex {
                    highlightedIndex = newIndex
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
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

