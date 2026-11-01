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

    // ---------- 最近一次原始响应（诊断页用）----------

    static let lastRawKey = "mg4.lastRaw"

    /// 只保留最近一次、截断到 60 KB：够看清结构，也不会把 App Group 撑大
    static func saveLastRaw(_ text: String) {
        defaults?.set(String(text.prefix(60_000)), forKey: lastRawKey)
    }

    static func loadLastRaw() -> String? {
        defaults?.string(forKey: lastRawKey)
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
    // ---------- 行驶 / 充电采样（自动统计的数据基础）----------

    static let samplesKey = "mg4.samples"
    static let autoRecordKey = "mg4.autoRecord"
    static let lastAutoSessionKey = "mg4.lastAutoSession"

    static func samples() -> [DriveSample] {
        guard let defaults, let data = defaults.data(forKey: samplesKey),
              let arr = try? JSONDecoder().decode([DriveSample].self, from: data) else { return [] }
        return arr
    }

    /// 追加一条采样：1 分钟内重复刷新只保留最新一条，总条数封顶（约 7 天）
    static func appendSample(_ s: DriveSample) {
        var arr = samples()
        if let last = arr.last, abs(s.t.timeIntervalSince(last.t)) < 60 {
            arr[arr.count - 1] = s
        } else {
            arr.append(s)
        }
        if arr.count > DriveStats.maxSamples {
            arr.removeFirst(arr.count - DriveStats.maxSamples)
        }
        if let data = try? JSONEncoder().encode(arr) {
            defaults?.set(data, forKey: samplesKey)
        }
    }

    /// 是否自动把「已结束的充电会话」写成充电记录（默认开）
    static var autoRecordEnabled: Bool {
        (defaults?.object(forKey: autoRecordKey) as? Bool) ?? true
    }
    static func setAutoRecord(_ on: Bool) {
        defaults?.set(on, forKey: autoRecordKey)
    }

    /// 上次自动记录的会话结束时间：用于去重，避免同一段充电反复写记录
    static func lastAutoSessionEnd() -> Date? {
        defaults?.object(forKey: lastAutoSessionKey) as? Date
    }
    static func setLastAutoSessionEnd(_ d: Date) {
        defaults?.set(d, forKey: lastAutoSessionKey)
    }
}


// ============================================================
// 行驶 / 充电采样与统计（自动记录的数据基础）
// ============================================================

/// 一次车况刷新留下的一条采样。字段刻意少而稳：只保留能推算出「行驶 / 掉电 / 充电」的最小集合。
struct DriveSample: Codable, Hashable {
    var t: Date
    var soc: Int?
    var rangeKm: Int?
    var odoKm: Int?
    var charging: Bool
    var chargeCode: Int?
    var lat: Double?
    var lng: Double?
    var address: String?

    init(snapshot s: VehicleSnapshot, at time: Date = Date()) {
        t = time
        soc = s.battery
        rangeKm = s.range.flatMap { Int($0) }
        odoKm = s.odometer
        charging = s.charging == true
        chargeCode = s.chargeStatusCode
        lat = s.lat
        lng = s.lng
        address = s.address
    }
}

/// 由采样序列推导出的充电会话（不落库，随时可重算）
struct ChargeSession: Hashable {
    var start: Date
    var end: Date
    var socStart: Int
    var socEnd: Int
    var address: String?
    /// 会话之后已经出现过「未充电」采样 → 这段充电结束了
    var isClosed: Bool
    /// 按 SOC 差 × 电池容量估算的充入电量（kWh）
    var kwh: Double
    var minutes: Double { max(0, end.timeIntervalSince(start)) / 60.0 }
}

enum DriveStats {
    /// 采样上限：约 7 天（按 5–15 分钟一次的刷新节奏）
    static let maxSamples = 2000

    /// 把采样切成充电会话；正在充的那段 isClosed = false，不自动记录
    static func sessions(_ samples: [DriveSample], packKWh: Double) -> [ChargeSession] {
        guard !samples.isEmpty else { return [] }
        var out: [ChargeSession] = []
        var i = 0
        while i < samples.count {
            guard samples[i].charging else { i += 1; continue }
            // 起点电量取「插枪前最后一次采样」，比会话内第一条更接近真实起点
            var socStart = samples[i].soc ?? 0
            if i > 0, let prev = samples[i - 1].soc { socStart = prev }
            var last = samples[i]
            var j = i
            while j < samples.count, samples[j].charging {
                last = samples[j]
                j += 1
            }
            let socEnd = last.soc ?? socStart
            let delta = max(0, socEnd - socStart)
            out.append(ChargeSession(start: samples[i].t,
                                     end: last.t,
                                     socStart: socStart,
                                     socEnd: socEnd,
                                     address: last.address,
                                     isClosed: j < samples.count,
                                     kwh: Double(delta) / 100.0 * max(packKWh, 0)))
            i = j
        }
        return out
    }

    /// 今日行驶里程（km）：今天采样里里程表的最大正差
    static func todayDistance(_ samples: [DriveSample], now: Date = Date()) -> Double? {
        let cal = Calendar.current
        let today = samples.filter { cal.isDate($0.t, inSameDayAs: now) }
            .compactMap { $0.odoKm.map(Double.init) }
        guard let lo = today.min(), let hi = today.max(), hi > lo else { return nil }
        return hi - lo
    }

    /// 停车掉电（%/天 与 kWh/天）。
    ///
    /// 只统计「真停车」的采样：相邻两条采样的里程表读数不变才算停车，
    /// 行驶中的掉电一律跳过（否则开车的消耗会被算成停车损耗）。
    /// 窗口默认 24 小时，跨度不足 2 小时不给值（样本太短没有意义）。
    static func parkedDropPerDay(_ samples: [DriveSample],
                                 packKWh: Double,
                                 hours: Double = 24,
                                 now: Date = Date()) -> (percentPerDay: Double, kwhPerDay: Double)? {
        let since = now.addingTimeInterval(-hours * 3600)
        let recent = samples.filter { !$0.charging && $0.t >= since && $0.soc != nil }
        guard recent.count >= 3 else { return nil }

        // 相邻两条里程表相同 → 两条都算「停着」
        var parked: [(Date, Int)] = []
        for i in recent.indices {
            let s = recent[i]
            guard let soc = s.soc else { continue }
            if i > 0, let a = recent[i - 1].odoKm, let b = s.odoKm, a != b { continue }
            parked.append((s.t, soc))
        }
        guard let first = parked.first, let last = parked.last else { return nil }
        let days = last.0.timeIntervalSince(first.0) / 86_400.0
        guard days > 2.0 / 24.0 else { return nil }   // 至少 2 小时
        let percent = Double(first.1 - last.1) / days
        guard percent > -20, percent < 60 else { return nil }   // 明显异常（如跨充电、跨校准）直接不给
        return (percent, percent / 100.0 * max(packKWh, 0))
    }

    /// 最近一次已结束的充电会话
    static func lastClosedSession(_ samples: [DriveSample], packKWh: Double) -> ChargeSession? {
        sessions(samples, packKWh: packKWh).last { $0.isClosed }
    }
}