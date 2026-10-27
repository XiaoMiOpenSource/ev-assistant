import SwiftUI

// MARK: - 记录 Tab
struct RecordsView: View {
    @EnvironmentObject private var store: Store
    @State private var formMode: FormMode?
    @State private var filterMonth: String?        // 年月筛选
    @State private var searchText = ""
    @State private var localMsg: String?
    @State private var msgTask: Task<Void, Never>?
    @State private var hideUndoTask: Task<Void, Never>?
    @State private var lastLongPressAt = Date.distantPast

    enum FormMode: Identifiable {
        var id: String {
            switch self { case .new: return "new"; case .edit(let r): return r.id.uuidString }
        }
        case new
        case edit(ChargeRecord)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let v = store.activeVehicle {
                    content(v)
                } else {
                    noVehicleView
                }
            }
            .navigationTitle("记录")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if store.activeVehicle != nil {
                        Button { formMode = .new } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            }
            .sheet(item: $formMode) { mode in
                RecordFormView(mode: mode)
                    .environmentObject(store)
            }
            .onReceive(store.$newRecordTick.dropFirst()) { _ in
                formMode = .new
            }
            // 长按 → 删除确认（唯一系统 Alert）
            .alert(item: $pendingDelete) { record in
                Alert(
                    title: Text("删除这条记录？"),
                    message: Text("\(record.date.zhDay()) · \(Fmt.dec(record.energyKWh, 1)) kWh / \(Fmt.yuan(record.costCNY))\n删除后不可恢复。"),
                    primaryButton: .destructive(Text("删除")) {
                        performDelete(record)
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
            .overlay(alignment: .bottom) { bottomBars }
            .onChange(of: store.undoOffer) { newOffer in
                guard newOffer != nil else { return }
                hideUndoTask?.cancel()
                hideUndoTask = Task {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    if !Task.isCancelled { store.undoOffer = nil }
                }
            }
        }
    }

    // MARK: - 状态
    @State private var pendingDelete: ChargeRecord?

    // MARK: - 底部：撤销条 + 轻提示
    @ViewBuilder private var bottomBars: some View {
        VStack(spacing: 8) {
            if let offer = store.undoOffer {
                HStack(spacing: 10) {
                    Text(offer.message).font(.footnote)
                    Button("撤销") { store.undoLast() }
                        .font(.footnote.weight(.semibold))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color(.label).opacity(0.88))
                .foregroundColor(Color(.systemBackground))
                .clipShape(Capsule())
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let localMsg {
                Text(localMsg)
                    .font(.footnote)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color(.label).opacity(0.85))
                    .foregroundColor(Color(.systemBackground))
                    .clipShape(Capsule())
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 56)
        .animation(.default, value: store.undoOffer)
    }
    private func showLocal(_ msg: String) {
        msgTask?.cancel()
        withAnimation { localMsg = msg }
        msgTask = Task {
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            if !Task.isCancelled { withAnimation { localMsg = nil } }
        }
    }

    // MARK: - 删除（失败反馈 + 成功提供撤销）
    private func performDelete(_ record: ChargeRecord) {
        if store.deleteRecord(record.id) {
            store.offerUndo(kind: .delete, message: "已删除 1 条记录", record: record)
        } else {
            showLocal("删除失败，请重试")
        }
    }

    // MARK: - 手势
    private func longPressAction(_ record: ChargeRecord) {
        lastLongPressAt = Date()
        if pendingDelete == nil { pendingDelete = record }
    }
    private func tapAction(_ record: ChargeRecord) {
        guard Date().timeIntervalSince(lastLongPressAt) > 0.45 else { return }
        formMode = .edit(record)
    }

    // MARK: - 视图
    private var noVehicleView: some View {
        VStack(spacing: 14) {
            Image(systemName: "car.fill").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("还没有车辆\n请到「设置」添加你的电车").multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
            Button("去设置") { store.selectedTab = .settings }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func content(_ v: Vehicle) -> some View {
        let rows = filteredRows(for: v)
        let totals = Calculator.totals(Calculator.derivedRows(store.records, for: v.id))
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部摘要行（三项居中，与下方卡片同一套留白/圆角）
                HStack(spacing: 0) {
                    summaryItem("平均电耗", Fmt.dec(totals.avgConsumption, 1), unit: "kWh/100km")
                    summaryDivider
                    summaryItem("平均成本", Fmt.dec(totals.avgCostPerKm.map { $0 * 100 }, 1), unit: "元/100km")
                    summaryDivider
                    summaryItem("累计里程", Fmt.intStr(totals.dist), unit: "km")
                }
                .padding(.vertical, 14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16).padding(.top, 10)

                // 续航达成率（按设置页所选月份区间统计）
                rateRangeBar(v: v, rows: rows)
                    .padding(.horizontal, 16).padding(.top, 8)

                // P1：搜索
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索备注 / 桩型 / 金额", text: $searchText)
                        .font(.subheadline)
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16).padding(.top, 10)

                // P1：年月筛选
                monthChips(allMonths: allMonths(for: v))

                if rows.count == 0 {
                    emptyState(text: hasFilters ? "没有符合条件的记录" : "还没有充电记录\n每次充电后 10 秒记一笔，自动算出真实电耗与每公里成本")
                } else {
                    let cycleRates = Calculator.cycleRates(rows: rows, vehicle: v)
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.record.id) { row in
                            RecordCard(row: row,
                                       tempC: store.tempC(for: row.record.id),
                                       rate: cycleRates[row.record.id],
                                       isAnomaly: anomaly(for: row),
                                       isImplausible: row.valid && !row.plausible)
                                .contentShape(Rectangle())
                                .onTapGesture { tapAction(row.record) }
                                .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 50,
                                                    perform: { longPressAction(row.record) })
                                .contextMenu { deleteMenu(row.record) }
                            Divider().padding(.leading, 16)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16).padding(.top, 10)
                    footerNote
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var hasFilters: Bool { !searchText.isEmpty || filterMonth != nil }

    /// 续航达成率：A / B 各自成块，两张卡分开摆；口径与「统计」页一致
    private func rateRangeBar(v: Vehicle, rows: [DerivedRow]) -> some View {
        let summary = Calculator.bestRate(rows: rows, vehicle: v, window: store.window)
        let excluded = Calculator.excludedCount(rows)
        let a = summary?.a?.rate
        let b = summary?.bAvgRate

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("续航达成率")
                    .font(.subheadline.weight(.semibold))
                Text(store.window.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            rateBlock(title: "口径 A · 能耗换算",
                      subtitle: "可用电量 ÷ 电耗 × 100",
                      value: a)

            rateBlock(title: "口径 B · 满充区间",
                      subtitle: "里程 ÷ SOC 降幅 × 100",
                      value: b)

            if excluded > 0 {
                Text("已排除 \(excluded) 条电耗异常记录（可能是里程/充电量录入有误，或存在漏记）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func rateBlock(title: String, subtitle: String, value: Double?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(value.map { String(format: "%.1f%%", $0) } ?? "—")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func allMonths(for v: Vehicle) -> [String] {
        var set = Set<String>()
        store.records.filter { $0.vehicleID == v.id }.forEach { set.insert($0.date.monthKey) }
        return set.sorted(by: >)
    }

    @ViewBuilder private func monthChips(allMonths: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", active: filterMonth == nil) { filterMonth = nil }
                ForEach(allMonths, id: \.self) { m in
                    chip(shortLabel(m), active: filterMonth == m) { filterMonth = m }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 6)
    }
    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(active ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(active ? Color.brand : Color(.tertiarySystemFill))
                .foregroundColor(active ? .white : .primary)
                .clipShape(Capsule())
        }
    }
    private func shortLabel(_ key: String) -> String {
        let p = key.split(separator: "-")
        guard p.count == 2 else { return key }
        return "\(Int(p[1])!)月"
    }

    private func filteredRows(for v: Vehicle) -> [DerivedRow] {
        var rows = store.records
            .filter { $0.vehicleID == v.id }
            .sorted { a, b in a.date == b.date ? a.createdAt > b.createdAt : a.date > b.date }
        if let m = filterMonth {
            rows = rows.filter { $0.date.monthKey == m }
        }
        if !searchText.isEmpty {
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            rows = rows.filter { r in
                r.note.lowercased().contains(q)
                    || (ChargerType(rawValue: r.chargerType)?.name ?? "").contains(q)
                    || Fmt.dec(r.costCNY, 2).contains(q)
            }
        }
        return Calculator.derivedRows(store.records, for: v.id)
            .filter { row in rows.contains { $0.id == row.record.id } }
    }

    /// P2：异常电耗——高于该车其它近 3 月有效记录均值 1.5 倍视为异常
    private func anomaly(for row: DerivedRow) -> Bool {
        guard row.valid, let c = row.consumption, c > 0 else { return false }
        let now = row.record.date
        let cal = Calendar.current
        let baselineStart = cal.date(byAdding: .month, value: -3, to: now) ?? now
        let others = Calculator.derivedRows(store.records, for: row.record.vehicleID)
            .filter { $0.countable && $0.record.id != row.record.id && $0.record.date >= baselineStart }
        guard !others.isEmpty else { return false }
        let avg = others.reduce(0) { $0 + ($1.consumption ?? 0) } / Double(others.count)
        return avg > 0 && c > avg * 1.5
    }

    @ViewBuilder private func deleteMenu(_ record: ChargeRecord) -> some View {
        Button(role: .destructive) { performDelete(record) } label: {
            Label("删除此条", systemImage: "trash")
        }
    }

    private func summaryItem(_ name: String, _ value: String, unit: String) -> some View {
        VStack(spacing: 3) {
            Text(name).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
    private var summaryDivider: some View { Divider().frame(height: 34) }

    private func emptyState(text: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "battery.75percent").font(.system(size: 46)).foregroundStyle(.secondary)
            Text(text).multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
            if !hasFilters {
                Button { formMode = .new } label: { Label("记下第一笔", systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 70)
    }

    private var footerNote: some View {
        Text("长按删除 · 点按编辑 · 按住记录约 0.6 秒可删除\n行驶里程 = 本次里程表读数 − 上一笔读数 · 首笔为基准 · 里程回退自动过滤\n刚充电又短距离补电的记录不单独计算，与相邻区间合并")
            .font(.caption2).foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity).padding(14).multilineTextAlignment(.center)
    }
}

// MARK: - 记录卡片
struct RecordCard: View {
    let row: DerivedRow
    var tempC: Int?
    /// 本笔所在充电周期的达成率（口径 B 逐笔版）；无 SOC 数据时为空，不显示标签
    var rate: Double?
    var isAnomaly: Bool = false
    /// 区间里程/电耗明显失真，已排除在电耗统计之外
    var isImplausible: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.record.date.zhDay())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                HStack(spacing: 6) {
                    if let tempC { tempTag(tempC) }
                    if isImplausible { implausibleTag }
                    if isAnomaly { anomalyTag }
                    rateTag
                    tag
                }
            }
            HStack(spacing: 18) {
                kv("充电量", "\(Fmt.dec(row.record.energyKWh, 1)) kWh")
                kv("金额", Fmt.yuan(row.record.costCNY))
                kv("里程表", "\(Fmt.dec(row.record.odometerKm, 0)) km")
            }
            if row.valid {
                HStack(spacing: 16) {
                    dkv("行驶", "\(Fmt.dec(row.distanceKm, 0)) km")
                    dkv(row.isAggregated ? "区间电耗" : "电耗",
                        "\(Fmt.dec(row.consumption, 1)) kWh/100km")
                    dkv("成本", "\(Fmt.dec(row.costPerKm, 2)) 元/km")
                }
                .padding(.top, 2)
                if row.isPending {
                    Text("短区间不单独计算，与相邻充电区间合并")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if row.isAggregated, let distance = row.groupDistanceKm {
                    Text("合并相邻短区间 · 合计 \(Fmt.dec(distance, 0)) km，充电量与费用按合计计算")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if row.record.socBefore != nil || row.record.socAfter != nil {
                Text("SOC \(row.record.socBefore != nil ? Fmt.int(row.record.socBefore!) + "%" : "—") → \(row.record.socAfter != nil ? Fmt.int(row.record.socAfter!) + "%" : "—")")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !row.record.note.isEmpty {
                Text("📝 " + row.record.note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func tempTag(_ t: Int) -> some View {
        Text("🌡 \(t)°")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.cyan.opacity(0.14)).foregroundColor(.cyan)
            .clipShape(Capsule())
    }
    /// 本笔周期达成率（口径 B：区间里程 ÷ SOC 降幅 ÷ 标称）；无 SOC 数据时不显示
    @ViewBuilder private var rateTag: some View {
        if let rate {
            Text("达成 \(String(format: "%.0f%%", rate))")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.brand.opacity(0.14)).foregroundColor(.brand)
                .clipShape(Capsule())
        }
    }
    private var implausibleTag: some View {
        Text("⚠ 数据异常")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.red.opacity(0.12)).foregroundColor(.red)
            .clipShape(Capsule())
    }
    private var anomalyTag: some View {
        Text("⚠ 异常")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.orange.opacity(0.16)).foregroundColor(.orange)
            .clipShape(Capsule())
    }

    @ViewBuilder private var tag: some View {
        let ct = ChargerType(rawValue: row.record.chargerType) ?? .home
        switch row.kind {
        case .ok:
            HStack(spacing: 4) {
                Image(systemName: ct.icon).font(.system(size: 9))
                Text(ct.name).font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(ct.color.opacity(0.15)).foregroundColor(ct.color)
            .clipShape(Capsule())
        case .first:
            Text("基准记录").font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(.tertiarySystemFill)).clipShape(Capsule())
        case .pending:
            Text("待累计").font(.caption2).fontWeight(.semibold)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(.tertiarySystemFill)).clipShape(Capsule())
        case .rollback:
            Text("里程异常").font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.orange.opacity(0.15)).foregroundColor(.orange).clipShape(Capsule())
        }
    }

    private func kv(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.subheadline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
    private func dkv(_ t: String, _ v: String) -> some View {
        HStack(spacing: 3) {
            Text(t).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.caption.weight(.semibold)).foregroundStyle(.primary)
        }
    }
}
