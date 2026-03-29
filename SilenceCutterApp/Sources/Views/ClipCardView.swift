import SwiftUI

/// A single clip card in Vrew style — shows segment as a visual block.
/// Discarded clips collapse to a thin gray bar with restore action.
struct ClipCardView: View {
    let index: Int
    @Binding var segment: Segment
    var onSeek: (TimeInterval) -> Void
    var onSplit: () -> Void
    var onMerge: (() -> Void)?
    var isActive: Bool = false

    var body: some View {
        if segment.isKept {
            keptCard
        } else {
            discardedBar
        }
    }

    // MARK: - Kept clip (full card)

    private var keptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: clip number + time range + seek + checkbox
            HStack(spacing: 6) {
                Text("클립 \(index + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                TimeField(seconds: $segment.start)
                Text("–")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
                TimeField(seconds: $segment.end)

                Button {
                    onSeek(segment.start)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)

                Toggle("", isOn: $segment.isKept)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            // Body: word flow or text field
            if segment.words.isEmpty {
                TextField("자막 텍스트", text: $segment.text, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...8)
                    .textFieldStyle(.plain)
            } else {
                WordFlowView(words: $segment.words)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.cyan.opacity(0.08) : Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.cyan.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .contextMenu {
            Button("클립 분할") { onSplit() }
            if let onMerge {
                Button("다음 클립과 병합") { onMerge() }
            }
        }
    }

    // MARK: - Discarded clip (collapsed bar)

    private var discardedBar: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.red.opacity(0.3))
                .frame(width: 3, height: 16)

            Text("클립 \(index + 1) — 삭제됨")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(formatTimeBrief(segment.start))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            Spacer()

            Button("복구") {
                segment.isKept = true
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .foregroundStyle(.cyan)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Brief time format

private func formatTimeBrief(_ seconds: Double) -> String {
    let totalSeconds = max(0, seconds)
    let minutes = Int(totalSeconds) / 60
    let secs = totalSeconds.truncatingRemainder(dividingBy: 60)
    return String(format: "%d:%04.1f", minutes, secs)
}
