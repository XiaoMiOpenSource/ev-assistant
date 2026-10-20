import SwiftUI
import Charts

// MARK: - 达成率详情
struct RateDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    let rows = Calculator.derivedRows(store.records, for: vehicle.id)
                    let summary = Calculator.bestRate(rows: rows, vehicle: vehicle, window: store.window)
                    let a = summary?.a
                    let b = Calculator.rangeBCycles(
                        rows: Calculator.windowRows(rows, window: store.window, now: Date()),
                        vehicle: vehicle)
                    let usingB = summary?.source == .b

                    // 顶部
                    VStack(spacing: 6) {
                        Text("\(usingB ? "口径 B · 满充区间（实测）" : "口径 A · 能耗换算") · \(store.window.name)")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(summary != nil ? "\(Int(summary!.rate.rounded()))%" : "—")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(summary != nil ? Color.rateStatusColor(summary!.rate) : .secondary)
                        Text("等效续航 \(summary != nil ? Fmt.int(summary!.estimatedRangeKm) : "—") km ／ 标称 \(Fmt.int(vehicle.ratedRangeKm)) km（\(RangeStandard(raw: vehicle.rangeStandard).name)）")
                            .font(.footnote).foregroundStyle(.secondary)
                        Picker("窗口", selection: Binding(get: { store.window }, set: { store.setWindow($0) })) {
                            ForEach(StatsWindow.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 40).padding(.top, 4)
                    }
                    .padding(.top, 8)

                    // B 优先，A 对照
                    HStack(spacing: 12) {
                        compareCard(name: "口径 A · 能耗换算",
                                    value: a != nil ? "\(Int(a!.rate.rounded()))%" : "—",
                                    color: Color(red: 0.05, green: 0.65, blue: 0.42),
                                    formula: "可用电量 ÷ 电耗 × 100",
                                    sub: a != nil ? "平均电耗 \(Fmt.dec(a!.avgConsumption, 1)) kWh/100km" : "样本不足",
                                    active: !usingB && a != nil)
                        compareCard(name: "口径 B · 满充区间",
                                    value: b.avgRate != nil ? "\(Int(b.avgRate!.rounded()))%" : "—",
                                    color: Color(red: 0.32, green: 0.25, blue: 0.85),
                                    formula: "里程 ÷ SOC 降幅 × 100",
                                    sub: b.cycles.isEmpty ? "暂无满充循环" : "\(b.cycles.count) 个循环 · 实测",
                                    active: usingB)
                    }
                    .padding(.horizontal, 16)

                    Text("优先展示口径 B（满充区间实测，不依赖手填可用电量）；没有满足条件的满充循环时，自动回落口径 A。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                    // 月度历史
                    historyCard

                    // 说明
                    infoCard("计算口径 A（能耗换算法）") {
                        Text("实际续航 = 可用电量 \(Fmt.dec(a?.usableKWh ?? vehicle.effectiveUsableKWh, 1)) kWh ÷ 平均百公里电耗 \(a != nil ? Fmt.dec(a!.avgConsumption, 1) : "—") × 100 = \(a != nil ? Fmt.int(a!.actualRangeKm) : "—") km\n达成率 = 实际续航 ÷ 标称 \(Fmt.int(vehicle.ratedRangeKm)) km × 100%")
                    }
                    infoCard("口径 B（满充区间法）· 主口径") {
                        Text("单循环等效续航 = 区间里程 ÷ (上笔充电后SOC − 本笔充电前SOC) × 100。\n要求：上一笔充电后 ≥90%（近似满充），且本笔记录充电前电量。它直接测电池百分比与里程的关系，不依赖手填的「可用电量」，所以作为默认展示口径。")
                    }
                    infoCard("数据清洗") {
                        Text("隐含电耗不在 5–40 kWh/100km 的区间会被排除（通常是漏记一次充电，导致区间里程虚增、平均电耗被低估、达成率虚高）。当前排除 \(Calculator.excludedCount(rows)) 条。")
                    }
                    infoCard("状态阈值") {
                        Text("≥100% 超达成 🎉 ｜ 80–100% 正常 ｜ <80% 提示 ⚠（可在后续版本调整）")
                    }
                    infoCard("数据来源与配置") {
                        Text("基准来源：\(RangeStandard(raw: vehicle.rangeStandard).name)。同车 CLTC 与 WLTP 差异可达 10–15%，来源选择直接影响达成率数值。可在「设置 → 车辆」修改标称续航、可用电量与统计窗口。")
                    }
                }
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("续航达成率")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func compareCard(name: String, value: String, color: Color,
                             formula: String, sub: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(name).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if active {
                    Text("当前")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(color.opacity(0.16)))
                        .foregroundColor(color)
                }
            }
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(color)
            Text(formula)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(sub).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? color.opacity(0.55) : Color.clear, lineWidth: 1.2)
        )
    }

    private var historyCard: some View {
        let rows = Calculator.derivedRows(store.records, for: vehicle.id)
        let series = Calculator.monthSeries(rows)
        let data: [(String, Double)] = series.compactMap { p in
            guard let c = p.consumption, c > 0, vehicle.ratedRangeKm > 0 else { return nil }
            let rate = vehicle.effectiveUsableKWh / c * 100 / vehicle.ratedRangeKm * 100
            return (p.monthLabel, rate)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("月度历史达成率").font(.headline)
            if data.isEmpty {
                Text("暂无数据").font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Chart(data, id: \.0) { item in
                    LineMark(x: .value("月份", monthLabel(item.0)), y: .value("达成率", item.1))
                        .foregroundStyle(Color(red: 0.32, green: 0.25, blue: 0.85))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("月份", monthLabel(item.0)), y: .value("达成率", item.1))
                        .foregroundStyle(Color(red: 0.32, green: 0.25, blue: 0.85))
                    RuleMark(y: .value("参考", 100)).foregroundStyle(Color.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
                }
                .chartYScale(domain: 40...130)
                .frame(height: 160)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let m = Int(parts[1]) else { return key }
        return "\(m)月"
    }

    private func infoCard<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content().font(.footnote).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
}
