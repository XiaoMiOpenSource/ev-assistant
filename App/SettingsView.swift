import SwiftUI
import UniformTypeIdentifiers

// MARK: - 设置 Tab
struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var carModel: CarModel
    @State private var showCarSettings = false
    @State private var showBackupCenter = false
    @State private var vehicleForm: VehicleFormTarget?
    @State private var confirmReset = false
    @State private var toastMsg: String?
    // P2：预算（展示态 / 编辑态）
    @State private var budgetText = ""          // 编辑缓冲，取消时不落库
    @State private var isEditingBudget = false
    @State private var showDeleteBudget = false
    @FocusState private var budgetFocused: Bool
    // P3：本地备份 / 恢复

    enum VehicleFormTarget: Identifiable {
        var id: String { vehicle?.id.uuidString ?? "new" }
        case new
        case edit(Vehicle)
        var vehicle: Vehicle? { if case .edit(let v) = self { return v }; return nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                vehiclesSection
                carSourceSection
                budgetSection
                rateSection
                dataSection
                infoSection
            }
            .onAppear {
                #if DEBUG
                let args = CommandLine.arguments
                if args.contains("-showbackup") || args.contains("-backup") || args.contains("-exportcsv")
                    || args.contains("-restorefile") || args.contains("-restoretest") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { showBackupCenter = true }
                }
                if args.contains("-carsettings") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { showCarSettings = true }
                }
                #endif
            }
            .navigationTitle("设置")
            .sheet(item: $vehicleForm) { target in
                VehicleFormView(target: target)
                    .environmentObject(store)
            }
            .navigationDestination(isPresented: $showBackupCenter) {
                BackupCenterView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showCarSettings) {
                CarSettingsView()
                    .environmentObject(carModel)
            }
            .alert("清空全部数据", isPresented: $confirmReset) {
                Button("取消", role: .cancel) {}
                Button("确定清空", role: .destructive) {
                    store.eraseAll()
                    toastMsg = "已清空全部本地数据"
                }
            } message: {
                Text("将删除本机全部车辆与充电记录，且无法恢复。")
            }
            .overlay(alignment: .bottom) {
                if let toastMsg {
                    Text(toastMsg).font(.footnote)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(Color(.label).opacity(0.85))
                        .foregroundColor(Color(.systemBackground))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                        .transition(.opacity)
                        .task(id: toastMsg) {
                            try? await Task.sleep(nanoseconds: 1_800_000_000)
                            withAnimation { self.toastMsg = nil }
                        }
                }
            }
        }
    }

    // MARK: - P2 月预算
    /// 统一风格的操作按钮：实心（主色）/ 浅底（警示色），圆角 10、图标与文字间距 4、禁用态降透明度
    private func budgetButton(_ title: String, icon: String, tint: Color, filled: Bool,
                              disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(filled ? tint : tint.opacity(0.12))
            .foregroundColor(filled ? .white : tint)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: 状态切换
    private func beginEditBudget() {
        budgetText = store.monthlyBudget > 0 ? String(format: "%.0f", store.monthlyBudget) : ""
        isEditingBudget = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { budgetFocused = true }   // 自动聚焦
    }
    /// 取消：丢弃编辑缓冲，不落库
    private func cancelEditBudget() {
        budgetText = ""
        isEditingBudget = false
        budgetFocused = false
        endEditing()
    }
    private var budgetValue: Double? {
        guard let v = Double(budgetText.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return v
    }
    private func commitBudget() {
        guard let v = budgetValue else { return }          // 非法金额不保存、不退出
        store.monthlyBudget = min(v, 1_000_000)
        store.requestNotifyAuthIfNeeded()
        toastMsg = "已保存预算 ¥\(Int(store.monthlyBudget))"
        cancelEditBudget()
    }
    private func deleteBudget() {
        store.monthlyBudget = 0
        toastMsg = "已删除预算"
        cancelEditBudget()
    }
    /// 输入校验：只保留数字与一个小数点，最多 2 位小数，正数，限长 12
    static func sanitizeAmount(_ s: String) -> String {
        var t = s.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
        if let dot = t.firstIndex(of: ".") {
            let intPart = String(t[..<dot]).filter(\.isNumber)
            let decPart = String(t[t.index(after: dot)...]).filter(\.isNumber)
            t = intPart + "." + String(decPart.prefix(2))
        }
        while t.count > 1 && t.hasPrefix("0") && !t.hasPrefix("0.") { t.removeFirst() }
        return String(t.prefix(12))
    }

    // MARK: 展示态
    private var budgetDisplayRow: some View {
        Button { beginEditBudget() } label: {
            HStack(spacing: 10) {
                Text("月预算")
                Spacer(minLength: 6)
                Text(store.monthlyBudget > 0
                     ? "¥\(Int(store.monthlyBudget.rounded()))"
                     : "点击设置月预算")
                    .font(.subheadline)
                    .foregroundColor(store.monthlyBudget > 0 ? .primary : .secondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 编辑态
    private var budgetEditRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 上：金额输入（自动聚焦 / 数字键盘 / 可一键清空）
            HStack(spacing: 10) {
                Text("月预算").foregroundStyle(.secondary)
                    .onTapGesture { cancelEditBudget() }        // 点标题=取消
                Spacer(minLength: 6)
                TextField("0", text: $budgetText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: 180)
                    .focused($budgetFocused)
                    .submitLabel(.done)
                    .onSubmit { commitBudget() }
                    .onChange(of: budgetText) { budgetText = Self.sanitizeAmount($0) }
                if !budgetText.isEmpty {
                    Button { budgetText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            // 下：确定 / 删除
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                budgetButton("确定", icon: "checkmark", tint: .brand, filled: true,
                             disabled: budgetValue == nil) { commitBudget() }
                budgetButton("删除", icon: "trash", tint: .red, filled: false,
                             disabled: store.monthlyBudget <= 0) { showDeleteBudget = true }
            }
        }
        .padding(.vertical, 2)
        // 点空白区域 = 取消编辑
        .background { Color.clear.contentShape(Rectangle()).onTapGesture { cancelEditBudget() } }
        .alert("删除月预算", isPresented: $showDeleteBudget) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) { deleteBudget() }
        } message: {
            Text("确认清除已设置的月预算？清除后将不再发送预算提醒。")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("取消") { cancelEditBudget() }
            }
        }
    }

    private var budgetSection: some View {
        Section {
            if isEditingBudget { budgetEditRow } else { budgetDisplayRow }
            HStack {
                Text("本月已用")
                Spacer()
                Text("¥\(Int(store.currentMonthCostCNY().rounded()))")
                    .fontWeight(.semibold)
                    .foregroundColor(store.hasBudget && store.currentMonthCostCNY() >= store.monthlyBudget ? .red : .primary)
            }
        } header: {
            Text("预算与提醒")
        } footer: {
            Text("开启后：某月累计充电费达到预算时发送一次本地通知提醒（跨月自动重置）。需允许通知权限。")
        }
    }

    // MARK: 车辆
    private var vehiclesSection: some View {
        Section {
            ForEach(store.vehicles) { v in
                Button {
                    vehicleForm = .edit(v)
                } label: {
                    HStack {
                        Image(systemName: "car.fill").foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(v.name).fontWeight(.medium)
                                if v.id == store.activeVehicleID {
                                    Text("当前").font(.caption2).padding(.horizontal, 6).padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.15)).foregroundColor(.blue).clipShape(Capsule())
                                }
                            }
                            Text("标称 \(Fmt.int(v.ratedRangeKm)) km · \(RangeStandard(raw: v.rangeStandard).name) · 电池 \(Fmt.dec(v.batteryKWh, 1)) kWh")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                indexSet.forEach { idx in
                    guard store.vehicles.indices.contains(idx) else { return }
                    let v = store.vehicles[idx]
                    if store.records.contains(where: { $0.vehicleID == v.id }) {
                        toastMsg = "该车辆已有记录，不能删除"
                    } else {
                        store.deleteVehicle(v.id)
                    }
                }
            }

            Button {
                vehicleForm = .new
            } label: {
                Label("添加车辆", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("车辆与基准")
        } footer: {
            Text("多车数据完全隔离，统计跟随当前车辆。标称续航用于计算续航达成率。")
        }
    }

    // MARK: 达成率口径
    private var rateSection: some View {
        Section {
            Picker("统计窗口", selection: Binding(get: { store.window }, set: { store.setWindow($0) })) {
                ForEach(StatsWindow.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            HStack {
                Text("状态阈值")
                Spacer()
                Text("≥100% 超达成 · 80–100% 正常 · <80% 提示")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("达成率口径")
        } footer: {
            Text("窗口越短对季节与工况越敏感（冬季达成率下降属正常），建议近 3 月。")
        }
    }

    // MARK: 数据
    private var dataSection: some View {
        Section {
            Button {
                showBackupCenter = true
            } label: {
                HStack {
                    Label("备份与恢复", systemImage: "externaldrive")
                    Spacer()
                    Text("\(store.autoBackupFiles().count) 份自动备份")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("清空全部数据", systemImage: "trash")
            }
        } header: {
            Text("数据")
        } footer: {
            Text("纯本地方案：数据仅存本机，不上传任何云端。完整备份（JSON）、本机自动备份与 CSV 导出都收在「备份与恢复」里。当前共 \(store.records.count) 笔记录 / \(store.vehicles.count) 辆车")
        }
    }

    // MARK: 车况数据源（合并自原「车况」App，入口收敛到设置页）
    private var carSourceSection: some View {
        Section {
            Button {
                showCarSettings = true
            } label: {
                HStack {
                    Label("车况数据源与提醒", systemImage: "car.side")
                    Spacer()
                    Text(carModel.config.needsSetup ? "未配置" : "已配置")
                        .font(.caption)
                        .foregroundStyle(carModel.config.needsSetup ? .orange : .secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("车况")
        } footer: {
            Text("配置车辆数据接口、车辆信息、低电量与未锁提醒；「车况」页右上角齿轮进入同一页面。")
        }
    }

    private var infoSection: some View {
        Section {
            LabeledContent("版本", value: "电车助手 v\(Store.appVersionString)")
        } header: {
            Text("关于")
        }
    }

}

// MARK: - Share sheet（iOS16 兼容）
struct ShareItem: Identifiable { let id = UUID(); let url: URL }
// MARK: - 车辆编辑表单
struct VehicleFormView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let target: SettingsView.VehicleFormTarget

    @State private var name = ""
    @State private var ratedStr = ""
    @State private var batteryStr = ""
    @State private var usableStr = ""
    @State private var standard: Int16 = 0
    @State private var errorMsg: String?

    init(target: SettingsView.VehicleFormTarget) {
        self.target = target
        if let v = target.vehicle {
            _name = State(initialValue: v.name)
            _ratedStr = State(initialValue: Fmt.dec(v.ratedRangeKm, 1))
            _batteryStr = State(initialValue: Fmt.dec(v.batteryKWh, 1))
            _usableStr = State(initialValue: v.usableKWh.map { Fmt.dec($0, 2) } ?? "")
            _standard = State(initialValue: v.rangeStandard)
        }
    }

    private var isEdit: Bool { target.vehicle != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("昵称（如：我的海豹 EV）", text: $name)
                    TextField("标称续航 km", text: $ratedStr).keyboardType(.decimalPad)
                    TextField("电池容量 kWh", text: $batteryStr).keyboardType(.decimalPad)
                } header: {
                    Text("车辆信息")
                }
                Section {
                    Picker("来源", selection: $standard) {
                        Text("CLTC（默认）").tag(Int16(0))
                        Text("WLTP").tag(Int16(1))
                        Text("自定义").tag(Int16(2))
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("标称续航来源")
                } footer: {
                    Text("同车 CLTC 与 WLTP 差异可达 10–15%，来源直接决定达成率数值")
                }
                Section {
                    TextField("可用电量 kWh（留空 = 标称 × 0.9）", text: $usableStr).keyboardType(.decimalPad)
                } header: {
                    Text("进阶")
                } footer: {
                    Text("能耗换算法精度取决于可用电量；真实可用通常低于标称容量（锁电）")
                }
                if isEdit, let v = target.vehicle,
                   !store.records.contains(where: { $0.vehicleID == v.id }) {
                    Section {
                        Button(role: .destructive) {
                            store.deleteVehicle(v.id)
                            dismiss()
                        } label: {
                            Text("删除车辆").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isEdit ? "编辑车辆" : "添加车辆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.fontWeight(.semibold) }
            }
            .alert("无法保存", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(errorMsg ?? "") }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { errorMsg = "请填写车辆昵称"; return }
        guard let rated = Double(ratedStr), rated > 0 else { errorMsg = "请填写有效的标称续航"; return }
        guard let batt = Double(batteryStr), batt > 0 else { errorMsg = "请填写有效的电池容量"; return }
        var usable: Double?
        if !usableStr.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let u = Double(usableStr), u > 0 else { errorMsg = "可用电量需大于 0"; return }
            usable = u
        }
        let v: Vehicle
        if let old = target.vehicle {
            v = Vehicle(id: old.id, name: n, ratedRangeKm: rated, rangeStandard: standard,
                        batteryKWh: batt, usableKWh: usable, createdAt: old.createdAt)
        } else {
            v = Vehicle(id: UUID(), name: n, ratedRangeKm: rated, rangeStandard: standard,
                        batteryKWh: batt, usableKWh: usable, createdAt: Date())
        }
        store.saveVehicle(v)
        dismiss()
    }
}
