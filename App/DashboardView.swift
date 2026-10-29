import SwiftUI
import UIKit
import MapKit
import WidgetKit

/// 仪表页
struct DashboardView: View {
    @EnvironmentObject private var model: CarModel
    @Environment(\.colorScheme) private var systemScheme
    @State private var showSettings = false
    @State private var showPreview = false
    @State private var didAutoRefresh = false

    private var palette: Palette {
        resolvePalette(config: model.config, systemDark: systemScheme == .dark)
    }

    var body: some View {
        let _ = DiagLog.once("dash.body", "snapshot=\(model.snapshot.map { _ in "有" } ?? "nil") loading=\(model.isLoading)")
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let snap = model.snapshot {
                        content(for: snap)
                    } else if model.config.needsSetup {
                        setupCard
                    } else {
                        noDataCard
                    }

                    if model.config.needsSetup && model.snapshot != nil {
                        setupHintBar
                    }

                    if let err = model.errorMessage {
                        errorBanner(err)
                    }

                    footNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            // 标题固定：内嵌(居中)显示于顶部导航栏，上下滚动页面时不随内容移动
            .navigationTitle("车况")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if model.isLoading {
                        ProgressView()
                    } else {
                        Button { Task { await model.refresh() } } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(model.config.needsSetup)
                    }
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                // 与「设置 → 车况数据源」是同一份表单（CarSettingsView）；
                // 这里只是车况页的快捷入口，不再单独维护一套配置界面。
                CarSettingsView(title: "车况数据源")
                    .environmentObject(model)
            }
            .sheet(isPresented: $showPreview) {
                WidgetPreviewSheet()
                    .environmentObject(model)
            }
            .onOpenURL { url in
                // 小组件点击（mg4widget://status）→ 直接落在车况主界面；
                // 仅预览深链 mg4widget://preview 用于直达“小组件预览”
                guard url.scheme == "mg4widget", url.host == "preview" else { return }
                showPreview = true
            }
            .task {
                // 调试用：-mock <url> 直连本地 mock 服务器拉取真实数据；-demo 载入演示数据
                if let idx = CommandLine.arguments.firstIndex(of: "-mock"),
                   CommandLine.arguments.count > idx + 1 {
                    model.config.apiURL = CommandLine.arguments[idx + 1]
                    SharedStore.saveConfig(model.config)
                    await model.refresh()
                }
                if CommandLine.arguments.contains("-demo") { model.loadDemoData() }
                if CommandLine.arguments.contains("-lowdemo") { model.loadLowDemoData() }
                // 首次启动延迟刷新时间线：缓解 TrollStore 无证书环境下
                // “刚装好桌面小组件空白、必须重启手机才恢复”的扩展注册/调度问题
                if !didAutoRefresh {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    WidgetCenter.shared.reloadAllTimelines()
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    WidgetCenter.shared.reloadAllTimelines()
                }
                guard !didAutoRefresh else { return }
                didAutoRefresh = true
                await model.autoRefreshIfNeeded()
            }
        }
    }

    // MARK: - 未配置状态

    private var setupCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 34))
                .foregroundColor(palette.orange)
            Text("还未配置车辆数据源")
                .font(.headline)
            Text("在设置中填入 API 地址后即可拉取车况（字段格式与 Scriptable 版脚本一致）。也可以先载入演示数据预览效果。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("载入演示数据") { model.loadDemoData() }
                    .buttonStyle(.bordered)
                Button("去配置") { showSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    /// 未配置 API 但有缓存/演示数据时的提示条
    private var setupHintBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(palette.orange)
            Text("尚未配置 API 地址，当前显示缓存/演示数据")
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
            Button("去配置") { showSettings = true }
                .font(.footnote.weight(.semibold))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private var noDataCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "car.side")
                .font(.system(size: 34))
                .foregroundColor(palette.sub)
            Text("暂无车况数据，点击右上角刷新")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("预览小组件") { showPreview = true }
                .font(.footnote)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color.dsDanger)
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private var footNote: some View {
        HStack(spacing: 5) {
            Image(systemName: "info.circle")
                .font(.caption2)
            Text("折算达成率＝满电动态续航 ÷ CLTC 标称；统计页为能耗换算口径，两者可能不同")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.bottom, 8)
    }

    // MARK: - 有数据时

    private func content(for snap: VehicleSnapshot) -> some View {
        VStack(spacing: Space.gap) {
            heroCard(snap)       // 身份 + 电量 / 续航 / 里程：原来两张卡，合并成一张主卡
            if model.config.lowBatteryRemind,
               snap.needsCharge(threshold: model.config.lowBatteryThreshold) {
                lowBatteryBanner(snap)   // 低电量充电提醒横幅
            }
            safetyCard(snap)     // 门锁 + 门窗：合成「安全状态」，一眼看完
            statGrid(snap)
            tyreCard(snap)
            locationCard(snap)
        }
    }

    /// 主卡 —— G-L1 排版：左边一个电量仪表，右边是结论，底部胶囊流收纳台账
    ///
    /// 骨架（两条竖轴，不用横排数据行）：
    ///   左轴 = 电量环（与上方车型、车牌共用同一条左边线）
    ///   右轴 = 续航大数字 + 「km 剩余续航」+「满电约 xxx km」，三行与环等高
    ///   底部 = WrapLayout 胶囊流（总里程 / VIN / 更新时间），宽度不够自动折行
    /// 数据一个都不少：车型、车名、车牌、车身色、续航、电量、满电动态续航、
    /// 总里程、VIN、充电状态、数据新鲜度都在卡内，只是分了三层字号。
    private func heroCard(_ snap: VehicleSnapshot) -> some View {
        let plate = model.config.carPlate
        let colorName = AppConfig.colorNames[model.config.carColor] ?? model.config.carColor
        let charging = snap.charging == true
        let vin = model.config.carVin
        let battery = min(max(snap.battery ?? 0, 0), 100)
        let lowBattery = battery <= model.config.lowBatteryThreshold
        let rangeText = snap.range.map { $0 == "--" ? "--" : $0 } ?? "--"
        // 满电状态动态续航（km）= 当前续航 ÷ 当前电量 × 100
        let fullDynamic: String = {
            guard let b = snap.battery, b > 0,
                  let r = snap.range.flatMap(Double.init), r > 0 else { return "--" }
            return "\(Int((r / Double(b) * 100.0).rounded())) km"
        }()

        return VStack(alignment: .leading, spacing: 14) {
            // ① 身份：车型/车名 + 车身色
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.config.carModel + (model.config.carName.isEmpty ? "" : " · " + model.config.carName))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Circle()
                        .fill(carColorDot)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(palette.sub.opacity(0.35), lineWidth: 0.5))
                    Text(colorName)
                        .font(.system(size: 12))
                        .foregroundColor(palette.sub)
                        .lineLimit(1)
                }
            }

            // ② 车牌 + 状态胶囊（充电中 / 数据过期）
            HStack(spacing: 8) {
                Text(plate.isEmpty ? "--" : plate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.sub)
                    .lineLimit(1)
                if charging {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                        Text("充电中").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(palette.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(palette.orange.opacity(0.14)))
                }
                if !snap.isFresh {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.badge.exclamationmark").font(.system(size: 9, weight: .bold))
                        Text("数据过期").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color.dsWarn)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.dsWarn.opacity(0.14)))
                }
                Spacer(minLength: 0)
            }

            // ③ 左右对称：环占左半边、续航占右半边，两块各自在本半区居中。
            //    环的圆心与「218」的字面中心落在同一条水平线上，左右视觉重量相等；
            //    原来环贴左、数字贴环，整段挤在左边，右侧空出一大片。
            HStack(alignment: .center, spacing: Space.gap) {
                // 左半：电量仪表
                ZStack {
                    Circle()
                        .stroke(palette.darkGray, lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(battery) / 100)
                        .stroke(lowBattery ? Color.dsDanger : Color.dsOK,
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(snap.battery ?? 0)%")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundColor(palette.text)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("电量")
                            .font(.system(size: 10))
                            .foregroundColor(palette.sub)
                    }
                }
                .frame(width: 84, height: 84)
                .frame(maxWidth: .infinity)   // 在本半区居中

                // 右半：续航结论（标签在上、数字居中、补充说明在下，与左侧圆环镜像）
                VStack(spacing: 2) {
                    Text("剩余续航")
                        .font(.system(size: 12))
                        .foregroundColor(palette.sub)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(rangeText)
                            .font(.system(size: 42, weight: .heavy, design: .rounded))
                            .foregroundColor(palette.text)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("km")
                            .font(.system(size: 15))
                            .foregroundColor(palette.sub)
                    }
                    Text("满电约 \(fullDynamic)")
                        .font(.system(size: 12))
                        .foregroundColor(palette.sub.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)   // 在本半区居中
            }

            // ④ 胶囊流：宽度不够自动折行，不做列对齐
            WrapLayout(spacing: 8, lineSpacing: 6) {
                chip(icon: "road.lanes", text: "\(VehicleFormat.odometer(snap.odometer)) km")
                if !vin.isEmpty {
                    chip(icon: "number", text: "VIN \(vin)")
                }
                chip(icon: "clock", text: freshnessText(snap))
            }
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// 胶囊流里的一枚标签
    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(.system(size: 11))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundColor(palette.sub)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.dsStroke.opacity(0.45)))
    }

    /// 数据新鲜度：车况接口每次刷新都会写 fetchTime
    private func freshnessText(_ snap: VehicleSnapshot) -> String {
        guard let t = snap.fetchTime else { return "更新时间未知" }
        let seconds = Date().timeIntervalSince(t)
        guard seconds.isFinite, seconds >= 0 else { return "刚刚更新" }
        if seconds < 60 { return "刚刚更新" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86_400)) 天前"
    }
    /// 车身颜色展示色点（与 AppConfig.colorNames 的 key 一一对应；白车靠外层浅描边区分底色）
    private var carColorDot: Color {
        switch model.config.carColor {
        case "Purple": return Color(hex: 0x9a5cd9)
        case "Green": return Color(hex: 0x2ec4a8)
        case "Red": return Color(hex: 0xe85a55)
        case "Blue": return Color(hex: 0x4a90d9)
        case "White": return Color(hex: 0xf0f0f2)
        case "Mulan-Grey": return Color(hex: 0x7e8489)
        default: return Color(hex: 0x9aa0a6)   // Grey 星野灰及其它
        }
    }

    /// 低电量充电提醒横幅（电量 ≤ 阈值且未充电时显示，红色浅底突出）
    private func lowBatteryBanner(_ snap: VehicleSnapshot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "battery.25")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(Color.dsDanger)
            VStack(alignment: .leading, spacing: 3) {
                Text("电量低，请及时充电")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(palette.text)
                Text("当前 \(snap.battery ?? 0)% · 低于提醒阈值 \(model.config.lowBatteryThreshold)%"
                     + (snap.isFresh ? "" : " · 数据可能已过期"))
                    .font(.footnote)
                    .foregroundColor(palette.sub)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color.dsDanger.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Color.dsDanger.opacity(0.35), lineWidth: 1)
        )
    }

    private func statGrid(_ snap: VehicleSnapshot) -> some View {
        // 满电状态动态续航（km）= 当前续航 ÷ 当前电量 × 100（主卡已展示，这里只用它算达成率）
        let fullDynamicKM: Double? = {
            guard let b = snap.battery, b > 0,
                  let r = snap.range.flatMap(Double.init), r > 0 else { return nil }
            return r / Double(b) * 100.0
        }()

        // CLTC 标称续航：设置里手动填写优先，其次接口上报的 battery_pack_range
        let cltcNominal: Int? = {
            if let m = model.config.cltcNominal, m > 0 { return m }
            return snap.cltcRange
        }()
        // 续航达成率（%）= 满电动态续航 ÷ CLTC 标称
        let cltcAchieve: String = {
            guard let d = fullDynamicKM, let n = cltcNominal, n > 0 else { return "--" }
            return String(format: "%.1f%%", d / Double(n) * 100.0)
        }()
        // 续航、总里程、满电动态续航都已在主卡；这一格放「CLTC 标称」——它正是达成率的分母，放一起才好对读
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            statCell(icon: "thermometer.medium", iconColor: Color.dsDanger,
                     value: (snap.interiorTemp.map { $0 == "--" ? "--" : $0 } ?? "--") + " °C",
                     label: "车内温度")
            statCell(icon: "bolt.batteryblock.fill", iconColor: Color.dsOK,
                     value: "\(VehicleFormat.voltageText(snap.voltage)) V",
                     label: "小电瓶电压")
            statCell(icon: "gauge.medium", iconColor: palette.blue,
                     value: cltcNominal.map { "\($0) km" } ?? "--",
                     label: "CLTC 标称")
            statCell(icon: "target", iconColor: palette.blue,
                     value: cltcAchieve,
                     label: "折算达成率")
        }
    }

    private func statCell(icon: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(iconColor)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(palette.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundColor(palette.sub)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: 安全状态 —— 门锁 + 门窗（原两个独立模块合并）

    /// 门锁与门窗原本是两张各占一行的卡，加起来 5 行里 2 行只有一句结论；
    /// 合成一张后「车锁着、窗也关着」这类最常见状态一屏只占一行多一点。
    private func safetyCard(_ snap: VehicleSnapshot) -> some View {
        let locked = snap.locked == true
        let closed = snap.allClosed == true
        let opens = snap.openParts ?? []

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                statusDot(systemName: locked ? "lock.fill" : "lock.open.fill",
                          tint: locked ? Color.dsOK : Color.dsDanger,
                          background: locked ? palette.lockOn : palette.lockOff)
                VStack(alignment: .leading, spacing: 3) {
                    Text("门锁")
                        .font(.caption.weight(.medium))
                        .foregroundColor(palette.sub)
                    Text(locked ? "车辆已锁" : "车辆未锁")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(palette.text)
                }
                Spacer(minLength: 0)
                Text(locked ? "已锁好" : "未上锁")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(locked ? Color.dsOK : Color.dsDanger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(locked ? palette.lockOn : palette.lockOff))
            }
            .padding(.bottom, 12)

            Divider()

            HStack(spacing: 12) {
                statusDot(systemName: closed ? "car.side.fill" : "car.side",
                          tint: closed ? Color.dsOK : Color.dsWarn,
                          background: closed ? palette.doorOn : palette.doorOff)
                VStack(alignment: .leading, spacing: 3) {
                    Text("门窗")
                        .font(.caption.weight(.medium))
                        .foregroundColor(palette.sub)
                    Text(closed ? "门窗已关" : "门窗未关")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(palette.text)
                }
                Spacer(minLength: 0)
                Text(closed ? "全部关闭" : "\(opens.count) 处未关")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(closed ? Color.dsOK : Color.dsWarn)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(closed ? palette.doorOn : palette.doorOff))
            }
            .padding(.top, 12)

            if !opens.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text("以下部件未关闭")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundColor(Color.dsWarn)
                    .padding(.top, 12)

                    // 按数量定列数：1→1 列，2 或 4→2 列（4 个门窗正好 2×2），其余 3 列。
                    LazyVGrid(columns: closedPartColumns(opens.count),
                              alignment: .leading, spacing: 8) {
                        ForEach(opens, id: \.self) { name in
                            HStack(spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                Text(name)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundColor(Color.dsWarn)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(Capsule().fill(palette.doorOff))
                        }
                    }
                }
            }
        }
        .padding(Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    /// 状态圆底图标（门锁 / 门窗共用，保证两个模块图标视觉重量一致）
    private func statusDot(systemName: String, tint: Color, background: Color) -> some View {
        ZStack {
            Circle().fill(background)
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
        }
        .frame(width: 44, height: 44)
    }

    /// 「以下部件未关闭」的列数：按数量选，行数尽量均衡。
    /// 1 → 1 列；2 → 2 列；4 → 2×2（比 3+1 平衡，前/后门窗正好成对）；其余（3、5、6…）→ 3 列。
    private func closedPartColumns(_ count: Int) -> [GridItem] {
        let columns = count <= 1 ? 1 : ((count == 2 || count == 4) ? 2 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
    }

    private func tyreCard(_ snap: VehicleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("胎压监测", systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(palette.text)
            HStack {
                tyreCell("前左", snap.tyres?["fl"])
                tyreCell("前右", snap.tyres?["fr"])
            }
            HStack {
                tyreCell("后左", snap.tyres?["rl"])
                tyreCell("后右", snap.tyres?["rr"])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private func tyreCell(_ label: String, _ v: Double?) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(palette.sub)
            Text(VehicleFormat.pressure(v) + " bar")
                .font(.body.weight(.semibold))
                .foregroundColor(palette.text)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
    }

    private func locationCard(_ snap: VehicleSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundColor(palette.blue)
                Text(snap.address ?? "等待位置数据...")
                    .font(.subheadline)
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 4)
                // 导航到车辆位置（有坐标才显示）
                if let lat = snap.lat, let lng = snap.lng,
                   (18.0...54.0).contains(lat), (73.0...136.0).contains(lng) {
                    Button { openNavigationToCar(lat: lat, lng: lng) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("导航")
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(palette.blue))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: snap.isFresh ? "checkmark.circle.fill" : "clock")
                    .font(.system(size: 13))
                    .foregroundColor(snap.isFresh ? Color.dsOK : palette.sub)
                Text("更新于 " + VehicleFormat.timeText(snap.fetchTime)
                     + (snap.isFresh ? "" : "（数据已超过 15 分钟）"))
                    .font(.caption)
                    .foregroundColor(snap.isFresh ? Color.dsOK : palette.sub)
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                }
                .disabled(model.isLoading)
            }

            // 坐标调试行（方便与手机地图核对接口原始坐标是否准确）
            if let lat = snap.lat, let lng = snap.lng {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.system(size: 9))
                    let (mlat, mlng) = displayCoord(lat: lat, lng: lng)
                    let suffix = model.config.mapFix ? "地图修正开" : "地图修正关"
                    let cal = (model.config.latOff != 0 || model.config.lngOff != 0) ? " · 已校准" : ""
                    Text("接口 \(String(format: "%.6f", lat)),\(String(format: "%.6f", lng))（\(suffix)\(cal)）→ 地图 \(String(format: "%.5f", mlat)),\(String(format: "%.5f", mlng))")
                }
                .font(.system(size: 9.5))
                .foregroundColor(palette.sub)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - 地图坐标修正（WGS-84 上报时转国内 GCJ-02）

    /// 依据设置返回用于地图/导航的坐标：mapFix 转换 + 手动校准偏移
    private func displayCoord(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
        // 与逆地理编码共用同一套换算（Shared/Car/Model.swift 的 mapDisplayCoord），
        // 否则地址文本会和地图上的点、导航终点错开
        mapDisplayCoord(lat: lat, lng: lng, config: model.config)
    }

    /// 用系统地图（Apple 地图）发起驾车导航到车辆坐标（导航同样应用坐标修正）
    private func openNavigationToCar(lat: Double, lng: Double) {
        let (mlat, mlng) = displayCoord(lat: lat, lng: lng)
        let place = MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: mlat, longitude: mlng))
        let item = MKMapItem(placemark: place)
        item.name = "我的\(model.config.carName.isEmpty ? "车" : model.config.carName)"
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
