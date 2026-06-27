import SwiftUI

/// Descript 스타일 텍스트 기반 편집기.
/// 모든 세그먼트의 단어를 연속 흐름으로 표시.
/// - 단어 탭: 비디오 seek + isKept 토글
/// - 재생 중인 단어 cyan 하이라이트
/// - 세그먼트 경계: 침묵 길이 표시 마커
struct TextBasedEditorView: View {
    var analysisService: AnalysisService
    var currentTime: Double
    var onSeek: (Double) -> Void
    var speakerNames: [Int: String] = [:]
    var hiddenSpeakers: Set<Int> = []

    @State private var autoScroll = true
    @State private var lastCurrentWordID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    FlowLayout(spacing: 5) {
                        ForEach(flatItems) { item in
                            itemView(for: item)
                        }
                    }
                    .padding(24)
                }
                .onChange(of: currentTime) { _, time in
                    let newID = wordIDAtTime(time)
                    guard newID != lastCurrentWordID else { return }
                    lastCurrentWordID = newID
                    if autoScroll, let id = newID {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Label(L10n.tr("editor.transcript"), systemImage: "quote.bubble")
                .font(.headline)
                .labelStyle(.titleAndIcon)

            HStack(spacing: 6) {
                statusPill(
                    L10n.tr("editor.kept_words", keptWordCount, totalWordCount),
                    systemImage: "checkmark.circle.fill",
                    color: .cyan
                )
                if removedWordCount > 0 {
                    statusPill(
                        L10n.tr("editor.removed_words", removedWordCount),
                        systemImage: "scissors",
                        color: .red
                    )
                }
            }

            Spacer()

            Toggle(isOn: $autoScroll) {
                Text(L10n.tr("editor.auto_scroll"))
            }
            .toggleStyle(.checkbox)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private func statusPill(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var totalWordCount: Int {
        analysisService.segments.reduce(0) { $0 + $1.words.count }
    }

    private var keptWordCount: Int {
        analysisService.segments.reduce(0) { partial, segment in
            partial + segment.words.filter(\.isKept).count
        }
    }

    private var removedWordCount: Int {
        max(0, totalWordCount - keptWordCount)
    }

    // MARK: - Item view builder

    @ViewBuilder
    private func itemView(for item: FlatItem) -> some View {
        switch item.kind {
        case .word(let si, let wi):
            wordView(si: si, wi: wi, id: item.id)
        case .segBreak(let gap):
            SegBreakView(gap: gap)
        }
    }

    @ViewBuilder
    private func wordView(si: Int, wi: Int, id: String) -> some View {
        let segs = analysisService.segments
        if si < segs.count, wi < segs[si].words.count {
            let word = segs[si].words[wi]
            let spkId = segs[si].speakerId
            let isSpeakerHidden = spkId.map { hiddenSpeakers.contains($0) } ?? false
            WordTokenView(
                text: word.text,
                isKept: word.isKept && !isSpeakerHidden,
                isCurrent: currentTime >= word.start && currentTime < word.end,
                speakerColor: spkId.map { Self.speakerColor($0) },
                onTap: {
                    guard !isSpeakerHidden else { return }
                    onSeek(word.start)
                    analysisService.segments[si].words[wi].isKept.toggle()
                }
            )
            .id(id)
        }
    }

    static func speakerColor(_ id: Int) -> Color {
        let palette: [Color] = [.cyan, Color(red: 1, green: 0.85, blue: 0.2),
                                Color(red: 0.8, green: 0.5, blue: 1.0), .orange, .green, .pink]
        return palette[id % palette.count]
    }

    // MARK: - Flat item list

    private enum ItemKind {
        case word(segIdx: Int, wordIdx: Int)
        case segBreak(gap: Double)
    }

    private struct FlatItem: Identifiable {
        let id: String
        let kind: ItemKind
    }

    private var flatItems: [FlatItem] {
        var result: [FlatItem] = []
        for (si, seg) in analysisService.segments.enumerated() {
            if si > 0 {
                let prev = analysisService.segments[si - 1]
                result.append(FlatItem(id: "brk-\(si)", kind: .segBreak(gap: seg.start - prev.end)))
            }
            for wi in seg.words.indices {
                result.append(FlatItem(id: "w-\(si)-\(wi)", kind: .word(segIdx: si, wordIdx: wi)))
            }
        }
        return result
    }

    private func wordIDAtTime(_ time: Double) -> String? {
        for (si, seg) in analysisService.segments.enumerated() {
            for (wi, word) in seg.words.enumerated() {
                if time >= word.start, time < word.end {
                    return "w-\(si)-\(wi)"
                }
            }
        }
        return nil
    }
}

// MARK: - Word Token

private struct WordTokenView: View {
    let text: String
    let isKept: Bool
    let isCurrent: Bool
    let speakerColor: Color?
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            if let color = speakerColor {
                Circle()
                    .fill(color.opacity(0.7))
                    .frame(width: 5, height: 5)
            }
            Text(text)
                .font(.callout)
                .fontWeight(isCurrent ? .semibold : .regular)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(bgView)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .strikethrough(!isKept, color: .red.opacity(0.75))
        .foregroundStyle(fgColor)
        .opacity(isKept ? 1.0 : 0.45)
        .onTapGesture { onTap() }
        .animation(.easeInOut(duration: 0.1), value: isCurrent)
        .animation(.easeInOut(duration: 0.12), value: isKept)
    }

    @ViewBuilder private var bgView: some View {
        if isCurrent {
            RoundedRectangle(cornerRadius: 5).fill(Color.cyan.opacity(0.28))
        } else if !isKept {
            RoundedRectangle(cornerRadius: 5).fill(Color.red.opacity(0.12))
        } else {
            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.04))
        }
    }

    private var fgColor: Color {
        if isCurrent { return .white }
        if !isKept { return .secondary }
        return .primary
    }
}

// MARK: - Segment Break View

private struct SegBreakView: View {
    let gap: Double

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 4, height: 4)
            }
            if gap > 0.8 {
                Text(String(format: "%.1fs", gap))
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.45))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}
