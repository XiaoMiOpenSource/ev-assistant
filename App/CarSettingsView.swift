import SwiftUI

/// 设置页（数据源 / 车辆信息 / 外观 / 操作）
struct CarSettingsView: View {
    @EnvironmentObject private var model: CarModel
    @Environment(\.dismiss) private var dismiss
    @State private var cfg = SharedStore.loadConfig()
    @State private var showPreview = false
    @State private var refreshState: String?
    @FocusState private var cltcFocused: Bool
    @FocusState private var amapFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        TextField("API 地址（车辆数据聚合接口）", text: $cfg.apiURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !cfg.apiURL.isEmpty {
                            Button {
                                cfg.apiURL = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清除 API 地址")
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("高德 Web 服务 Key（选填，用于显示地址）", text: Binding(
                            get: { cfg.amapKey ?? "" },
                            set: { cfg.amapKey = $0.isEmpty ? nil : $0 }
                        ))
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($amapFocused)
                        if !(cfg.amapKey ?? "").isEmpty {
                            Button {
                                cfg.amapKey = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("清除高德 Key")
                        }
                    }
                } header: {
                    Text("数据源")
                } footer: {
                    Text("接口需返回 { \"data\": { \"vehicle_value\": {...}, \"vehicle_state\": {...}, \"vehicle_position\": \"纬度,经度\" } } 结构。填了「高德 Web 服务 Key」时，App 会额外请求高德逆地理编码（restapi.amap.com），把车辆坐标换成中文地址显示在车况页底部；不填则完全不请求第三方，位置只显示「已定位」与坐标本身，坐标不外发。")
                }

                Section {
                    TextField("车型", text: $cfg.carModel)
                    TextField("车辆昵称", text: $cfg.carName)
                    TextField("车牌号", text: $cfg.carPlate)
                        .textInputAutocapitalization(.characters)
                    TextField("车辆识别码（VIN）", text: $cfg.carVin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Picker("车辆颜色", selection: $cfg.carColor) {
                        ForEach(Array(AppConfig.colorNames.keys), id: \.self) { key in
                            Text(AppConfig.colorNames[key] ?? key).tag(key)
                        }
                    }
                    TextField("CLTC 标称续航（km）", text: Binding(
                        get: { cfg.cltcNominal.map { String($0) } ?? "" },
                        set: { cfg.cltcNominal = Int($0.trimmingCharacters(in: .whitespaces)) }
                    ))
                    .keyboardType(.numberPad)
                    .focused($cltcFocused)
                } header: {
                    Text("车辆信息")
                } footer: {
                    Text("CLTC 标称续航用于计算车况页的「续航达成率」（按当前能耗折算的满电续航 ÷ 标称）。留空则自动采用接口上报的 battery_pack_range；若与你的车型官方标称不符，可手动填写覆盖。")
                }

                Section("外观") {
                    Picker("主题", selection: $cfg.theme) {
                        ForEach(Array(AppConfig.themeNames.keys), id: \.self) { key in
                            Text(AppConfig.themeNames[key] ?? key).tag(key)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section {
                    Toggle("地图坐标修正", isOn: $cfg.mapFix)
                    if cfg.latOff != 0 || cfg.lngOff != 0 {
                        Button("清除手动校准偏移", role: .destructive) {
                            cfg.latOff = 0
                            cfg.lngOff = 0
                            model.saveConfig(cfg)
                        }
                    }
                } header: {
                    Text("地图")
                } footer: {
                    Text("若车辆接口上报的是 GPS 坐标（WGS-84），国内地图（Apple/高德）上会偏移几百米；开启后自动转换为国内地图坐标（GCJ-02），地图标记、导航与地址都会一起修正。若你的接口已是火星坐标则保持关闭。")
                }

                Section {
                    Toggle("未锁 / 门窗未关提醒", isOn: $cfg.lockRemind)
                    Toggle("低电量充电提醒", isOn: $cfg.lowBatteryRemind)
                    if cfg.lowBatteryRemind {
                        HStack {
                            Text("低电量阈值")
                            Spacer()
                            Stepper("\(cfg.lowBatteryThreshold)%",
                                    value: $cfg.lowBatteryThreshold, in: 5...50, step: 5)
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("提醒")
                } footer: {
                    Text("「未锁/门窗未关」：刷新发现未上锁或门窗未关且连续两次仍如此时发送本地通知；「低电量充电」：电量 ≤ 阈值且未充电时车况页顶部横幅提示，刷新时发送本地通知（20 分钟内不重复打扰，充电中或电量回升后解除）。桌面/锁屏小组件低电量时同步显示红色「请充电」标识。需在系统弹窗中允许通知。")
                }

                Section {
                    Button {
                        Task { await doRefresh() }
                    } label: {
                        HStack {
                            Text("立即刷新车况")
                            if model.isLoading {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.config.needsSetup)

                    Button("预览小组件") { showPreview = true }
                    Button("载入演示数据") { model.loadDemoData() }

                    if let state = refreshState {
                        Text(state)
                            .font(.footnote)
                            .foregroundColor(state.contains("成功") ? .green : .secondary)
                    }
                } header: {
                    Text("操作")
                } footer: {
                    Text("提示：保存后先返回桌面把“MG4 车况”小组件添加到主屏幕，即可在主屏直接查看车况。")
                }
            }
            .onAppear {
                #if DEBUG
                if CommandLine.arguments.contains("-filldemo") {
                    if cfg.apiURL.isEmpty { cfg.apiURL = "https://example.com/api/vehicle/status" }
                }
                #endif
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if cltcFocused || amapFocused {
                        Spacer()
                        Button("完成") {
                            cltcFocused = false
                            amapFocused = false
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showPreview) {
                WidgetPreviewSheet()
                    .environmentObject(model)
            }
        }
    }

    private func save() {
        model.saveConfig(cfg)
        dismiss()
    }

    private func doRefresh() async {
        model.saveConfig(cfg)
        await model.refresh()
        refreshState = model.errorMessage == nil ? "刷新成功 ✓" : nil
    }
}

/// 小组件三尺寸预览（数据来自共享存储，与桌面小组件一致）
struct WidgetPreviewSheet: View {
    @EnvironmentObject private var model: CarModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme

    private var content: WidgetContent {
        var c = WidgetContent(snapshot: model.snapshot ?? VehicleSnapshot.demo(),
                              config: model.config,
                              carImage: CarImageStore.localImage(color: model.config.carColor))
        if model.snapshot == nil && model.config.needsSetup {
            c.snapshot = VehicleSnapshot.demo()
        }
        return c
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    previewRow(title: "小号", size: CGSize(width: 155, height: 155)) {
                        layout(.systemSmall)
                    }
                    previewRow(title: "中号", size: CGSize(width: 329, height: 155)) {
                        layout(.systemMedium)
                    }
                    previewRow(title: "大号", size: CGSize(width: 329, height: 345)) {
                        layout(.systemLarge)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("小组件预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func layout(_ family: MG4WidgetFamily) -> some View {
        let cfg = content.config
        let snap = content.snapshot ?? .demo()
        let palette = resolvePalette(config: cfg, systemDark: systemScheme == .dark)
        return ZStack {
            palette.bg
            switch family {
            case .systemSmall:
                SmallLayout(snap: snap, palette: palette, carImage: content.carImage, cfg: cfg)
            case .systemMedium:
                MediumLayout(snap: snap, palette: palette, carImage: content.carImage, cfg: cfg)
            case .systemLarge:
                LargeLayout(snap: snap, palette: palette, carImage: content.carImage, cfg: cfg)
            case .systemAccessoryRectangular:
                LockRectLayout(snap: snap, threshold: cfg.lowBatteryThreshold)
            }
        }
    }

    private func previewRow<Content: View>(title: String, size: CGSize,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
            content()
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
        }
    }
}
