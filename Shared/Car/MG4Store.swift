import Foundation

// ============================================================
// 共享存储 —— App Group 容器（App 与小组件读写同一份数据）
// ============================================================

enum SharedStore {
    /// App Group ID：来自 Info.plist 的 MG4WidgetGroup（见 SharedData.swift 的 CarAppGroupID），
    /// 正式版是 group.mg4widget，测试包是 group.mg4widget.test（两边容器隔离）。
    static let appGroupID = CarAppGroupID

    static let configKey = "mg4.config"
    static let snapshotKey = "mg4.snapshot"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// App Group 容器目录（用于缓存车辆图片等文件）
    static var containerURL: URL? {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        // 模拟器不发放共享容器：回退到 App 沙盒 Caches，便于本地验证去底渲染
        #if targetEnvironment(simulator)
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("mg4shared", isDirectory: true)
        #else
        return nil
        #endif
    }

    /// 确保容器目录存在（写缓存前调用）
    static func ensureContainerDirectory() {
        guard let url = containerURL else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // ---------- 配置 ----------

    static func loadConfig() -> AppConfig {
        guard let defaults,
              let data = defaults.data(forKey: configKey),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return AppConfig()
        }
        return cfg
    }

    static func saveConfig(_ config: AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults?.set(data, forKey: configKey)
        defaults?.synchronize()
    }

    // ---------- 车况快照 ----------

    static func loadSnapshot() -> VehicleSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: snapshotKey),
              let snap = try? JSONDecoder().decode(VehicleSnapshot.self, from: data) else {
            return nil
        }
        return snap
    }

    static func saveSnapshot(_ snapshot: VehicleSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
        defaults?.synchronize()
    }

    // ---------- 车辆图片缓存 ----------

    /// 车辆效果图缓存文件名（按颜色区分；回归 1.0.8 方案：直接存原图、不做后处理）
    static func carImageURL(color: String) -> URL? {
        containerURL?.appendingPathComponent("car_img_\(color).png")
    }

    // ---------- 电量历史（趋势）----------

    static let historyKey = "mg4.history"

    /// 单条历史：抓取时间 / 电量百分比 / 续航字符串
    struct HistoryPoint: Codable {
        let t: Date
        let battery: Int?
        let range: String?
    }

    static func loadHistory() -> [HistoryPoint] {
        guard let defaults,
              let data = defaults.data(forKey: historyKey),
              let h = try? JSONDecoder().decode([HistoryPoint].self, from: data) else { return [] }
        return h
    }

    /// 追加一条并裁剪到最近 50 条
    static func appendHistory(_ p: HistoryPoint) {
        guard let defaults else { return }
        var h = loadHistory()
        h.append(p)
        if h.count > 50 { h.removeFirst(h.count - 50) }
        if let data = try? JSONEncoder().encode(h) {
            defaults.set(data, forKey: historyKey)
            defaults.synchronize()
        }
    }

    // ---------- 未锁提醒状态（app 沙盒，勿与小组件共享）----------

    private static let pendingKey = "mg4.remind.pending"   // 上次抓取异常尚未提醒
    private static let lastKey = "mg4.remind.lastTime"     // 上次提醒时间

    static var remindPending: Bool { UserDefaults.standard.bool(forKey: pendingKey) }
    static func setRemindPending(_ v: Bool) { UserDefaults.standard.set(v, forKey: pendingKey) }

    static var lastRemindTime: Date? {
        UserDefaults.standard.object(forKey: lastKey) as? Date
    }
    static func markRemindedNow() {
        UserDefaults.standard.set(Date(), forKey: lastKey)
        UserDefaults.standard.set(false, forKey: pendingKey)
    }

    // ---------- 低电量提醒状态（app 沙盒；独立于未锁提醒的冷却）----------

    private static let lowLastKey = "mg4.lowbat.lastTime"

    /// 上次低电量提醒时间（20 分钟冷却）
    static var lastLowRemindTime: Date? {
        UserDefaults.standard.object(forKey: lowLastKey) as? Date
    }
    static func markLowRemindedNow() {
        UserDefaults.standard.set(Date(), forKey: lowLastKey)
    }
    /// 电量回升 / 进入充电后清除冷却，下次低电可立即再提醒
    static func clearLowReminder() {
        UserDefaults.standard.removeObject(forKey: lowLastKey)
    }
}
