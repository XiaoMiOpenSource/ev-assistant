import SwiftUI
import UIKit
import WidgetKit

// ============================================================
// 小组件视图（Shared，使 App 内“预览小组件”可复用同一套渲染）
// 提供 small / medium / large 三档布局
// ============================================================

/// 小组件渲染所需的全部内容
struct WidgetContent {
    var snapshot: VehicleSnapshot?
    var config: AppConfig
    var carImage: UIImage?
    /// 无数据时展示的提示（nil 表示有数据）
    var placeholder: String? = nil

    static func live() -> WidgetContent {
        let cfg = SharedStore.loadConfig()
        let snap = SharedStore.loadSnapshot()
        let img = CarImageStore.localImage(color: cfg.carColor)
        var placeholder: String? = nil
        if snap == nil {
            placeholder = cfg.needsSetup ? "未配置数据源\n请打开 App 填写 API 地址" : "暂无数据"
        }
        return WidgetContent(snapshot: snap, config: cfg, carImage: img, placeholder: placeholder)
    }

    static func demo(color: String? = nil) -> WidgetContent {
        var cfg = SharedStore.loadConfig()
        if let color { cfg.carColor = color }
        return WidgetContent(snapshot: .demo(), config: cfg, carImage: CarImageStore.localImage(color: cfg.carColor))
    }
}

/// 小组件根视图：按 WidgetKit 注入的 family 分发到对应布局
struct MG4WidgetEntryView: View {
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.widgetFamily) private var widgetKitFamily
    let content: WidgetContent

    private var palette: Palette {
        resolvePalette(config: content.config, systemDark: systemScheme == .dark)
    }

    private var family: MG4WidgetFamily {
        switch widgetKitFamily {
        case .systemSmall: return .systemSmall
        case .systemMedium: return .systemMedium
        case .accessoryRectangular: return .systemAccessoryRectangular
        default: return .systemLarge
        }
    }

    @ViewBuilder
    var body: some View {
        if widgetKitFamily == .accessoryRectangular {
            // 锁屏矩形组件：系统深色材质，不铺自己的背景色
            if let snapshot = content.snapshot {
                LockRectLayout(snap: snapshot, threshold: content.config.lowBatteryThreshold)
                    .widgetURL(URL(string: "mg4widget://status"))
            } else {
                Text("暂无数据")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
            }
        } else {
            ZStack {
                palette.bg.ignoresSafeArea()
                if let snapshot = content.snapshot {
                    switch family {
                    case .systemSmall: SmallLayout(snap: snapshot, palette: palette, carImage: content.carImage, cfg: content.config)
                    case .systemMedium: MediumLayout(snap: snapshot, palette: palette, carImage: content.carImage, cfg: content.config)
                    case .systemAccessoryRectangular: LockRectLayout(snap: snapshot, threshold: content.config.lowBatteryThreshold)
                    default: LargeLayout(snap: snapshot, palette: palette, carImage: content.carImage, cfg: content.config)
                    }
                } else {
                    PlaceholderView(text: content.placeholder ?? "暂无数据", palette: palette)
                }
            }
            .preferredColorScheme(ThemeMode(raw: content.config.theme).forcedDark == true ? .dark
                                  : (ThemeMode(raw: content.config.theme).forcedDark == false ? .light : nil))
            .widgetURL(URL(string: "mg4widget://status"))
        }
    }
}

// ------------------------------------------------------------

/// 无数据占位
struct PlaceholderView: View {
    let text: String
    let palette: Palette

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "car.side")
                .font(.system(size: 26))
                .foregroundColor(palette.sub)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(palette.sub)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(8)
    }
}

// ------------------------------------------------------------
// Small
// ------------------------------------------------------------
struct SmallLayout: View {
    let snap: VehicleSnapshot
    let palette: Palette
    let carImage: UIImage?
    let cfg: AppConfig

