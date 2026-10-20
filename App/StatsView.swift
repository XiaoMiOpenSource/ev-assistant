import SwiftUI
import Charts
import UIKit

// MARK: - 统计 Tab
struct ChargerAgg { var cost = 0.0; var dist = 0.0; var n = 0; var costAll = 0.0 }

struct StatsView: View {
    @EnvironmentObject private var store: Store
    @State private var showRateDetail = false
    // P3：PDF 月度报告
    @State private var pdfBusy = false

    var body: some View {
        NavigationStack {
            Group {
                if let v = store.activeVehicle {
                    let rows = Calculator.derivedRows(store.records, for: v.id)
                    if rows.isEmpty {
                        empty(v)
                    } else {
                        statsBody(v, rows)
                    }
                } else {
                    noVehicle
                }
            }
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("-exportpdf"), store.activeVehicle != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { exportMonthlyPDF() }
                }
                #endif
            }
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("-ratedetail") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { showRateDetail = true }
                }
                #endif
            }
            .navigationTitle("统计")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    vehicleMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportMonthlyPDF()
                    } label: {
                        if pdfBusy {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(pdfBusy || store.activeVehicle == nil)
                    .accessibilityLabel("导出月度报告 PDF")
                }
            }
            .sheet(isPresented: $showRateDetail) {
                if let v = store.activeVehicle {
                    RateDetailView(vehicle: v)
                        .environmentObject(store)
                }
            }
        }
    }

    private var vehicleMenu: some View {
        Menu {
            ForEach(store.vehicles) { v in
                Button {
                    store.setActive(v.id)
                } label: {
                    if store.activeVehicleID == v.id {
                        Label(v.name, systemImage: "checkmark")
                    } else {
                        Text(v.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(store.activeVehicle?.name ?? "车辆").font(.headline)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .foregroundColor(.primary)
        }
    }

    private var noVehicle: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("暂无车辆，请到「设置」添加").font(.subheadline).foregroundStyle(.secondary)
            Button("去设置") { store.selectedTab = .settings }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func empty(_ v: Vehicle) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("还没有数据").font(.headline)
                Text("录入 2 笔以上充电记录后，将在这里展示\n电耗、成本与续航达成率统计").font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("去记录第一笔") { store.selectedTab = .records }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(.top, 120)
        }
    }

    private func statsBody(_ v: Vehicle, _ rows: [DerivedRow]) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard(v, rows)          // P2：月度小结（本月 vs 上月）+ 预算进度
                rateCard(v, rows)
                monthCards(rows)
                totalsGrid(rows)
                chartsSection(v, rows)
                chargerSection(rows)
                Text("数据仅存储于本机 · 所有派生值按时间实时计算，不落库")
                    .font(.caption2).foregroundStyle(.tertiary).padding(.bottom, 8)
            }
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: P2 · 月度小结 + 预算进度
    private func summaryCard(_ v: Vehicle, _ rows: [DerivedRow]) -> some View {
        let series = Calculator.monthSeries(rows)
        let cm = Date().monthKey
        let pm = Calendar.current.date(byAdding: .month, value: -1, to: Date())?.monthKey ?? cm
        let cur = series.first { $0.monthKey == cm }
        let prev = series.first { $0.monthKey == pm }

        func delta(_ a: Double, _ b: Double) -> (Double?, Color, String) {
            guard b > 0, a > 0 else { return (nil, .secondary, "—") }
            let d = (a - b) / b * 100
            // 中国习惯：费用/电耗上涨用红色警示，下降用绿色
            let color: Color = d >= 0 ? .red : .green
            let arrow = d >= 0 ? "▲" : "▼"
            return (d, color, arrow)
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本月小结").font(.headline)
                Spacer()
                if store.hasBudget, let cur {
                    HStack(spacing: 2) {
                        Image(systemName: cur.cost > store.monthlyBudget ? "exclamationmark.triangle.fill" : "target")
                            .font(.caption2).foregroundColor(cur.cost > store.monthlyBudget ? .red : .secondary)
                        ProgressView(value: min(cur.cost / max(store.monthlyBudget, 1), 1))
                            .tint(cur.cost > store.monthlyBudget ? .red : .brand)
                            .frame(width: 60)
                        Text("¥\(Int(cur.cost.rounded()))/\(Int(store.monthlyBudget.rounded()))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let cur {
                HStack(spacing: 0) {
                    mItem("费用", "¥\(Int(cur.cost.rounded()))",
                          prev.map { delta(cur.cost, $0.cost) })
                    Divider().frame(height: 30)
                    mItem("里程", "\(Int(cur.distAll.rounded())) km",
                          prev.map { delta(cur.distAll, $0.distAll) })
                    Divider().frame(height: 30)
                    mItem("平均电耗", cur.consumption.map { Fmt.dec($0, 1) } ?? "—",
                          prev.flatMap { p in cur.consumption.flatMap { c in p.consumption.map { delta(c, $0) } } })
                }
                if prev == nil {
                    Text("上月暂无记录，本月为首个完整记录月")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("本月暂无记录").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(.secondarySystemGroupedBackground), Color(.secondarySystemGroupedBackground)],
                           startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }
    @ViewBuilder
    private func mItem(_ name: String, _ value: String, _ d: (Double?, Color, String)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let d, let pct = d.0 {
                    Text("\(d.2)\(Int(abs(pct).rounded()))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(d.1)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: P3 · PDF 月度报告
    private func exportMonthlyPDF() {
        guard let v = store.activeVehicle, !pdfBusy else { return }
        let rows = Calculator.derivedRows(store.records, for: v.id)
        pdfBusy = true
        Task {
            let url = MonthlyPDFBuilder.build(vehicle: v, rows: rows, budget: store.hasBudget ? store.monthlyBudget : nil)
            await MainActor.run {
                pdfBusy = false
                if let url { SharePresenter.share([url]) }
            }
        }
    }

    // MARK: 达成率卡片（A / B 分开上下两块，先 A 后 B）
    private func rateCard(_ v: Vehicle, _ rows: [DerivedRow]) -> some View {
        let summary = Calculator.bestRate(rows: rows, vehicle: v, window: store.window)
        let b = Calculator.rangeBCycles(
            rows: Calculator.windowRows(rows, window: store.window, now: Date()),
            vehicle: v)

        return Button {
            showRateDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("续航达成率")
                        .font(.system(size: 16, weight: .semibold))
                    if let summary { statusBadge(summary.rate) }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white.opacity(0.65))
                }

                divider

                rateBlock(title: "口径 A · 能耗换算",
                          value: summary?.a?.rate,
                          formula: summary?.a.map {
                              "可用电量 \(Fmt.dec($0.usableKWh, 1)) kWh ÷ 平均电耗 \(Fmt.dec($0.avgConsumption, 1)) × 100"
                          } ?? "可用电量 ÷ 平均电耗 × 100",
                          footnote: summary?.a.map {
                              "等效续航 \(Fmt.int($0.actualRangeKm)) km ／ 标称 \(Fmt.int(v.ratedRangeKm)) km"
                          } ?? "样本不足")

                divider

                rateBlock(title: "口径 B · 满充区间",
                          value: b.avgRate,
                          formula: b.cycles.isEmpty
                              ? "里程 ÷ SOC 降幅 × 100（需要一次满充到 ≥90% 的完整循环）"
                              : "区间里程 ÷ SOC 降幅 × 100",
                          footnote: b.cycles.isEmpty
                              ? "暂无满充循环"
                              : "\(b.cycles.count) 个循环 · 等效续航 \(summary.map { Fmt.int($0.estimatedRangeKm) } ?? "—") km")

                divider

                Text(footLine(summary, b))
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(.white)
            .padding(16)
            .background(
                LinearGradient(colors: [Color(red: 0.05, green: 0.45, blue: 0.95),
                                        Color(red: 0.32, green: 0.25, blue: 0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
    }

    /// 单块口径：标题 + 数值 + 换算方式 + 结果说明
    private func rateBlock(title: String, value: Double?, formula: String, footnote: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 8)
                Text(value != nil ? "\(Int(value!.rounded()))%" : "—")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Text(formula)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.62))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(footnote)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func footLine(_ summary: Calculator.RateSummary?,
                          _ b: (cycles: [Calculator.RangeBCycle], avgRate: Double?)) -> String {
        let usingB = summary?.source == .b
        let mode = usingB ? "主显示口径 B" : "B 样本不足，按 A 显示"
        return "\(store.window.name) · \(mode)"
    }

    @ViewBuilder
    private func statusBadge(_ rate: Double) -> some View {
        let icon: String = rate >= 100 ? "sparkles" : (rate >= 80 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        let tint: Color = rate >= 100 ? Color(red: 0.42, green: 0.95, blue: 0.65)
            : (rate >= 80 ? .white : Color(red: 1.0, green: 0.82, blue: 0.35))
        let text: String = rate >= 100 ? "超达成" : (rate >= 80 ? "正常" : "低于预期")
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundColor(tint)
            Text(text).font(.system(size: 10.5, weight: .semibold)).foregroundColor(.white)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(Color.white.opacity(0.16)))
    }

    private func rateTag(_ r: Double) -> String {
        if r >= 100 { return "🎉 超达成" }
        if r >= 80 { return "正常" }
        return "⚠ 低于预期"
    }

    // MARK: 本月
    private func monthCards(_ rows: [DerivedRow]) -> some View {
        let series = Calculator.monthSeries(rows)
        let current = Date().monthKey
        let m0 = series.first { $0.monthKey == current }
        return HStack(spacing: 12) {
            metricBox("本月费用", m0.map { Fmt.yuan($0.cost) } ?? "—", unit: "")
            metricBox("本月充电", m0.map { Fmt.dec($0.energyAll, 1) } ?? "—", unit: "kWh")
        }
        .padding(.horizontal, 16)
    }

    // MARK: 累计概览
    private func totalsGrid(_ rows: [DerivedRow]) -> some View {
        let t = Calculator.totals(rows)
        return VStack(alignment: .leading, spacing: 10) {
            Text("累计概览 · 共 \(t.count) 笔").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metricBox("累计里程", Fmt.intStr(t.dist), unit: "km")
                metricBox("累计充电费", Fmt.yuan(t.costAll), unit: "")
                metricBox("累计充电量", Fmt.dec(t.energyAll, 1), unit: "kWh")
                metricBox("平均成本", t.avgCostPerKm.map { Fmt.dec($0, 2) } ?? "—", unit: "元/km")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func metricBox(_ name: String, _ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: 图表区
    private func chartsSection(_ v: Vehicle, _ rows: [DerivedRow]) -> some View {
        let series = Calculator.monthSeries(rows)
        return VStack(spacing: 14) {
            costChart(series)
            consumptionChart(series)
            rateHistoryChart(v, series)
        }
    }

    private func costChart(_ series: [Calculator.MonthPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("充电费用 · 近 6 月").font(.headline)
            Chart(series.filter { inLast6($0.monthKey) }) { p in
                BarMark(x: .value("月份", shortMonth(p.monthKey)), y: .value("费用", p.cost))
                    .foregroundStyle(Color.orange.gradient)
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                    AxisValueLabel()
                }
            }
            .frame(height: 150)
            Text("月度充电费用（¥）").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func consumptionChart(_ series: [Calculator.MonthPoint]) -> some View {
        let data = series.filter { inLast6($0.monthKey) && $0.consumption != nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text("百公里电耗 · 月度").font(.headline)
            if data.isEmpty {
                emptyChart("有效区间数据不足")
            } else {
                Chart(data) { p in
                    LineMark(x: .value("月份", shortMonth(p.monthKey)), y: .value("电耗", p.consumption!))
                        .foregroundStyle(Color.blue)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("月份", shortMonth(p.monthKey)), y: .value("电耗", p.consumption!))
                        .foregroundStyle(Color.blue)
                }
                .frame(height: 150)
            }
            Text("kWh / 100km（充电量 ÷ 行驶里程，含损耗）").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func rateHistoryChart(_ v: Vehicle, _ series: [Calculator.MonthPoint]) -> some View {
        let data = series.compactMap { p -> (String, Double)? in
            guard let c = p.consumption, c > 0, v.ratedRangeKm > 0 else { return nil }
            let rate = v.effectiveUsableKWh / c * 100 / v.ratedRangeKm * 100
            return (shortMonth(p.monthKey), rate)
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("续航达成率 · 月度").font(.headline)
            if data.isEmpty {
                emptyChart("暂无数据")
            } else {
                Chart(data, id: \.0) { item in
                    LineMark(x: .value("月份", item.0), y: .value("达成率", item.1))
                        .foregroundStyle(Color(red: 0.32, green: 0.25, blue: 0.85))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("月份", item.0), y: .value("达成率", item.1))
                        .foregroundStyle(Color(red: 0.32, green: 0.25, blue: 0.85))
                    RuleMark(y: .value("参考", 100)).foregroundStyle(Color.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 0.6, dash: [4, 3]))
                }
                .chartYScale(domain: 40...130)
                .frame(height: 150)
            }
            Text("达成率 %（口径A，虚线为标称 100%）").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func emptyChart(_ msg: String) -> some View {
        Text(msg).font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func inLast6(_ monthKey: String) -> Bool {
        let now = Date()
        var keys = Set<String>()
        for k in 0..<6 {
            if let d = Calendar.current.date(byAdding: .month, value: -k, to: now) {
                keys.insert(d.monthKey)
            }
        }
        return keys.contains(monthKey)
    }

    private func shortMonth(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return "\(Int(parts[1])!)月"
    }

    // MARK: 按桩型
    private func chargerSection(_ rows: [DerivedRow]) -> some View {
        var map: [ChargerType: ChargerAgg] = [:]
        for row in rows {
            let ct = ChargerType(rawValue: row.record.chargerType) ?? .home
            var a = map[ct] ?? ChargerAgg()
            a.costAll += row.record.costCNY
            if row.valid {
                a.cost += row.record.costCNY
                a.dist += row.distanceKm ?? 0
                a.n += 1
            }
            map[ct] = a
        }
        let ordered = ChargerType.allCases.compactMap { ct -> (ChargerType, ChargerAgg)? in
            guard let a = map[ct], a.dist > 0 else { return nil }
            return (ct, a)
        }
        guard !ordered.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text("按桩类型").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ordered, id: \.0) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.0.name) · \(item.1.n) 笔").font(.caption).foregroundStyle(.secondary)
                            Text("\(Fmt.dec(item.1.cost / item.1.dist, 2)) 元/km")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(item.0.color)
                            Text("总花费 \(Fmt.yuan(item.1.costAll))").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 16)
        )
    }
}

// MARK: - P3 · PDF 月度报告构建器（UIKit 矢量绘制 → 临时文件 → 系统分享）
enum MonthlyPDFBuilder {
    static func build(vehicle: Vehicle, rows: [DerivedRow], budget: Double?) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4
        let fmt = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: fmt)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 60
            let margin: CGFloat = 56
            let width = page.width - margin * 2

            func draw(_ text: String, _ size: CGFloat, _ bold: Bool, color: UIColor = .black) {
                let f = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
                let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
                let str = text as NSString
                let box = CGRect(x: margin, y: y, width: width, height: 30)
                str.draw(in: box, withAttributes: attrs)
                y += size + 8
            }
            func hr() {
                let p = UIBezierPath()
                p.move(to: CGPoint(x: margin, y: y))
                p.addLine(to: CGPoint(x: margin + width, y: y))
                p.lineWidth = 0.6
                UIColor.systemGray3.setStroke()
                p.stroke()
                y += 14
            }
            // 页面换页保护
            func ensure(_ h: CGFloat = 80) {
                if y > page.height - 90 {
                    ctx.beginPage()
                    y = 60
                }
            }

            // 标题
            let now = Date()
            let dfm = DateFormatter(); dfm.locale = Locale(identifier: "zh_CN"); dfm.dateFormat = "yyyy年M月"
            draw("电车助手 · 月度报告", 22, true)
            y -= 4
            draw("\(vehicle.name) · \(dfm.string(from: now)) · 生成于 \(now.zhDay())", 12, false, color: .systemGray)
            hr()

            // 汇总
            let cur = Calculator.monthSeries(rows).first { $0.monthKey == now.monthKey }
            let wavg = Calculator.weightAvg(rows, window: .threeMonths)
            let rate = Calculator.rangeRateA(rows: rows, vehicle: vehicle, window: .threeMonths)
            draw("本月概览", 15, true)
            if let cur {
                draw("本月费用：¥\(Int(cur.cost.rounded()))   本月里程：\(Int(cur.distPair.rounded())) km   本月充电：\(Fmt.dec(cur.energyAll, 1)) kWh", 12, false)
            } else {
                draw("本月暂无充电记录。", 12, false)
            }
            if let wavg { draw("近3月平均电耗：\(Fmt.dec(wavg.cons, 1)) kWh/100km", 12, false) }
            if let rate { draw("续航达成率（近3月）：\(Int(rate.rate.rounded()))%（口径 A·能耗换算）", 12, false) }
            if let budget, let cur {
                let ratio = Int((cur.cost / max(budget, 1)) * 100)
                draw("预算：¥\(Int(budget.rounded())) ／ 已使用 \(ratio)%", 12, false,
                     color: cur.cost > budget ? .systemRed : .systemGray)
            }
            hr()

            // 本月明细
            draw("本月充电明细", 15, true)
            let cmRecords = rows
                .filter { $0.record.date.monthKey == now.monthKey }
                .sorted { $0.record.date < $1.record.date }
            if cmRecords.isEmpty {
                draw("（无记录）", 12, false, color: .systemGray)
            }
            let dday = DateFormatter(); dday.locale = Locale(identifier: "zh_CN"); dday.dateFormat = "MM-dd"
            for r in cmRecords {
                ensure()
                let ct = ChargerType(rawValue: r.record.chargerType)?.name ?? ""
                var line = "\(dday.string(from: r.record.date))  \(ct)  电量 \(Fmt.dec(r.record.energyKWh, 1)) kWh  ¥\(Fmt.dec(r.record.costCNY, 2))  里程 \(Fmt.dec(r.record.odometerKm, 0)) km"
                if r.valid {
                    line += "  (行驶 \(Fmt.dec(r.distanceKm, 0)) km · \(Fmt.dec(r.consumption, 1)) kWh/100km)"
                } else if r.kind == .first {
                    line += "  (基准记录)"
                } else {
                    line += "  (里程异常)"
                }
                draw(line, 11.5, false)
                if r.record.socBefore ?? r.record.socAfter != nil {
                    draw("    SOC \(r.record.socBefore.map { Fmt.int($0) + "%" } ?? "—") → \(r.record.socAfter.map { Fmt.int($0) + "%" } ?? "—")", 10, false, color: .systemGray)
                }
                if !r.record.note.isEmpty {
                    draw("    备注：\(r.record.note)", 10, false, color: .systemGray)
                }
            }
            hr()

            // 尾部
            ensure(60)
            draw("数据均存于本机，仅用于个人用车成本分析。", 10, false, color: .systemGray)
            draw("口径：百公里电耗 = 充电量 ÷ 行驶里程 × 100（含充电损耗）", 10, false, color: .systemGray)
        }

        let name = "电车助手_月报_\(Date().isoDate()).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
