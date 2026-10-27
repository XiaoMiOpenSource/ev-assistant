import Foundation

// MARK: - 派生计算引擎（纯函数、可单测；口径与蓝图/Web 原型一致）

enum RowKind { case first, ok, rollback, pending }

struct DerivedRow {
    let record: ChargeRecord
    let kind: RowKind
    let distanceKm: Double?       // 本笔行驶里程 = 本次读数 − 上一笔读数
    let consumption: Double?      // kWh/100km（含充电损耗）
    let costPerKm: Double?        // 元/km（合并区间时使用合计费用 ÷ 合计里程）
    /// 配对统计使用的充电量/费用；合并区间在最后一笔一次计入，避免漏算或重复。
    let pairedEnergyKWh: Double
    let pairedCostCNY: Double
    /// 合并区间的总里程；nil 表示普通单笔区间，待累计行也没有已完成区间。
    let groupDistanceKm: Double?
    var isAggregated: Bool { groupDistanceKm != nil }
    /// 短区间暂不与充电量配对；里程仍计入总里程，等后续记录一起结算。
    var isPending: Bool { kind == .pending }
    var valid: Bool { distanceKm != nil && distanceKm! > 0 }

    /// 隐含电耗的可信区间（kWh/100km）。漏记一次充电会让区间里程虚增、
    /// 隐含电耗掉到 3–4，从而把达成率抬到 150% 以上——这类行不能进效率统计。
    static let plausibleRange: ClosedRange<Double> = 5...40

    /// 隐含电耗是否可信（有里程、有电耗、且落在合理区间）
    var plausible: Bool {
        guard let c = consumption else { return false }
        return DerivedRow.plausibleRange.contains(c)
    }

    /// 可参与充电量-里程效率聚合的行；SOC 续航口径独立检查自己的数据。
    var countable: Bool { valid && plausible }
}

enum Calculator {

    // 升序派生：里程表必填，首笔为基准；里程回退（负差）自动过滤
    static func derivedRows(_ records: [ChargeRecord], for vehicleID: UUID) -> [DerivedRow] {
        let recs = records
            .filter { $0.vehicleID == vehicleID }
            .sorted { a, b in
                if a.date != b.date { return a.date < b.date }
                return a.createdAt < b.createdAt
            }
        var rows: [DerivedRow] = []
        var prevOdo: Double?
        for (i, r) in recs.enumerated() {
            var dist: Double?
            var kind: RowKind = .first
            var cons: Double?
            var ckm: Double?
            if let prev = prevOdo, i > 0 {
                let d = r.odometerKm - prev
                if d > 0 {
                    dist = d
                    kind = .ok
                    if r.energyKWh > 0 { cons = r.energyKWh / d * 100 }
                    if r.costCNY > 0 { ckm = r.costCNY / d }
                } else if d < 0 { kind = .rollback }
            }
            rows.append(DerivedRow(record: r, kind: kind, distanceKm: dist, consumption: cons, costPerKm: ckm,
                                   pairedEnergyKWh: 0, pairedCostCNY: 0, groupDistanceKm: nil))
            // 里程回退多半是录入错误：保留原基准，避免下一笔里程被虚增
            if r.odometerKm.isFinite, kind != .rollback { prevOdo = r.odometerKm }
        }
        // 刚充完又充一次时，两次读数可能只差几公里。把整笔充电量除以这
        // 几公里会产生几百 kWh/100km 的假高电耗。失真短区间只与相邻区间
        // 按“充电量合计 ÷ 里程合计”计算，不跨正常记录，也不隐藏真实高电耗。
        let minimumDistanceKm = 30.0
        let shortOutliers = Set(rows.indices.filter { i in
            guard rows[i].valid, let distance = rows[i].distanceKm,
                  distance < minimumDistanceKm, let consumption = rows[i].consumption
            else { return false }
            return !DerivedRow.plausibleRange.contains(consumption)
        })
        var groups: [(indices: ClosedRange<Int>, settle: Int)] = []
        var i = 0
        while i < rows.count {
            guard shortOutliers.contains(i) else { i += 1; continue }
            let start = i
            while i + 1 < rows.count, shortOutliers.contains(i + 1) { i += 1 }
            if i + 1 < rows.count, rows[i + 1].valid {
                groups.append((start...(i + 1), i + 1))
                i += 2 // 结算行不能被后续短区间再次占用
            } else {
                i += 1
            }
        }
        // 反向处理没有下一笔的短区间；不与已完成的组合重叠。
        i = rows.count - 1
        while i >= 0 {
            if shortOutliers.contains(i), !groups.contains(where: { $0.indices.contains(i) }) {
                var start = i
                while start > 0, shortOutliers.contains(start - 1),
                      !groups.contains(where: { $0.indices.contains(start - 1) }) { start -= 1 }
                if start > 0, rows[start - 1].valid,
                   !groups.contains(where: { $0.indices.contains(start - 1) }) {
                    groups.append(((start - 1)...i, start - 1))
                }
            }
            i -= 1
        }
        for group in groups {
            let indices = group.indices
            let distance = indices.reduce(0.0) { $0 + (rows[$1].distanceKm ?? 0) }
            let energy = indices.reduce(0.0) { $0 + rows[$1].record.energyKWh }
            let cost = indices.reduce(0.0) { $0 + rows[$1].record.costCNY }
            for index in indices where index != group.settle {
                rows[index] = DerivedRow(record: rows[index].record, kind: .pending,
                                         distanceKm: rows[index].distanceKm,
                                         consumption: nil, costPerKm: nil,
                                         pairedEnergyKWh: 0, pairedCostCNY: 0, groupDistanceKm: nil)
            }
            rows[group.settle] = DerivedRow(record: rows[group.settle].record, kind: .ok,
                                            distanceKm: rows[group.settle].distanceKm,
                                            consumption: energy > 0 ? energy / distance * 100 : nil,
                                            costPerKm: cost > 0 ? cost / distance : nil,
                                            pairedEnergyKWh: energy, pairedCostCNY: cost,
                                            groupDistanceKm: distance)
        }
        return rows
    }

