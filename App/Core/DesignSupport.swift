import SwiftUI
import UIKit

// MARK: - 格式化
enum Fmt {
    static func dec(_ v: Double?, _ dp: Int = 1) -> String {
        guard let v = v, v.isFinite else { return "—" }
        return String(format: "%.\(dp)f", v)
    }
    static func yuan(_ v: Double?) -> String {
        guard let v = v, v.isFinite else { return "—" }
        if v >= 100 { return "¥" + String(format: "%.0f", v) }
        return "¥" + String(format: "%.1f", v)
    }
    static func int(_ v: Double?) -> String {
        guard let v = v, v.isFinite else { return "—" }
        return String(Int(v.rounded()))
    }
    static func intStr(_ v: Double?) -> String {
        guard let v = v, v.isFinite else { return "—" }
        return String(format: "%.0f", v)
    }
}

extension Date {
    var monthKey: String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents([.year, .month], from: self)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
    func zhDay() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: self)
    }
    func zhMonth() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f.string(from: self)
    }
    func isoDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}

// 品牌色
extension Color {
    static let brand = Color(red: 0x0A/255.0, green: 0x4D/255.0, blue: 0xE0/255.0)
}

// MARK: - 设计令牌 · 尺寸
/// 一屏里的主要容器只允许两种圆角，不再 12/16/18 混用
enum Radius {
    /// 卡片
    static let card: CGFloat = 20
    /// 卡内容器（提示条、内嵌块）
    static let inner: CGFloat = 12
}

enum Space {
    /// 页面左右边距
    static let page: CGFloat = 16
    /// 卡片内边距
    static let card: CGFloat = 16
    /// 卡片之间
    static let gap: CGFloat = 12
}

// MARK: - 设计令牌 · 颜色
/// 语义色：全 App 只认 brand / ok / warn / danger 四个，浅色与暗色各一套值，
/// 由系统外观自动切换——避免「同一屏里两个蓝不是同一个蓝」。
extension UIColor {
    convenience init(dsHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    static func dsAdaptive(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(dsHex: dark) : UIColor(dsHex: light) }
    }
}

extension Color {
    private static func dsDynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor.dsAdaptive(light: light, dark: dark))
    }

    /// 正常 / 通过 / 已锁
    static let dsOK = dsDynamic(light: 0x12A150, dark: 0x30D158)
    /// 提醒 / 未关 / 达成率 80–100%
    static let dsWarn = dsDynamic(light: 0xF59E0B, dark: 0xFFB020)
    /// 危险 / 异常 / 达成率 < 80%
    static let dsDanger = dsDynamic(light: 0xE5484D, dark: 0xFF6B6B)
    /// 分隔线与描边
    static let dsStroke = dsDynamic(light: 0xE5E5EA, dark: 0x2C2C2E)
}

extension View {
    /// 统一卡片容器：圆角 + 分组底色 +（可选）1px 描边。暗色下靠描边而不是阴影分隔。
    func dsCard(radius: CGFloat = Radius.card,
                fill: Color = Color(.secondarySystemGroupedBackground),
                stroke: Color? = nil) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                }
            }
    }
}

// 达成率在列表/统计中主色
extension Color {
    static func rateStatusColor(_ rate: Double?, over: Double = 100, warn: Double = 80) -> Color {
        guard let rate else { return .secondary }
        if rate >= over { return .dsOK }
        if rate >= warn { return .dsWarn }
        return .dsDanger
    }
}

// MARK: - 自动换行排布（iOS 16 Layout）

/// 会自动折行的水平排布。用途是「胶囊流」：一串短标签按可用宽度排列，
/// 放不下就折到下一行。相比 `HStack` 它不会被压扁，相比 `LazyVGrid` 它不会
/// 硬排出看不见的列——宽度变化、动态字号变大时都能自然适应。
struct WrapLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = lines.reduce(0) { $0 + $1.height }
            + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let width = lines.map(\.width).max() ?? 0
        return CGSize(width: width.isFinite ? min(width, maxWidth) : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let widthIfAppended = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width
            if !current.indices.isEmpty && widthIfAppended > maxWidth {
                lines.append(current)
                current = Line(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = widthIfAppended
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}