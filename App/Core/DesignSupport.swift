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

// 品牌色
extension Color {
    static let brand = Color(red: 0x0A/255.0, green: 0x4D/255.0, blue: 0xE0/255.0)
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