    // 月度序列：合并区间的配对电量/里程在结算记录所在月份计入；费用与总充电量仍按原记录月份统计。
    struct MonthPoint: Identifiable {
        var id: String { monthKey }
        let monthKey: String // "2026-06"
        let energyPair: Double   // 可信区间充电量
        let distPair: Double     // 可信区间里程（算电耗用）
        let distAll: Double      // 全部有效里程（展示用，含被排除的可疑区间）
        let cost: Double         // 当月全部花费
        let energyAll: Double    // 当月全部充电量
        var consumption: Double? { distPair > 0 ? energyPair / distPair * 100 : nil }
        var monthLabel: String { monthKey }
    }

    static func monthSeries(_ rows: [DerivedRow]) -> [MonthPoint] {
        var map: [String: (e: Double, d: Double, z: Double, c: Double, ea: Double)] = [:]
        let cal = Calendar(identifier: .gregorian)
        for row in rows {
            let comps = cal.dateComponents([.year, .month], from: row.record.date)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            var m = map[key] ?? (0, 0, 0, 0, 0)
            if row.countable {
                m.e += row.isAggregated ? row.pairedEnergyKWh : row.record.energyKWh
                m.d += row.distanceKm ?? 0
            }
            if row.valid { m.z += row.distanceKm ?? 0 }
            m.c += row.record.costCNY
            m.ea += row.record.energyKWh
            map[key] = m
        }
        return map.keys.sorted().map { key in
            let m = map[key]!
            return MonthPoint(monthKey: key, energyPair: m.e, distPair: m.d, distAll: m.z, cost: m.c, energyAll: m.ea)
        }
    }

    // 窗口内平均电耗（口径 A 依赖）
    static func weightAvg(_ rows: [DerivedRow], window: StatsWindow, now: Date = Date()) -> (cons: Double, E: Double, D: Double)? {
        let set = windowRows(rows, window: window, now: now).filter { $0.countable }
        let E = set.reduce(0) { $0 + ($1.isAggregated ? $1.pairedEnergyKWh : $1.record.energyKWh) }
        let D = set.reduce(0) { $0 + ($1.distanceKm ?? 0) }
        if D <= 0 { return nil }
        return (E / D * 100, E, D)
    }

