import SwiftUI
import Foundation
import WidgetKit
import UserNotifications

// MARK: - 撤销模型
enum UndoKind: Int { case delete = 0, edit = 1 }
struct UndoOffer: Equatable {
    let kind: UndoKind
    let message: String
    let record: ChargeRecord
}

// MARK: - 全局 Store
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// 统一版本来源：直接读 Info.plist，避免多处硬编码导致版本漂移
    static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.3"
        let build = info?["CFBundleVersion"] as? String ?? "2"
        return "\(short) (\(build))"
    }

    @Published var vehicles: [Vehicle] = []
    @Published var records: [ChargeRecord] = []
    @Published var activeVehicleID: UUID?
    @Published var window: StatsWindow = .threeMonths
    @Published var selectedTab: AppTab = .records
    @Published var newRecordTick: Int = 0
    @Published var undoOffer: UndoOffer?
    @Published var cloudMessage: String?

    let pc = PersistenceController.shared
    private let ud = UserDefaults.standard
    private var observerTokens: [NSObjectProtocol] = []

    private init() {
        load()
        restorePrefs()   // 不自动注入示例数据：库为空则显示空态，由用户自行录入
        SharedData.writeMetric("cost")
        pushWidgetSnapshot()
        // 持久层加载完成 / 数据变更 → 刷新内存镜像
        let token = NotificationCenter.default.addObserver(
            forName: .EVDataChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        observerTokens.append(token)
    }

    // MARK: 读取
    func load() {
        vehicles = pc.fetchVehicles()
        records = pc.fetchRecords()
        restorePrefs()
    }

    private func restorePrefs() {
        if let idStr = ud.string(forKey: "activeVehicleID"), let id = UUID(uuidString: idStr),
           vehicles.contains(where: { $0.id == id }) {
            activeVehicleID = id
        } else {
            activeVehicleID = vehicles.first?.id
        }
        if let wRaw = ud.string(forKey: "statsWindow"), let w = StatsWindow(rawValue: wRaw) {
            window = w
        }
    }

    private func persistPrefs() {
        if let id = activeVehicleID { ud.set(id.uuidString, forKey: "activeVehicleID") }
        ud.set(window.rawValue, forKey: "statsWindow")
    }

    var activeVehicle: Vehicle? {
        vehicles.first { $0.id == activeVehicleID } ?? vehicles.first
    }

    func records(for vid: UUID?) -> [ChargeRecord] {
        guard let vid else { return [] }
        return records.filter { $0.vehicleID == vid }
    }

    func setActive(_ id: UUID) {
        activeVehicleID = id
        persistPrefs()
        pushWidgetSnapshot()
    }
    func setWindow(_ w: StatsWindow) {
        window = w
        persistPrefs()
        pushWidgetSnapshot()
    }

    // MARK: - 用户偏好（UserDefaults）
    // 记住上次桩型（“新记录”默认选择）
    var lastChargerType: Int16 {
        get { Int16(ud.integer(forKey: "lastChargerType")) }
        set { ud.set(Int(newValue), forKey: "lastChargerType") }
    }
    // 月预算（¥；0 = 未设置）
    var monthlyBudget: Double {
        get { ud.double(forKey: "monthlyBudget") }
        set { ud.set(newValue, forKey: "monthlyBudget") }
    }
    var hasBudget: Bool { monthlyBudget > 0 }

    // MARK: - 温度标签（UserDefaults 元数据，避免 Core Data 模型迁移风险）
    private var tempDict: [String: Int] {
        get { (ud.dictionary(forKey: "recordTempC") as? [String: Int]) ?? [:] }
        set { ud.set(newValue, forKey: "recordTempC") }
    }
    func tempC(for recordID: UUID) -> Int? {
        tempDict[recordID.uuidString]
    }
    func setTempC(_ t: Int?, for recordID: UUID) {
        var d = tempDict
        if let t { d[recordID.uuidString] = t } else { d.removeValue(forKey: recordID.uuidString) }
        tempDict = d
    }
    func deleteTemp(for recordID: UUID) { setTempC(nil, for: recordID) }

    // MARK: - 写入
    @discardableResult
    func saveVehicle(_ v: Vehicle) -> Bool {
        let ok = pc.upsertVehicle(v)
        load()
        if activeVehicle == nil { activeVehicleID = v.id; persistPrefs() }
        pushWidgetSnapshot()
        objectWillChange.send()
        return ok
    }

    @discardableResult
    func deleteVehicle(_ id: UUID) -> Bool {
        guard records.first(where: { $0.vehicleID == id }) == nil else { return false }
        let ok = pc.delete(entity: "Vehicle", id: id)
        if activeVehicleID == id { activeVehicleID = nil }
        load(); persistPrefs()
        pushWidgetSnapshot()
        return ok
    }

    @discardableResult
    func saveRecord(_ r: ChargeRecord) -> Bool {
        let ok = pc.upsertRecord(r)
        load()
        pushWidgetSnapshot()
        autoBackup()
        checkBudgetAlertIfNeeded()
        objectWillChange.send()
        return ok
    }

    @discardableResult
    func saveRecordQuiet(_ r: ChargeRecord) -> Bool {
        let ok = pc.upsertRecord(r)
        if ok {
            load()
            pushWidgetSnapshot()
            autoBackup()
            objectWillChange.send()
        }
        return ok
    }

    @discardableResult
    func deleteRecord(_ id: UUID) -> Bool {
        deleteTemp(for: id)
        let ok = pc.delete(entity: "ChargeRecord", id: id)
        if ok {
            load()
            pushWidgetSnapshot()
            autoBackup()
            objectWillChange.send()
        }
        return ok
    }

    func eraseAll() {
        pc.deleteAll()
        ud.removeObject(forKey: "activeVehicleID")
        tempDict = [:]
        load()
        pushWidgetSnapshot()
        autoBackup()
    }

    // MARK: - 撤销（编辑 & 删除统一入口）
    func offerUndo(kind: UndoKind, message: String, record: ChargeRecord) {
        undoOffer = UndoOffer(kind: kind, message: message, record: record)
    }
    func undoLast() {
        guard let offer = undoOffer else { return }
        let ok = saveRecordQuiet(offer.record)   // 编辑→还原旧版；删除→upsert 恢复
        undoOffer = nil
        if ok {
            cloudMessage = offer.kind == .delete ? "已撤销删除" : "已撤销本次修改"
            scheduleMessageClear()
        } else {
            cloudMessage = "撤销失败：存储写入出错"
            scheduleMessageClear()
        }
    }
    private var clearTask: Task<Void, Never>?
    func scheduleMessageClear() {
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { cloudMessage = nil }
        }
    }

    // MARK: - 预算 / 本地通知（失败静默；权限被拒→忽略）
    func currentMonthCostCNY() -> Double {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let month = cal.dateInterval(of: .month, for: now)!
        return records.filter { month.contains($0.date) }.reduce(0) { $0 + $1.costCNY }
    }
    func currentMonthKey() -> String { Date().monthKey }
    func requestNotifyAuthIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    private func checkBudgetAlertIfNeeded() {
        guard hasBudget else { return }
        let cost = currentMonthCostCNY()
        guard cost >= monthlyBudget else { return }
        let flagKey = "budgetNotified-\(currentMonthKey())"
        guard !ud.bool(forKey: flagKey) else { return }
        ud.set(true, forKey: flagKey)
        let content = UNMutableNotificationContent()
        content.title = "电车助手 · 预算提醒"
        content.body = String(format: "本月充电费 ¥%.0f 已达到预算 ¥%.0f，注意控制用车成本。", cost, monthlyBudget)
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString,
                                                                      content: content, trigger: trigger))
    }
    func resetBudgetNotifyFlagForNewMonth() {
        // 跨月自动重置：写操作时若月份变化则删除上月标记
        let k = "budgetNotifiedMonth"
        let last = ud.string(forKey: k)
        let cur = currentMonthKey()
        if last != cur {
            ud.removeObject(forKey: "budgetNotified-\(last ?? "")")
            ud.set(cur, forKey: k)
        }
    }

    // MARK: - CSV 生成 / 自动备份 / 恢复
    /// 生成当前车辆完整 CSV（列与「从备份恢复」解析一致）
    func makeCSV(for v: Vehicle) -> String {
        let rows = Calculator.derivedRows(records, for: v.id)
        let df = DateFormatter(); df.locale = Locale(identifier: "zh_CN"); df.dateFormat = "yyyy-MM-dd"
        var lines = ["日期,车辆,桩类型,充电量kWh,金额CNY,里程表读数km,行驶里程km,百公里电耗,每公里成本元/km,充电前SOC,充电后SOC,备注"]
        for row in rows {
            let r = row.record
            let ct = ChargerType(rawValue: r.chargerType)?.name ?? ""
            let cells = [
                df.string(from: r.date), v.name, ct,
                Fmt.dec(r.energyKWh, 1), Fmt.dec(r.costCNY, 2), Fmt.dec(r.odometerKm, 0),
                row.valid ? Fmt.dec(row.distanceKm, 1) : "",
                row.consumption != nil ? Fmt.dec(row.consumption, 1) : "",
                row.costPerKm != nil ? Fmt.dec(row.costPerKm, 2) : "",
                r.socBefore != nil ? Fmt.int(r.socBefore!) : "",
                r.socAfter != nil ? Fmt.int(r.socAfter!) : "",
                r.note
            ]
            lines.append(cells.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))
        }
        return "\u{FEFF}" + lines.joined(separator: "\n")
    }

    /// 每次写操作后的本地自动备份（滚动保留最近 10 份）
    func autoBackup() {
        guard let v = activeVehicle else { return }
        let dir = PersistenceController.backupDir
        let df = DateFormatter(); df.locale = Locale(identifier: "zh_CN"); df.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = df.string(from: Date())
        let url = dir.appendingPathComponent("EVLogger_\(stamp).csv")
        do {
            try makeCSV(for: v).write(to: url, atomically: true, encoding: .utf8)
            let all = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            let csv = all.filter { $0.pathExtension == "csv" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            if csv.count > 10 { csv.dropFirst(10).forEach { try? FileManager.default.removeItem(at: $0) } }
        } catch {
            NSLog("autoBackup failed: \(error)")
        }
    }

    /// 从备份 CSV 导入（按 车辆名 + 日期 + 里程 去重）
    func importBackup(data: Data) -> (imported: Int, skipped: Int, error: String?) {
        resetBudgetNotifyFlagForNewMonth()
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16) else { return (0, 0, "无法解析备份文件编码") }
        let lines = text.split(whereSeparator: \.isNewline).dropFirst() // 跳表头
        let df = DateFormatter(); df.locale = Locale(identifier: "zh_CN"); df.dateFormat = "yyyy-MM-dd"
        var imported = 0, skipped = 0
        for raw in lines {
            // 简单 CSV 解析：处理引号包裹的备注
            let tokens = csvParse(String(raw))
            guard tokens.count >= 12,
                  let date = df.date(from: tokens[0]),
                  let energy = Double(tokens[3]),
                  let cost = Double(tokens[4]),
                  let odo = Double(tokens[5])
            else { skipped += 1; continue }
            let vehicleName = tokens[1]
            let type: Int16 = ["家充": 0, "快充": 1, "慢充": 2][tokens[2]] ?? 0
            let sb = Double(tokens[9]).map { $0 > 0 ? $0 : nil } ?? nil
            let sa = Double(tokens[10]).map { $0 > 0 ? $0 : nil } ?? nil
            let note = tokens[11]
            // 车辆：按名匹配，否则按当前车，否则新建
            var v = vehicles.first { $0.name == vehicleName }
            if v == nil { v = activeVehicle }
            if v == nil {
                let nv = Vehicle(id: UUID(), name: vehicleName.isEmpty ? "导入车辆" : vehicleName,
                                 ratedRangeKm: 550, rangeStandard: 0, batteryKWh: 60, usableKWh: nil, createdAt: Date())
                if !saveVehicle(nv) { skipped += 1; continue }
                v = nv
            }
            guard let v else { skipped += 1; continue }
            // 去重：同车 同日期 同里程
            let dup = records.contains { $0.vehicleID == v.id && Calendar.current.isDate($0.date, inSameDayAs: date) && $0.odometerKm == odo }
            if dup { skipped += 1; continue }
            let rec = ChargeRecord(id: UUID(), vehicleID: v.id, date: date, odometerKm: odo,
                                   energyKWh: energy, costCNY: cost, chargerType: type,
                                   socBefore: sb, socAfter: sa, note: note, createdAt: Date())
            if saveRecordQuiet(rec) { imported += 1 } else { skipped += 1 }
        }
        return (imported, skipped, nil)
    }

    private func csvParse(_ line: String) -> [String] {
        var out: [String] = []
        var cur = "", inQ = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if inQ {
                if c == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" { cur.append("\""); i = next }
                    else { inQ = false }
                } else { cur.append(c) }
            } else {
                if c == "\"" { inQ = true }
                else if c == "," { out.append(cur); cur = "" }
                else { cur.append(c) }
            }
            i = line.index(after: i)
        }
        out.append(cur)
        return out
    }

    // MARK: - 示例数据（仅首次安装空库自动触发）
    // MARK: - Widget 快照
    func pushWidgetSnapshot() {
        let v = activeVehicle
        let rows = v.map { Calculator.derivedRows(records, for: $0.id) } ?? []
        let totals = Calculator.totals(rows)
        let a = v.flatMap { Calculator.rangeRateA(rows: rows, vehicle: $0, window: window) }
        let cm = Date().monthKey
        let m0 = Calculator.monthSeries(rows).first { $0.monthKey == cm }
        let snap = WidgetSnapshot(
            appVersion: "电车助手 v\(Self.appVersionString)",
            generatedAt: Date(),
            hasData: !rows.isEmpty,
            vehicleName: v?.name,
            totalDistanceKm: totals.dist,
            totalCostCNY: totals.costAll,
            totalEnergyKWh: totals.energyAll,
            avgConsumption: totals.avgConsumption ?? 0,
            avgCostPerKm: totals.avgCostPerKm ?? 0,
            monthCostCNY: m0?.cost ?? 0,
            monthEnergyKWh: m0?.energyAll ?? 0,
            rangeRatePercent: a?.rate ?? 0,
            windowLabel: window.name,
            windowMonthsBack: window.sinceStartOfMonthBack,
            cost6: last6Cost(),
            rate6: last6Rate(v, rows)
        )
        SharedData.writeSnapshot(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func last6Cost() -> [MonthlyMini] {
        let v = activeVehicle
        let rows = v.map { Calculator.derivedRows(records, for: $0.id) } ?? []
        let series = Calculator.monthSeries(rows)
        let cal = Calendar.current
        let now = Date()
        var out: [MonthlyMini] = []
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yy年M月"
        for k in (0..<6).reversed() {
            let d = cal.date(byAdding: .month, value: -k, to: now) ?? now
            let key = d.monthKey
            let m = series.first { $0.monthKey == key }
            out.append(MonthlyMini(label: f.string(from: d), value: m?.cost ?? 0))
        }
        return out
    }

    private func last6Rate(_ v: Vehicle?, _ rows: [DerivedRow]) -> [MonthlyMini] {
        guard let v = v, v.ratedRangeKm > 0 else { return [] }
        let series = Calculator.monthSeries(rows)
        let cal = Calendar.current
        let now = Date()
        var out: [MonthlyMini] = []
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yy年M月"
        let usable = v.effectiveUsableKWh
        for k in (0..<6).reversed() {
            let d = cal.date(byAdding: .month, value: -k, to: now) ?? now
            let key = d.monthKey
            let m = series.first { $0.monthKey == key }
            if let m, let c = m.consumption, c > 0 {
                let r = usable / c * 100 / v.ratedRangeKm * 100
                out.append(MonthlyMini(label: f.string(from: d), value: r))
            } else {
                out.append(MonthlyMini(label: f.string(from: d), value: 0))
            }
        }
        return out
    }

    // MARK: - 全量备份 / 恢复

    /// 把全部车辆、记录、温度标签与预算编码成一个 JSON 备份
    func makeFullBackup() -> Data? {
        var payload = BackupPayload()
        payload.appVersion = Self.appVersionString
        payload.vehicles = vehicles
        payload.records = records
        payload.temperatures = tempDict
        payload.monthlyBudget = hasBudget ? monthlyBudget : nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(payload)
    }

    /// 恢复：JSON 走全量合并（按 id 去重），旧版 CSV 备份继续走 importBackup
    @discardableResult
    func restoreBackup(from data: Data) -> (imported: Int, skipped: Int, error: String?) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: data) else {
            return importBackup(data: data)
        }
        var imported = 0
        var skipped = 0
        for vehicle in payload.vehicles {
            if vehicles.contains(where: { $0.id == vehicle.id }) { skipped += 1; continue }
            if saveVehicle(vehicle) { imported += 1 } else { skipped += 1 }
        }
        for record in payload.records {
            if self.records.contains(where: { $0.id == record.id }) { skipped += 1; continue }
            if saveRecordQuiet(record) { imported += 1 } else { skipped += 1 }
        }
        for (key, value) in payload.temperatures {
            if let id = UUID(uuidString: key), tempC(for: id) == nil { setTempC(value, for: id) }
        }
        if let budget = payload.monthlyBudget, budget > 0, !hasBudget { monthlyBudget = budget }
        load()
        pushWidgetSnapshot()
        return (imported, skipped, nil)
    }

    // MARK: - 本机自动备份（沙盒 CSV，滚动 10 份）

    func autoBackupFiles() -> [URL] {
        let dir = PersistenceController.backupDir
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "csv" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    @discardableResult
    func restoreFile(_ url: URL) -> (imported: Int, skipped: Int, error: String?) {
        guard let data = try? Data(contentsOf: url) else { return (0, 0, "无法读取该文件") }
        return restoreBackup(from: data)
    }

    func deleteAutoBackup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
