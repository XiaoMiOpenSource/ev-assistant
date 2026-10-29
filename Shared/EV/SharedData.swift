import Foundation

// 共享 · 小组件 DTO
// 双方 target（主 App / Widget Extension）各放一份同源副本，避免跨 target 文件系统同步组冲突。
// 写入端：主 App 在每次数据变更后序列化写入 App Group UserDefaults；
// 读取端：Widget 通过 TimelineProvider 读取并渲染。

/// App Group 从 Info.plist 读（值来自 project.yml 的 MG4_APP_GROUP / MG4_WIDGET_GROUP）。
/// 读不到、为空、或构建设置没展开（还留着 "$(" 字面量）时回落到仓库默认值 ——
/// 这样无论是 Xcode 直接编、脚本编，还是别的打包方式，都不会突然读不到容器。
private func appGroupFromPlist(_ key: String, fallback: String) -> String {
    if let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String {
        let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty, !v.contains("$(") { return v }
    }
    return fallback
}

/// 电耗数据（小组件快照 / 主指标）所在的 group
let AppGroupID = appGroupFromPlist("MG4AppGroup", fallback: "group.com.evstats.EVLogger")
/// 车况数据（接口地址、车辆快照、历史曲线）所在的 group
let CarAppGroupID = appGroupFromPlist("MG4WidgetGroup", fallback: "group.mg4widget")
let WidgetSnapshotKey = "evstats.snapshot.v1"
let WidgetMetricKey = "evstats.widgetMetric.v1"   // "cost" | "rate" | "cons"

struct WidgetSnapshot: Codable, Hashable {
    let appVersion: String
    let generatedAt: Date
    let hasData: Bool
    let vehicleName: String?
    let totalDistanceKm: Double
    let totalCostCNY: Double
    let totalEnergyKWh: Double
    let avgConsumption: Double     // kWh/100km
    let avgCostPerKm: Double       // CNY/km
    let monthCostCNY: Double
    let monthEnergyKWh: Double
    let rangeRatePercent: Double   // 0..n
    let windowLabel: String
    let windowMonthsBack: Int      // 0..12
    // 关键 6 月历史（柱状 + 达成率折线）—— 直接喂给小组件，Widget 不再读 Core Data
    let cost6: [MonthlyMini]
    let rate6: [MonthlyMini]
}

struct MonthlyMini: Codable, Hashable {
    let label: String  // "26年6月"
    let value: Double
}

enum SharedData {
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupID)
    }

    /// 主 App 写入（每次派生数据变化时）
    static func writeSnapshot(_ snap: WidgetSnapshot) {
        guard let d = defaults else { return }
        if let data = try? JSONEncoder().encode(snap) {
            d.set(data, forKey: WidgetSnapshotKey)
        }
    }

    /// 双方读取（Widget 调用）
    static func readSnapshot() -> WidgetSnapshot? {
        guard let d = defaults,
              let data = d.data(forKey: WidgetSnapshotKey)
        else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func readMetric() -> String {
        defaults?.string(forKey: WidgetMetricKey) ?? "cost"
    }
    static func writeMetric(_ m: String) {
        defaults?.set(m, forKey: WidgetMetricKey)
    }
}
