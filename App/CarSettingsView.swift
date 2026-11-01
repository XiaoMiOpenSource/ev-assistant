import SwiftUI

/// 设置页（数据源 / 车辆信息 / 外观 / 操作）
struct CarSettingsView: View {
    @EnvironmentObject private var model: CarModel
    @Environment(\.dismiss) private var dismiss
    @State private var cfg = SharedStore.loadConfig()
    @State private var showPreview = false
    @State private var refreshState: String?
    @State private var captureText = ""
    @State private var captureHint: String?
    @FocusState private var cltcFocused: Bool
    @FocusState private var amapFocused: Bool

    /// 作为「设置」里的二级页面被 push 时置 true：
    /// 不再自带 NavigationStack（否则导航栈套两层），也不再显示「取消」——系统返回按钮已经够了。
    var embedded: Bool = false
    /// 导航标题：弹窗里是「设置」，嵌进设置页时是「车况数据源」
    var title: String = "设置"

    var body: some View {
        if embedded {
            formContent
        } else {
            NavigationStack { formContent }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
            Section {
                // 从抓包里一键填入：粘贴整条 getVehicleStatus 请求 URL，
                // 自动取 appId / VIN / token，并把 data 里的 timestamp 换成当前时间
                VStack(alignment: .leading, spacing: 6) {
                    TextField("粘贴抓包里的完整请求 URL", text: $captureText, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.caption.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack(spacing: 10) {
                        Button("解析并填入") { applyCapture(captureText) }
                            .buttonStyle(.borderedProminent)
                            .disabled(captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let captureHint {
                            Text(captureHint)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 2)

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
                TextField("电池容量（kWh）", text: Binding(
                    get: { cfg.packKWh.map { String(format: "%g", $0) } ?? "" },
                    set: { cfg.packKWh = Double($0.trimmingCharacters(in: .whitespaces)) }
                ))
                .keyboardType(.decimalPad)
                // 一键套用官方参数，省得手敲；点完 CLTC 与容量一起填好
                HStack(spacing: 8) {
                    ForEach(AppConfig.packPresets) { preset in
                        Button {
                            cfg.packKWh = preset.kwh
                            cfg.cltcNominal = preset.cltc
                        } label: {
                            Text(preset.label.replacingOccurrences(of: "MG4 ", with: ""))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(Color.brand.opacity(0.12)))
                                .foregroundColor(.brand)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
                Toggle("里程单位为 0.1 km（数值 ÷10）", isOn: $cfg.odometerInDecikm)
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("诊断信息（原始响应 / 定位质量 / 充电状态码）", systemImage: "stethoscope")
                        .font(.footnote)
                }
            } header: {
                Text("车辆信息")
            } footer: {
                Text("CLTC 标称续航用于计算车况页的「续航达成率」；电池容量用于把电量百分比换算成「剩余电量 kWh」。两者都可一键套用上方预设。注意：接口返回的 battery_pack_range 是当前可跑里程，不是 CLTC 标称，已不再拿它兜底。")
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
        .navigationTitle(title)
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
            if !embedded {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showPreview) {
            WidgetPreviewSheet()
                .environmentObject(model)
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
    /// 解析粘贴的抓包 URL：取出 data 里的 appId / vin / token，
    /// 把 timestamp 换成当前毫秒时间戳后回写到 apiURL（时间戳服务端不校验，但换新更稳）。
    private func applyCapture(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              var comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dataValue = comps.queryItems?.first(where: { $0.name == "data" })?.value,
              let jsonData = dataValue.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any] else {
            captureHint = "没解析出 data 参数，请确认粘贴的是完整请求 URL（含 ?data=…）"
            return
        }
        var payload = obj
        payload["timestamp"] = String(Int(Date().timeIntervalSince1970 * 1000))
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: encoded, encoding: .utf8) else {
            captureHint = "重组 data 失败，请检查抓包内容是否被截断"
            return
        }
        comps.queryItems = [URLQueryItem(name: "data", value: text)]
        guard let finalURL = comps.url?.absoluteString else {
            captureHint = "生成接口地址失败"
            return
        }
        cfg.apiURL = finalURL
        let vin = (payload["vin"] as? String) ?? ""
        if !vin.isEmpty { cfg.carVin = vin }
        let appId = (payload["appId"] as? String) ?? "?"
        let tokenOK = ((payload["token"] as? String) ?? "").isEmpty == false
        captureHint = "已填入：appId \(appId)、VIN \(vin.isEmpty ? "?" : vin)；token \(tokenOK ? "已读取" : "缺失")，时间戳已更新"
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

/// 诊断信息页：把「车端时间 / 定位质量 / 充电状态码 / 最近一次原始响应」摊开，
/// 出问题时截图即可定位，不用再让用户翻抓包。
struct DiagnosticsView: View {
    @EnvironmentObject private var model: CarModel
    @State private var raw: String?

    private var snap: VehicleSnapshot? { model.snapshot }

    private var pmText: String {
        let parts = [snap?.pm25Interior, snap?.pm25Exterior].compactMap { $0 }.map(String.init)
        return parts.isEmpty ? "—" : parts.joined(separator: " / ")
    }

    var body: some View {
        Form {
            Section("时间") {
                row("车端数据时间", snap?.vehicleTime.map(Self.fmt) ?? "—")
                row("本机抓取时间", snap?.fetchTime.map(Self.fmt) ?? "—")
                row("位置数据时间", snap?.positionTime.map(Self.fmt) ?? "—")
                row("位置是否滞后", snap?.positionIsStale == true ? "是（超过 30 分钟）" : "否")
            }
            Section("定位质量") {
                row("卫星数", snap?.satellites.map(String.init) ?? "—")
                row("hdop", snap?.hdop.map(String.init) ?? "—")
                row("gps_status", snap?.gpsStatus.map(String.init) ?? "—")
                row("海拔（m）", snap?.altitude.map(String.init) ?? "—")
                row("位置授权", snap?.positionAuthorized.map { $0 ? "允许" : "已关闭（车机隐私设置）" } ?? "—")
            }
            Section("充电 / 环境") {
                row("充电状态", snap?.chargeStatusText ?? "—")
                row("charge_status 码", snap?.chargeStatusCode.map(String.init) ?? "—")
                row("充电剩余", snap?.chargeRemainingMinutes.map { "\($0) 分钟" } ?? "—")
                row("车外温度", snap?.exteriorTemp.map { "\($0) ℃" } ?? "—")
                row("PM2.5 内 / 外", pmText)
            }
            Section {
                if let raw, !raw.isEmpty {
                    ScrollView {
                        Text(raw)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 280)
                } else {
                    Text("还没有抓取过（或接口返回为空）")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Button("重新读取原始响应") { raw = SharedStore.loadLastRaw() }
            } header: {
                Text("最近一次原始响应")
            } footer: {
                Text("原始响应只保留最近一次、截断到 60 KB，存在 App Group 里，不会上传。")
            }
        }
        .navigationTitle("诊断信息")
        .onAppear { raw = SharedStore.loadLastRaw() }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
            Spacer(minLength: 8)
            Text(value)
                .foregroundColor(.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: d)
    }
}
