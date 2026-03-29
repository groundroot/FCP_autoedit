import SwiftUI

/// A horizontally wrapping layout of words, each clickable to toggle isKept.
/// Deleted words show strikethrough + reduced opacity.
struct WordFlowView: View {
    @Binding var words: [Word]
    var disabled: Bool = false

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                Text(word.text)
                    .font(.body)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(word.isKept ? Color.clear : Color.red.opacity(0.15))
                    )
                    .strikethrough(!word.isKept)
                    .opacity(word.isKept ? 1.0 : 0.4)
                    .onTapGesture {
                        guard !disabled else { return }
                        words[index].isKept.toggle()
                    }
            }
        }
    }
}

/// Simple horizontal flow layout that wraps to next line when width exceeds available space.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                // Wrap to next line
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
        }

        return (CGSize(width: totalWidth, height: y + rowHeight), positions)
    }
}