    var body: some View {
        VStack(spacing: 4) {
            // 顶部：车型 + 车牌
            HStack {
                Text(cfg.carModel)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !cfg.carPlate.isEmpty && cfg.carPlate != "--" {
                    Text(cfg.carPlate)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(palette.sub)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            // 中间：车辆效果图
            Group {
                if let carImage {
                    Image(uiImage: carImage).resizable().scaledToFit()
                } else {
                    Image(systemName: "car.fill")
                        .font(.system(size: 34))
                        .foregroundColor(palette.sub)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 58)
            Spacer(minLength: 0)
            // 续航
            HStack(spacing: 5) {
                Image(systemName: snap.locked == true ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(snap.locked == true ? palette.green : palette.red)
                Text(rangeText + " km")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            // 底部：电量条 + 百分比（低电量：条收窄让位，加红色「低电」胶囊）
            HStack(spacing: 5) {
                BatteryBar(value: snap.battery, palette: palette,
                           maxWidth: lowCharge ? 44 : 76, height: 5,
                           lowThreshold: cfg.lowBatteryThreshold)
                Text("\(snap.battery ?? 0)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(lowCharge ? palette.red : palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if lowCharge {
                    LowBatteryChip(palette: palette, fontSize: 9, compact: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
    }

    private var rangeText: String {
        guard let r = snap.range, r != "--", !r.isEmpty else { return "--" }
        return r
    }
    private var lowCharge: Bool { snap.needsCharge(threshold: cfg.lowBatteryThreshold) }
}

// ------------------------------------------------------------
// Medium
// ------------------------------------------------------------
struct MediumLayout: View {
    let snap: VehicleSnapshot
    let palette: Palette
    let carImage: UIImage?
    let cfg: AppConfig

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                leftColumn
                    .frame(maxWidth: .infinity, alignment: .leading)
                rightColumn
            }
            Spacer(minLength: 0)
            addressFooter
        }
        .padding(12)
    }

    // 左侧：车型/名称 + 电量 + 带文字标签的 2x2 指标格（续航/总里程/车内温度/电瓶电压）
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(cfg.carModel)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(palette.text)
                Text(cfg.carName)
                    .font(.system(size: 9))
                    .foregroundColor(palette.sub)
                    .lineLimit(1)
            }
            // 电量行（低电量：图标/数字变红 + 条收窄让位，行尾加「请充电」胶囊）
            HStack(spacing: 5) {
                Image(systemName: lowCharge ? "battery.25"
                       : (snap.charging == true ? "bolt.fill" : "battery.75"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(lowCharge ? palette.red
                        : (snap.charging == true ? palette.orange : palette.green))
                BatteryBar(value: snap.battery, palette: palette,
                           maxWidth: lowCharge ? 52 : 84, height: 7,
                           lowThreshold: cfg.lowBatteryThreshold)
                Text("\(snap.battery ?? 0)%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(lowCharge ? palette.red : palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if lowCharge {
                    LowBatteryChip(palette: palette, fontSize: 9, compact: true)
                }
            }
            // 2x2 指标：每格 标签(小) + 数值(大)，两列等宽对齐
            HStack(spacing: 10) {
                metricCell(label: "剩余续航", value: rangeText, unit: "km", valueSize: 20, big: true)
                metricCell(label: "总里程", value: VehicleFormat.odometer(snap.odometer), unit: "km", valueSize: 14)
            }
            HStack(spacing: 10) {
                metricCell(label: "车内温度", value: tempValue, unit: "°C", valueSize: 14)
                metricCell(label: "电瓶电压", value: VehicleFormat.voltageText(snap.voltage), unit: "V", valueSize: 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 左列指标格：上行小标签 + 下行数值（单位小字）；big=true 续航主值放大
    private func metricCell(label: String, value: String, unit: String,
                            valueSize: CGFloat, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(palette.sub)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: valueSize, weight: .heavy, design: .rounded))
                    .foregroundColor(big ? palette.green : palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 8))
                        .foregroundColor(palette.sub)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tempValue: String {
        guard let t = snap.interiorTemp, t != "--", !t.isEmpty else { return "--" }
        return t
    }
    private var lowCharge: Bool { snap.needsCharge(threshold: cfg.lowBatteryThreshold) }

    // 右侧：车辆图 + 状态胶囊 + 胎压（固定列宽，避免挤压左侧内容）
    private var rightColumn: some View {
        VStack(spacing: 3) {
            Group {
                if let carImage {
                    // 有图：透明底直接平铺（与小号一致），不再垫色块面板
                    Image(uiImage: carImage).resizable().scaledToFit()
                } else {
                    // 无图：仅此时用色块兜底，视觉不空洞
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.card)
                        Image(systemName: "car.fill")
                            .font(.system(size: 30))
                            .foregroundColor(palette.sub)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)

            HStack(spacing: 4) {
                StateChip(on: snap.locked == true,
                          onIcon: "lock.fill", offIcon: "lock.open.fill",
                          onText: "已锁", offText: "未锁",
                          onBg: palette.lockOn, offBg: palette.lockOff,
                          onFg: palette.green, offFg: palette.red,
                          iconSize: 9, fontSize: 10,
                          minWidth: 60)
                StateChip(on: snap.allClosed == true,
                          onIcon: "car.side", offIcon: "car.side.fill",
                          onText: "门窗关", offText: "门窗未关",
                          onBg: palette.doorOn, offBg: palette.doorOff,
                          onFg: palette.green, offFg: palette.orange,
                          iconSize: 9, fontSize: 10,
                          minWidth: 60)
            }
            // 胎压
            tyreRows
            HStack(spacing: 3) {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                    .foregroundColor(snap.isFresh ? palette.green : palette.sub)
                Text("更新于 " + VehicleFormat.timeText(snap.fetchTime))
                    .font(.system(size: 9))
                    .foregroundColor(snap.isFresh ? palette.green : palette.sub)
            }
        }
        .frame(width: 136)
    }

    private var tyreRows: some View {
        VStack(spacing: 1) {
            HStack(spacing: 8) {
                tyreCell("前左", snap.tyres?["fl"])
                tyreCell("前右", snap.tyres?["fr"])
            }
            HStack(spacing: 8) {
                tyreCell("后左", snap.tyres?["rl"])
                tyreCell("后右", snap.tyres?["rr"])
            }
        }
    }

    private func tyreCell(_ label: String, _ v: Double?) -> some View {
        Text("\(label) \(VehicleFormat.pressure(v))")
            .font(.system(size: 9))
            .foregroundColor(palette.sub)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var addressFooter: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 9))
                .foregroundColor(palette.sub)
            Text(snap.address ?? "等待位置数据...")
                .font(.system(size: 8.5))
                .foregroundColor(palette.sub)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.footer))
    }

    private var rangeText: String {
        guard let r = snap.range, r != "--", !r.isEmpty else { return "--" }
        return r
    }
    private var tempText: String {
        guard let t = snap.interiorTemp, t != "--", !t.isEmpty else { return "-- °C" }
        return "\(t) °C"
    }
    private var voltageText: String {
        "\(VehicleFormat.voltageText(snap.voltage)) V"
    }
}

// ------------------------------------------------------------
// Large —— 复用 Medium 的数据卡片，但放大 + 加一列胎压明细
// ------------------------------------------------------------
// ------------------------------------------------------------
// Large（集中式仪表：顶部信息带 → 续航主卡 → 状态/胎压卡 → 地址）
// ------------------------------------------------------------
// ------------------------------------------------------------
// Large（通透分层布局）
// 原则：不叠卡、不贴边——整体置于组件浅底上，纵向用大间距分区，
// 依次为：①车辆信息+电量条 → ②续航大数字焦点 → ③锁/门窗状态 →
// ④胎压 → ⑤位置与更新时间。字号拉开层级，避免信息挤压。
// ------------------------------------------------------------
struct LargeLayout: View {
    let snap: VehicleSnapshot
    let palette: Palette
    let carImage: UIImage?
    let cfg: AppConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBlock          // 车辆信息 + 车图 + 电量 + 电量条
            Spacer(minLength: 12)
            rangeBlock           // 续航焦点
            Spacer(minLength: 14)
            statusRow            // 已锁 / 门窗
            if let opens = snap.openParts, !opens.isEmpty {
                Text("未关闭：\(opens.joined(separator: " · "))")
                    .font(.system(size: 9))
                    .foregroundColor(palette.orange)
                    .padding(.top, 6)
            }
            Spacer(minLength: 12)
            Divider().background(palette.darkGray)
            Spacer(minLength: 10)
            tyreRow              // 胎压一行四格
            Spacer(minLength: 10)
            footerRow            // 位置 + 更新时间
        }
        .padding(15)
    }

    // MARK: ① 车辆信息 + 电量 + 电量条
    private var headerBlock: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cfg.carModel)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundColor(palette.text)
                        .lineLimit(1)
                    Text(cfg.carName + (cfg.carPlate.isEmpty || cfg.carPlate == "--" ? "" : " · " + cfg.carPlate))
                        .font(.system(size: 10))
                        .foregroundColor(palette.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 车辆效果图（去底透明小图；无图时不占位，避免空洞/挤占）
                if let carImage {
                    Image(uiImage: carImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 36)
                        .padding(.trailing, 6)
                }

                HStack(spacing: 5) {
                    Image(systemName: lowCharge ? "battery.25"
                           : (snap.charging == true ? "bolt.fill" : "battery.75"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(lowCharge ? palette.red
                            : (snap.charging == true ? palette.orange : palette.green))
                    Text("\(snap.battery ?? 0)%")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(lowCharge ? palette.red : palette.text)
                    if snap.charging == true {
                        Text("充电中")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(palette.orange)
                    } else if lowCharge {
                        LowBatteryChip(palette: palette, fontSize: 10)
                    }
                }
            }
            .padding(.bottom, 11)

            BatteryBar(value: snap.battery, palette: palette, maxWidth: nil, height: 6,
                       lowThreshold: cfg.lowBatteryThreshold)
        }
    }

