import SwiftUI

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

// MARK: - 通用小组件视图
struct CardBox<Content: View>: View {
    var tint: Color = .clear
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct MetricChip: View {
    let name: String
    let color: Color
    var body: some View {
        Text(name)
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// 达成率进度环
struct RateRing: View {
    let rate: Double?   // 百分比数值
    var size: CGFloat = 88
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 9)
            if let rate {
                let p = min(max(rate / 100, 0), 1.3)
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(ringColor(rate), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(rate != nil ? "\(Int((rate ?? 0).rounded()))" : "—")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("%").font(.system(size: 11)).opacity(0.85)
            }
        }
        .frame(width: size, height: size)
    }
    func ringColor(_ r: Double) -> Color {
        if r >= 100 { return Color(red: 0.2, green: 0.78, blue: 0.35) }
        if r >= 80 { return .white }
        return .yellow
    }
}

// 品牌色
extension Color {
    static let brand = Color(red: 0x0A/255.0, green: 0x4D/255.0, blue: 0xE0/255.0)
    static let brandLight = Color(red: 0x35/255.0, green: 0xA7/255.0, blue: 1.0)
    static let brandTeal = Color(red: 0x3D/255.0, green: 0xF0/255.0, blue: 0xB4/255.0)
}

// 达成率在列表/统计中主色
extension Color {
    static func rateStatusColor(_ rate: Double?, over: Double = 100, warn: Double = 80) -> Color {
        guard let rate else { return .secondary }
        if rate >= over { return Color(red: 0.05, green: 0.65, blue: 0.42) }
        if rate >= warn { return .blue }
        return .orange
    }
}

// 月份图表数据辅助
struct ChartSerie: Identifiable {
    var id: String { monthKey }
    let monthKey: String
    let label: String
    let value: Double
    let value2: Double?  // 可选第二条线
}
