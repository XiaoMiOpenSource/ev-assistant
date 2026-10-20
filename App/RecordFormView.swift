import SwiftUI

// MARK: - 记录表单（新建 / 编辑）
struct RecordFormView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var carModel: CarModel
    @Environment(\.dismiss) private var dismiss
    let mode: RecordsView.FormMode

    @State private var date: Date = Date()
    @State private var chargerType: ChargerType = .home
    @State private var energyStr = ""
    @State private var costStr = ""
    @State private var odoStr = ""
    @State private var socBStr = ""
    @State private var socAStr = ""
    @State private var note = ""
    @State private var errorMessage: String?
    // P1/P2 增强：温度标签（UserDefaults 元数据，不触碰 Core Data 模型）
    @State private var hasTemp = false
    @State private var tempValue = 20
    @State private var original: ChargeRecord?   // 编辑前的原记录（供撤销）

    init(mode: RecordsView.FormMode) {
        self.mode = mode
        if case .edit(let r) = mode {
            _original = State(initialValue: r)
            _date = State(initialValue: r.date)
            _chargerType = State(initialValue: ChargerType(rawValue: r.chargerType) ?? .home)
            _energyStr = State(initialValue: Fmt.dec(r.energyKWh, 1))
            _costStr = State(initialValue: Fmt.dec(r.costCNY, 2))
            _odoStr = State(initialValue: Fmt.dec(r.odometerKm, 0))
            _socBStr = State(initialValue: r.socBefore.map { Fmt.int($0) } ?? "")
            _socAStr = State(initialValue: r.socAfter.map { Fmt.int($0) } ?? "")
            _note = State(initialValue: r.note)
        } else {
            // “记住上次桩型”：上次保存记录用的桩型作为默认
            let last = UserDefaults.standard.integer(forKey: "lastChargerType")
            if last >= 0 && last <= 2, let ct = ChargerType(rawValue: Int16(last)) {
                _chargerType = State(initialValue: ct)
            }
        }
    }

    private var isEdit: Bool { if case .edit = mode { return true }; return false }

    private var canReuseLast: Bool {
        guard !isEdit, store.activeVehicle != nil else { return false }
        return store.records.contains { $0.vehicleID == store.activeVehicle?.id }
    }
    private func reuseLast() {
        // “沿用上笔”：复制同车最近一条的 桩型 + 备注（电量/金额/里程每笔不同，不复制）
        guard let v = store.activeVehicle else { return }
        let last = store.records
            .filter { $0.vehicleID == v.id }
            .sorted { $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date }
            .first
        guard let last else { return }
        chargerType = ChargerType(rawValue: last.chargerType) ?? .home
        note = last.note
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    group(label: "日期与桩型") {
                        if !isEdit && canReuseLast {
                            Button {
                                reuseLast()
                            } label: {
                                Label("沿用上笔（桩型 + 备注）", systemImage: "arrow.uturn.backward.circle")
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.brand)
                        }
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                        Picker("桩类型", selection: $chargerType) {
                            ForEach(ChargerType.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    group(label: "电量与金额") {
                        HStack(spacing: 12) {
                            field("充电量 (kWh)", text: $energyStr, unit: "kWh")
                            field("金额 (¥)", text: $costStr, unit: "¥")
                        }
                    }

                    group(label: "里程表读数") {
                        if !isEdit { snapshotFill }
                        field("本次里程表读数 (km)", text: $odoStr, unit: "km")
                        Text("行驶里程 = 本次读数 − 上一笔读数，系统自动推算，无需手填。")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    group(label: "电量状态（可选，用于口径 B 满充区间）") {
                        HStack(spacing: 12) {
                            field("充电前 %", text: $socBStr, unit: "%")
                            field("充电后 %", text: $socAStr, unit: "%")
                        }
                    }

                    group(label: "温度标签（可选，用于能耗归因）") {
                        Toggle("记录当天温度", isOn: $hasTemp)
                        if hasTemp {
                            Stepper(value: $tempValue, in: -20...45) {
                                Text("\(tempValue)°C").font(.subheadline.weight(.semibold))
                            }
                            Text("冬季达成率骤降时可回看温度，解释电耗差异")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    group(label: "备注") {
                        TextField("充电地点 / 天气 / 路况…", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }

                    livePreview
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(isEdit ? "编辑记录" : "记一笔充电")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.fontWeight(.semibold)
                }
            }
            .alert("无法保存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.large])
        .onAppear {
            // 编辑温度回填（环境对象在 onAppear 可用）
            if case .edit(let r) = mode, let t = store.tempC(for: r.id) {
                hasTemp = true
                tempValue = t
            }
        }
    }

    // MARK: 从「车况」带入（合并后两套数据同进程，省去手抄里程与电量）
    @ViewBuilder private var snapshotFill: some View {
        if let snap = carModel.snapshot, snap.odometer != nil || snap.battery != nil {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    if let odo = snap.odometer { odoStr = String(odo) }
                    if let b = snap.battery { socAStr = String(b) }
                } label: {
                    Label("从车况带入里程与当前电量", systemImage: "arrow.down.circle")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.brand)

                Text("来自车况最近一次刷新（\(VehicleFormat.timeText(snap.fetchTime))"
                     + (snap.isFresh ? "，15 分钟内" : "，可能已过期") + "）")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 实时预览（按插入位置推算：行驶里程 = 草稿 − 上一笔，与引擎同口径）
    struct Preview { var kind: RowKind; var distance: Double?; var consumption: Double?; var costPerKm: Double? }
    @State private var formID = UUID()

    @ViewBuilder private var livePreview: some View {
        if store.activeVehicle != nil, let p = previewResult() {
            VStack(alignment: .leading, spacing: 6) {
                switch p.kind {
                case .first:
                    Label("第一笔记录：作为里程基准保存，累计金额照常计入", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundColor(Color(red: 0.05, green: 0.6, blue: 0.4))
                case .rollback:
                    Label("里程读数小于上一笔，该区间将被过滤，请检查是否填错", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundColor(.orange)
                case .ok:
                    VStack(alignment: .leading, spacing: 4) {
                        Text("实时预览（相对上一笔）").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            Text("行驶 \(Fmt.dec(p.distance, 0)) km").font(.subheadline.weight(.semibold))
                            Text("电耗 \(Fmt.dec(p.consumption, 1)) kWh/100km").font(.subheadline.weight(.semibold))
                            Text("成本 \(Fmt.dec(p.costPerKm, 2)) 元/km").font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.kind == .rollback ? Color.orange.opacity(0.1) : Color(red: 0.05, green: 0.6, blue: 0.4).opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var draft: ChargeRecord {
        let existingID: UUID = {
            if case .edit(let r) = mode { return r.id }
            return formID
        }()
        return ChargeRecord(
            id: existingID,
            vehicleID: store.activeVehicle?.id ?? UUID(),
            date: date,
            odometerKm: Double(odoStr) ?? 0,
            energyKWh: Double(energyStr) ?? 0,
            costCNY: Double(costStr) ?? 0,
            chargerType: chargerType.rawValue,
            socBefore: Double(socBStr),
            socAfter: Double(socAStr),
            note: note,
            createdAt: Date()
        )
    }

    private func previewResult() -> Preview? {
        guard let v = store.activeVehicle else { return nil }
        let others = store.records
            .filter { $0.vehicleID == v.id && $0.id != draft.id }
            .sorted { a, b in a.date == b.date ? a.createdAt < b.createdAt : a.date < b.date }
        // 插入位置
        let ins = others.firstIndex { $0.date > draft.date || ($0.date == draft.date && $0.createdAt > draft.createdAt) } ?? others.count
        guard ins > 0 else { return Preview(kind: .first, distance: nil, consumption: nil, costPerKm: nil) }
        let prev = others[ins - 1]
        let d = draft.odometerKm - prev.odometerKm
        if d <= 0 {
            return Preview(kind: .rollback, distance: nil, consumption: nil, costPerKm: nil)
        }
        let cons = draft.energyKWh > 0 ? draft.energyKWh / d * 100 : nil
        let ckm = draft.costCNY > 0 ? draft.costCNY / d : nil
        return Preview(kind: .ok, distance: d, consumption: cons, costPerKm: ckm)
    }

    private func save() {
        // 校验
        guard let v = store.activeVehicle else { return }
        let odo = Double(odoStr)
        guard let odo, odo > 0 else { errorMessage = "里程表读数为必填项"; return }
        let energy = Double(energyStr) ?? 0
        guard energy >= 0 else { errorMessage = "充电量需 ≥ 0"; return }
        let cost = Double(costStr) ?? 0
        guard cost >= 0 else { errorMessage = "金额需 ≥ 0"; return }
        if let sb = Double(socBStr), (sb < 0 || sb > 100) { errorMessage = "电量需在 0–100 之间"; return }
        if let sa = Double(socAStr), (sa < 0 || sa > 100) { errorMessage = "电量需在 0–100 之间"; return }

        let rec = ChargeRecord(
            id: draft.id,
            vehicleID: v.id,
            date: date,
            odometerKm: odo,
            energyKWh: energy,
            costCNY: cost,
            chargerType: chargerType.rawValue,
            socBefore: Double(socBStr),
            socAfter: Double(socAStr),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: isEdit ? (original?.createdAt ?? Date()) : Date()
        )
        let ok = store.saveRecord(rec)
        if ok {
            // P1：记住桩型，供下次“新记录”默认
            store.lastChargerType = chargerType.rawValue
            // P2：温度标签写入 UserDefaults 元数据
            if hasTemp { store.setTempC(tempValue, for: rec.id) } else { store.setTempC(nil, for: rec.id) }
            // P2：跨月预算标记自动重置
            store.resetBudgetNotifyFlagForNewMonth()
            // P1：编辑撤销（还原为保存前的原记录）
            if isEdit, let original {
                store.offerUndo(kind: .edit, message: "记录已更新", record: original)
            }
            dismiss()
        } else {
            errorMessage = "保存失败：本地存储写入出错，请重试"
        }
    }

    // MARK: - 小组件
    private func group<Content: View>(label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func field(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            TextField(title, text: text)
                .keyboardType(.decimalPad)
            Text(unit).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
