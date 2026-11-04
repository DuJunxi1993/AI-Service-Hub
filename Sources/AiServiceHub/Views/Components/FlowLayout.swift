import SwiftUI

/// 自动换行的流式布局
///
/// `HStack` 不会换行：按钮一多，HStack 的最小宽度就超过容器，
/// 内容会被**两侧**裁掉（左右各溢出一点，看起来像被居中截断）。
/// 这个布局把子视图按可用宽度折行，放不下就换到下一行。
///
/// `alignment` 决定每行的对齐方式
struct FlowLayout: Layout {
    /// 每行的水平对齐
    enum Alignment {
        case leading
        case center
        case trailing
    }

    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var alignment: Alignment = .center

    /// 一个子视图及其尺寸
    private struct Item {
        let index: Int
        let size: CGSize
    }

    /// 把子视图按可用宽度分组
    private func groupedLines(subviews: Subviews, maxWidth: CGFloat) -> [[Item]] {
        var result: [[Item]] = []
        var current: [Item] = []
        var currentWidth: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = current.isEmpty ? size.width : currentWidth + spacing + size.width
            if !current.isEmpty && needed > maxWidth {
                result.append(current)
                current = [Item(index: index, size: size)]
                currentWidth = size.width
            } else {
                current.append(Item(index: index, size: size))
                currentWidth = needed
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func lineWidth(_ items: [Item]) -> CGFloat {
        guard let first = items.first else { return 0 }
        return items.dropFirst().reduce(first.size.width) { $0 + spacing + $1.size.width }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let groups = groupedLines(subviews: subviews, maxWidth: maxWidth)

        var height: CGFloat = 0
        for (index, group) in groups.enumerated() {
            height += group.map(\.size.height).max() ?? 0
            if index < groups.count - 1 { height += lineSpacing }
        }

        let widest = groups.map { lineWidth($0) }.max() ?? 0
        let width = maxWidth.isFinite ? min(maxWidth, widest) : widest
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let groups = groupedLines(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for group in groups {
            let lineHeight = group.map(\.size.height).max() ?? 0
            let width = lineWidth(group)
            var x: CGFloat
            switch alignment {
            case .leading:
                x = bounds.minX
            case .center:
                x = bounds.minX + (bounds.width - width) / 2
            case .trailing:
                x = bounds.maxX - width
            }

            for item in group {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (lineHeight - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }

            y += lineHeight + lineSpacing
        }
    }
}

/// 窄布局标记
///
/// 面板太窄时，标签与值上下排列比左右排列更易读。
/// 用环境值传递，避免把 `narrow` 参数一路传到每个子视图。
private struct NarrowLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 当前是否处于窄布局
    var isNarrowLayout: Bool {
        get { self[NarrowLayoutKey.self] }
        set { self[NarrowLayoutKey.self] = newValue }
    }
}
