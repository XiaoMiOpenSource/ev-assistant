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
                CarSettingsView()
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
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
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(palette.red)
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
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
        VStack(spacing: 12) {
            identityCard(snap)
            energyCard(snap)
            if model.config.lowBatteryRemind,
               snap.needsCharge(threshold: model.config.lowBatteryThreshold) {
                lowBatteryBanner(snap)   // 低电量充电提醒横幅
            }
            lockModule(snap)     // 独立模块 1：门锁
            doorModule(snap)     // 独立模块 2：门窗
            statGrid(snap)
            tyreCard(snap)
            locationCard(snap)
        }
    }

    /// 第一模块 —— 电量主卡（v1.0.28 排版统一版）
    /// 字体规范（全卡一致）：主数值 = SF Rounded Heavy（环内 34 / 续航焦点 26）；
    /// 标题 = 17 Semibold；次级值 = 13 Semibold；辅助（标签/单位/颜色/VIN）= 12 Regular 次级灰；
    /// 数字统一 monospacedDigit 防跳动；状态胶囊 11 Semibold 橙。
    /// 布局：环(104) + 右列左对齐，节奏 = 标题行 → 徽章行 → 焦点续航 → 总里程 → VIN 脚注，
    /// 标签列定宽 56 使数值列严格对齐，间距节律 6。
    private func identityCard(_ snap: VehicleSnapshot) -> some View {
        let plate = model.config.carPlate
        let colorName = AppConfig.colorNames[model.config.carColor] ?? model.config.carColor
        let charging = snap.charging == true
        let vin = model.config.carVin

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.config.carModel + (model.config.carName.isEmpty ? "" : " · " + model.config.carName))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 6)
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

            HStack(spacing: 8) {
                Text(plate.isEmpty ? "--" : plate)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(palette.blue))
                if charging {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold))
                        Text("充电中").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(palette.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(palette.orange.opacity(0.14)))
                }
                Spacer(minLength: 0)
            }

            if !vin.isEmpty {
                HStack(spacing: 6) {
                    Text("VIN")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundColor(palette.sub.opacity(0.7))
                    Text(vin)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(palette.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private func energyCard(_ snap: VehicleSnapshot) -> some View {
        let battery = min(max(snap.battery ?? 0, 0), 100)
        let rangeText = snap.range.map { $0 == "--" ? "--" : $0 } ?? "--"

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("剩余续航")
                        .font(.system(size: 12))
                        .foregroundColor(palette.sub)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(rangeText)
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundColor(palette.text)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("km")
                            .font(.system(size: 14))
                            .foregroundColor(palette.sub)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(palette.darkGray, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat(battery) / 100)
                        .stroke(battery <= model.config.lowBatteryThreshold ? palette.red : palette.green,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(snap.battery ?? 0)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(palette.text)
                            .monospacedDigit()
                        Text("%").font(.system(size: 8)).foregroundColor(palette.sub)
                    }
                }
                .frame(width: 78, height: 78)
            }

            Rectangle()
                .fill(palette.darkGray)
                .frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                Text("总里程")
                    .font(.system(size: 12))
                    .foregroundColor(palette.sub)
                Spacer(minLength: 8)
                Text("\(VehicleFormat.odometer(snap.odometer)) km")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
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
                .foregroundColor(palette.red)
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
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(palette.red.opacity(0.12)))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(palette.red.opacity(0.35), lineWidth: 1)
        )
    }

    private func statGrid(_ snap: VehicleSnapshot) -> some View {
        // 满电状态动态续航（km）= 当前续航 ÷ 当前电量 × 100（按当下能耗推算满电可跑里程）
        let fullDynamicKM: Double? = {
            guard let b = snap.battery, b > 0,
                  let r = snap.range.flatMap(Double.init), r > 0 else { return nil }
            return r / Double(b) * 100.0
        }()
        let fullDynamic: String = fullDynamicKM.map { "\(Int($0.rounded())) km" } ?? "--"
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
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            statCell(icon: "car.fill", iconColor: palette.blue,
                     value: (snap.range.map { $0 == "--" ? "--" : $0 } ?? "--") + " km",
                     label: "续航里程")
            statCell(icon: "speedometer", iconColor: palette.orange,
                     value: "\(VehicleFormat.odometer(snap.odometer)) km",
                     label: "总里程")
            statCell(icon: "thermometer.medium", iconColor: palette.red,
                     value: (snap.interiorTemp.map { $0 == "--" ? "--" : $0 } ?? "--") + " °C",
                     label: "车内温度")
            statCell(icon: "bolt.batteryblock.fill", iconColor: palette.green,
                     value: "\(VehicleFormat.voltageText(snap.voltage)) V",
                     label: "小电瓶电压")
            statCell(icon: "battery.100", iconColor: palette.green,
                     value: fullDynamic,
                     label: "满电动态续航")
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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundColor(palette.sub)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: 独立模块 1 —— 门锁
    private func lockModule(_ snap: VehicleSnapshot) -> some View {
        let on = snap.locked == true
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(on ? palette.lockOn : palette.lockOff)
                Image(systemName: on ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(on ? palette.green : palette.red)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("门锁")
                    .font(.caption.weight(.medium))
                    .foregroundColor(palette.sub)
                Text(on ? "车辆已锁" : "车辆未锁")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(palette.text)
            }
            Spacer(minLength: 0)
            Text(on ? "已锁好" : "未上锁")
                .font(.caption.weight(.semibold))
                .foregroundColor(on ? palette.green : palette.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(on ? palette.lockOn : palette.lockOff))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: 独立模块 2 —— 门窗（未关时在卡内展开明细胶囊）
    @ViewBuilder
    private func doorModule(_ snap: VehicleSnapshot) -> some View {
        let on = snap.allClosed == true
        let opens = snap.openParts ?? []
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(on ? palette.doorOn : palette.doorOff)
                    Image(systemName: on ? "car.side.fill" : "car.side")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(on ? palette.green : palette.orange)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("门窗")
                        .font(.caption.weight(.medium))
                        .foregroundColor(palette.sub)
                    Text(on ? "门窗已关" : "门窗未关")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(palette.text)
                }
                Spacer(minLength: 0)
                Text(on ? "全部关闭" : "\(opens.count) 处未关")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(on ? palette.green : palette.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(on ? palette.doorOn : palette.doorOff))
            }

            if !opens.isEmpty {
                Divider()
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text("以下部件未关闭")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundColor(palette.orange)
                    .padding(.top, 12)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)],
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
                            .foregroundColor(palette.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(palette.doorOff))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
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
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                    .foregroundColor(snap.isFresh ? palette.green : palette.sub)
                Text("更新于 " + VehicleFormat.timeText(snap.fetchTime)
                     + (snap.isFresh ? "" : "（数据已超过 15 分钟）"))
                    .font(.caption)
                    .foregroundColor(snap.isFresh ? palette.green : palette.sub)
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
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
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