    // MARK: 口径 A（能耗换算法）——
    // 实际续航 = usable ÷ 平均百公里电耗 × 100；达成率 = 实际 ÷ 标称 × 100%
    struct RangeRateResult {
        let actualRangeKm: Double
        let rate: Double      // 百分比数值，如 92.5
        let usableKWh: Double
        let avgConsumption: Double
    }

    static func rangeRateA(rows: [DerivedRow], vehicle: Vehicle, window: StatsWindow, now: Date = Date()) -> RangeRateResult? {
        guard vehicle.ratedRangeKm > 0 else { return nil }
        let valid = windowRows(rows, window: window, now: now).filter { $0.countable }
        let sumE = valid.reduce(0) { $0 + ($1.isAggregated ? $1.pairedEnergyKWh : $1.record.energyKWh) }
        let sumD = valid.reduce(0) { $0 + ($1.distanceKm ?? 0) }
        guard sumD > 0, sumE > 0 else { return nil }
        let avgCons = sumE / sumD * 100
        let usable = vehicle.effectiveUsableKWh
        guard usable > 0, avgCons > 0 else { return nil }
        let actual = usable / avgCons * 100
        return RangeRateResult(actualRangeKm: actual, rate: actual / vehicle.ratedRangeKm * 100, usableKWh: usable, avgConsumption: avgCons)
    }

    // MARK: 口径 B（满充区间法）——上一笔充电后 ≥90% 且本笔记录了充电前电量
    struct RangeBCycle {
        let dist: Double
        let dropPts: Double
        let equivalentKm: Double
        let rate: Double
        let from: Date
        let to: Date
    }
    static func rangeBCycles(rows: [DerivedRow], vehicle: Vehicle) -> (cycles: [RangeBCycle], avgRate: Double?) {
        var cycles: [RangeBCycle] = []
        guard vehicle.ratedRangeKm > 0 else { return ([], nil) }
        for i in 1..<rows.count {
            let prev = rows[i - 1], cur = rows[i]
            guard cur.valid, !cur.isPending, !cur.isAggregated,
                  let after = prev.record.socAfter, after >= 90,
                  let before = cur.record.socBefore, before >= 0,
                  before < after,
                  let dist = cur.distanceKm, dist > 0
            else { continue }
            let drop = after - before
            guard drop >= 5, drop <= 100 else { continue }
            let eq = dist / drop * 100
            cycles.append(RangeBCycle(dist: dist, dropPts: drop, equivalentKm: eq, rate: eq / vehicle.ratedRangeKm * 100, from: prev.record.date, to: cur.record.date))
        }
        let avg = cycles.isEmpty ? nil : cycles.reduce(0) { $0 + $1.rate } / Double(cycles.count)
        return (cycles, avg)
    }