    private var lowCharge: Bool { snap.needsCharge(threshold: cfg.lowBatteryThreshold) }

    // MARK: ② 剩余续航大数字（视觉焦点）
    private var rangeBlock: some View {
        HStack(alignment: .center, spacing: 12) {
            // 左：标签 + 大数字
            VStack(alignment: .leading, spacing: 1) {
                Text("剩余里程")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.sub)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(rangeText)
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(palette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("km")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(palette.sub)
                }
            }
            Spacer(minLength: 8)
            // 右：总里程 / 车内温度 / 电瓶电压 三行（等宽标签列 → 数值起点对齐）
            VStack(alignment: .leading, spacing: 8) {
                statLine("speedometer", "总里程", VehicleFormat.odometer(snap.odometer) + " km")
                statLine("thermometer.medium", "车内温度", tempText)
                statLine("bolt.batteryblock.fill", "电瓶电压", voltageText)
            }
        }
    }

    /// 三行小指标：图标列 + 标签列固定等宽(50) → 数值列左缘对齐
    private func statLine(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(palette.green)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(palette.sub)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    // MARK: ③ 锁 / 门窗状态（两枚等宽胶囊并排，间距宽松）
    private var statusRow: some View {
        HStack(spacing: 12) {
            StateChip(on: snap.locked == true,
                      onIcon: "lock.fill", offIcon: "lock.open.fill",
                      onText: snap.locked == true ? "车辆已锁" : "车辆未锁",
                      offText: snap.locked == true ? "车辆已锁" : "车辆未锁",
                      onBg: palette.lockOn, offBg: palette.lockOff,
                      onFg: palette.green, offFg: palette.red,
                      iconSize: 12, fontSize: 13,
                      expands: true)
            StateChip(on: snap.allClosed == true,
                      onIcon: "car.side", offIcon: "car.side.fill",
                      onText: snap.allClosed == true ? "门窗已关" : "门窗未关",
                      offText: snap.allClosed == true ? "门窗已关" : "门窗未关",
                      onBg: palette.doorOn, offBg: palette.doorOff,
                      onFg: palette.green, offFg: palette.orange,
                      iconSize: 12, fontSize: 13,
                      expands: true)
        }
    }

    // MARK: ④ 胎压（一行四格，均分）
    private var tyreRow: some View {
        HStack(spacing: 0) {
            tyreCell("前左", snap.tyres?["fl"])
            tyreCell("前右", snap.tyres?["fr"])
            tyreCell("后左", snap.tyres?["rl"])
            tyreCell("后右", snap.tyres?["rr"])
        }
    }

    private func tyreCell(_ label: String, _ v: Double?) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(palette.sub)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(VehicleFormat.pressure(v))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(palette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("bar")
                    .font(.system(size: 9))
                    .foregroundColor(palette.sub)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: ⑤ 位置 + 更新时间
    private var footerRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 11))
                .foregroundColor(palette.blue)
            Text(snap.address ?? "等待位置数据...")
                .font(.system(size: 10))
                .foregroundColor(palette.sub)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 4)
            Image(systemName: snap.isFresh ? "checkmark.circle.fill" : "clock")
                .font(.system(size: 10))
                .foregroundColor(snap.isFresh ? palette.green : palette.orange)
            Text("更新于 " + VehicleFormat.timeText(snap.fetchTime))
                .font(.system(size: 10))
                .foregroundColor(snap.isFresh ? palette.green : palette.orange)
                .lineLimit(1)
        }
    }

    // MARK: 显示值工具
    private var rangeText: String {
        guard let r = snap.range, r != "--", !r.isEmpty else { return "--" }
        return r
    }
    private var tempText: String {
        guard let t = snap.interiorTemp, t != "--", !t.isEmpty else { return "-- °C" }
        return "\(t) °C"
    }
    private var voltageText: String {
        "\(VehicleFormat.voltageText(snap.voltage)) V"
    }
}



