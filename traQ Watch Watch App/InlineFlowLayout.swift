import SwiftUI

private nonisolated struct FlowLineBreakKey: LayoutValueKey {
    static let defaultValue = false
}

struct FlowLineBreak: View {
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .layoutValue(key: FlowLineBreakKey.self, value: true)
    }
}

/// スポイラーのButtonを文中に置くための折り返し。通常の段落は標準Textを使う。
struct InlineFlowLayout: Layout {
    private struct Placement {
        var point: CGPoint
        var size: CGSize
        var baseline: CGFloat
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: max(1, proposal.width ?? 160), subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: max(1, bounds.width), subviews: subviews)
        for (index, placement) in result.placements.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + placement.point.x, y: bounds.minY + placement.point.y),
                                  proposal: ProposedViewSize(placement.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [Placement]) {
        var placements: [Placement] = []
        var rowStart = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        func finishRow(emptyLine: Bool = false) {
            for index in rowStart..<placements.count {
                placements[index].point.y = y + ascent - placements[index].baseline
            }
            y += max(ascent + descent, emptyLine ? 20 : 0)
            rowStart = placements.count
            x = 0
            ascent = 0
            descent = 0
        }
        for subview in subviews {
            if subview[FlowLineBreakKey.self] {
                finishRow(emptyLine: true)
                placements.append(Placement(point: CGPoint(x: 0, y: y), size: .zero, baseline: 0))
                rowStart = placements.count
                continue
            }
            let dimensions = subview.dimensions(in: ProposedViewSize(width: width, height: nil))
            let size = CGSize(width: min(width, dimensions.width), height: dimensions.height)
            if x > 0 && x + size.width > width { finishRow() }
            let baseline = dimensions[.firstTextBaseline]
            placements.append(Placement(point: CGPoint(x: x, y: y), size: size, baseline: baseline))
            ascent = max(ascent, baseline)
            descent = max(descent, size.height - baseline)
            x += size.width
        }
        finishRow()
        return (CGSize(width: width, height: y), placements)
    }
}