    static func windowRows(_ rows: [DerivedRow], window: StatsWindow, now: Date) -> [DerivedRow] {
        switch window {
        case .all:
            return rows
        case .threeMonths:
            let cal = Calendar(identifier: .gregorian)
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: cal.component(.month, from: now) - 2, day: 1)) ?? now
            return rows.filter { $0.record.date >= start }
        case .currentMonth:
            let cal = Calendar(identifier: .gregorian)
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: cal.component(.month, from: now), day: 1)) ?? now
            return rows.filter { $0.record.date >= start }
        }
    }

    // 汇总
    struct Totals {
        let costAll: Double
        let energyAll: Double
        let dist: Double            // 全部有效区间里程（累计里程用）
        let energyPair: Double      // 可信区间的充电量
        let consDist: Double        // 可信区间的里程
        let count: Int
        var avgConsumption: Double? { consDist > 0 ? energyPair / consDist * 100 : nil }
        var avgCostPerKm: Double? { dist > 0 ? costAll / dist : nil }
        fileprivate let rows: [DerivedRow]
    }
    // MARK: 续航达成率
    /// 单笔达成率（%）= 本笔行驶里程 ÷ 车标称续航 × 100；缺标称续航或里程返回 nil（UI 显示「—」）
    static func rowRangeRate(_ row: DerivedRow, ratedRangeKm: Double) -> Double? {
        guard ratedRangeKm > 0, let d = row.distanceKm, d > 0, d.isFinite else { return nil }
        return d / ratedRangeKm * 100
    }
    /// 按月份闭区间过滤（"yyyy-MM" 字符串比较）
    static func rows(_ rows: [DerivedRow], from start: String, to end: String) -> [DerivedRow] {
        rows.filter { r in
            let k = r.record.date.monthKey
            return (start.isEmpty || k >= start) && (end.isEmpty || k <= end)
        }
    }

    static func totals(_ rows: [DerivedRow]) -> Totals {
        let valid = rows.filter { $0.valid }
        let countable = rows.filter { $0.countable }
        return Totals(
            costAll: rows.reduce(0) { $0 + $1.record.costCNY },
            energyAll: rows.reduce(0) { $0 + $1.record.energyKWh },
            dist: valid.reduce(0) { $0 + ($1.distanceKm ?? 0) },
            energyPair: countable.reduce(0) { $0 + ($1.isAggregated ? $1.pairedEnergyKWh : $1.record.energyKWh) },
            consDist: countable.reduce(0) { $0 + ($1.distanceKm ?? 0) },
            count: rows.count,
            rows: valid
        )
    }
}

// MARK: - 逐笔周期达成率 / 数据质量

extension Calculator {
    /// 单周期达成率（口径 B 的逐笔版）：上一笔充到 ≥90%、本笔记录了充电前 SOC、本笔区间可信。
    /// 返回 本笔记录 id → 达成率（%）。
    static func cycleRates(rows: [DerivedRow], vehicle: Vehicle) -> [UUID: Double] {
        guard vehicle.ratedRangeKm > 0, rows.count > 1 else { return [:] }
        var result: [UUID: Double] = [:]
        for i in 1..<rows.count {
            let prev = rows[i - 1], cur = rows[i]
            guard cur.valid, !cur.isPending, !cur.isAggregated,
                  let dist = cur.distanceKm,
                  let after = prev.record.socAfter, after >= 90,
                  let before = cur.record.socBefore, before < after
            else { continue }
            let drop = after - before
            guard drop >= 5 else { continue }
            result[cur.record.id] = dist / drop * 100 / vehicle.ratedRangeKm * 100
        }
        return result
    }

    /// 被排除在效率统计之外的行数（有效里程但隐含电耗离谱；待累计行不算异常）。
    static func excludedCount(_ rows: [DerivedRow]) -> Int {
        rows.filter { $0.valid && !$0.isPending && !$0.plausible }.count
    }
}

// MARK: - 推荐口径：优先 B（实测），样本不足回落 A

extension Calculator {
    struct RateSummary {
        enum Source { case a, b }
        let rate: Double
        let source: Source
        let estimatedRangeKm: Double
        let cycles: Int              // B 的样本循环数
        let a: RangeRateResult?      // A 的明细（对照组）
        let bAvgRate: Double?
    }

    /// B 是实测（SOC 降幅 × 里程），不依赖手填的「可用电量」，误差源更少，所以优先展示；
    /// 没有满足满充条件的循环时，回落 A（能耗换算），并在 UI 上标明。
    static func bestRate(rows: [DerivedRow], vehicle: Vehicle,
                         window: StatsWindow, now: Date = Date()) -> RateSummary? {
        let a = rangeRateA(rows: rows, vehicle: vehicle, window: window, now: now)
        let windowed = windowRows(rows, window: window, now: now)
        let b = rangeBCycles(rows: windowed, vehicle: vehicle)

        if let bRate = b.avgRate, vehicle.ratedRangeKm > 0 {
            return RateSummary(rate: bRate, source: .b,
                               estimatedRangeKm: bRate / 100 * vehicle.ratedRangeKm,
                               cycles: b.cycles.count, a: a, bAvgRate: bRate)
        }
        if let a {
            return RateSummary(rate: a.rate, source: .a, estimatedRangeKm: a.actualRangeKm,
                               cycles: 0, a: a, bAvgRate: b.avgRate)
        }
        return nil
    }
}