// ------------------------------------------------------------
// Lock Screen 矩形组件（accessoryRectangular）
// 系统深色材质上直接排内容；文字固定白/状态色，不受主题影响
// ------------------------------------------------------------
struct LockRectLayout: View {
    let snap: VehicleSnapshot
    /// 低电量阈值（%），由小组件 timeline 配置注入
    var threshold: Int = 20

    private var batteryPct: Int { snap.battery ?? 0 }
    private var lowCharge: Bool { snap.needsCharge(threshold: threshold) }
    private var rangeTxt: String {
        guard let r = snap.range, r != "--", !r.isEmpty else { return "--" }
        return r
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: snap.charging == true ? "bolt.fill"
                       : (lowCharge ? "battery.25" : "battery.75"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(snap.charging == true ? Color(hex: 0xff9f0a)
                        : (lowCharge ? Color(hex: 0xff453a) : Color(hex: 0x30d158)))
                Text("\(batteryPct)%")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(lowCharge ? Color(hex: 0xff453a) : .white)
                Spacer(minLength: 0)
                Image(systemName: snap.locked == true ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(snap.locked == true ? Color(hex: 0x30d158) : Color(hex: 0xff453a))
            }
            HStack(spacing: 6) {
                if lowCharge {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: 0xff453a))
                }
                Text("续航 \(rangeTxt) km")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                Image(systemName: snap.allClosed == true ? "car.side.fill" : "car.side")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(snap.allClosed == true ? Color(hex: 0x30d158) : Color(hex: 0xff9f0a))
                Text(snap.allClosed == true ? "已关" : "未关")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(snap.allClosed == true ? Color(hex: 0x30d158) : Color(hex: 0xff9f0a))
            }
        }
    }
}

/// family 描述（避免 Widget 侧直接依赖 WidgetKit 类型，便于 App 预览复用）
enum MG4WidgetFamily {
    case systemSmall, systemMedium, systemLarge, systemAccessoryRectangular
}
