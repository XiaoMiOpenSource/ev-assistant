import SwiftUI
import WidgetKit
import UserNotifications

// ------------------------------------------------------------
// 车况状态模型（原 MG4Widget 的 CarModel，合并后并入主 App）
// ------------------------------------------------------------

@MainActor
final class CarModel: ObservableObject {
    @Published var config: AppConfig = SharedStore.loadConfig()
    @Published var snapshot: VehicleSnapshot? = SharedStore.loadSnapshot()
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// 电量历史版本号（每次成功抓取 +1，供界面按需重读历史）
    @Published var historyRevision = 0

    /// 手动/自动刷新：抓取车况 -> 写共享存储 -> 刷新小组件时间线
    func refresh() async {
        guard !config.needsSetup else {
            errorMessage = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        ensureNotificationPermission()
        do {
            let snap = try await MG4Service(config: config).fetchAndCache()
            snapshot = snap
            errorMessage = nil
            // 顺带确保车辆效果图已在共享容器里
            _ = await CarImageStore.ensureLocal(color: config.carColor)
            // 记录电量历史并评估“未锁/门窗未关”提醒
            SharedStore.appendHistory(.init(t: Date(), battery: snap.battery, range: snap.range))
            historyRevision += 1
            evaluateLockReminder(snap)
            evaluateLowBatteryReminder(snap)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 自动刷新策略：数据缺失或超过 5 分钟未更新则拉取
    func autoRefreshIfNeeded() async {
        guard !config.needsSetup else { return }
        if snapshot == nil || !(snapshot?.isFresh ?? false) {
            await refresh()
        }
    }

    // MARK: - 未锁 / 门窗未关 提醒

    /// 首次抓取前请求通知权限（任一提醒开关打开即请求）
    func ensureNotificationPermission() {
        guard config.lockRemind || config.lowBatteryRemind else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 连续两次抓取均异常才提醒；提醒后进入 20 分钟冷却；恢复正常即复位
    func evaluateLockReminder(_ snap: VehicleSnapshot) {
        guard config.lockRemind else { return }
        let abnormal = (snap.locked == false) || (snap.allClosed == false)
        guard abnormal else {
            SharedStore.setRemindPending(false)
            return
        }
        if !SharedStore.remindPending {
            SharedStore.setRemindPending(true)   // 第一次发现异常，等下次确认
            return
        }
        // 连续两次异常：提醒（受 20 分钟冷却限制）
        if let last = SharedStore.lastRemindTime, Date().timeIntervalSince(last) < 20 * 60 {
            return
        }
        sendLockReminder(snap)
        SharedStore.markRemindedNow()
    }

    private func sendLockReminder(_ snap: VehicleSnapshot) {
        var bits: [String] = []
        if snap.locked == false { bits.append("车辆未上锁") }
        if snap.allClosed == false {
            if let o = snap.openParts, !o.isEmpty {
                bits.append("门窗未关（\(o.joined(separator: "、"))）")
            } else {
                bits.append("门窗未关")
            }
        }
        guard !bits.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "车况提醒"
        content.body = bits.joined(separator: "，") + "，建议尽快处理"
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "mg4.remind.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - 低电量充电提醒

    /// 刷新后评估低电量：≤阈值且未充电 → 发通知（20 分钟冷却）；
    /// 一旦充电或电量回升即清除冷却，下次低电可立即再提醒
    func evaluateLowBatteryReminder(_ snap: VehicleSnapshot) {
        guard config.lowBatteryRemind, snap.needsCharge(threshold: config.lowBatteryThreshold),
              let b = snap.battery else {
            SharedStore.clearLowReminder()
            return
        }
        // 20 分钟冷却内不重复打扰
        if let last = SharedStore.lastLowRemindTime,
           Date().timeIntervalSince(last) < 20 * 60 { return }
        sendLowBatteryReminder(snap, battery: b)
        SharedStore.markLowRemindedNow()
    }

    private func sendLowBatteryReminder(_ snap: VehicleSnapshot, battery: Int) {
        let content = UNMutableNotificationContent()
        content.title = "电量低，请及时充电"
        var body = "当前电量 \(battery)%"
        if let r = snap.range, r != "--", !r.isEmpty { body += "，剩余续航约 \(r) km" }
        body += "，建议尽快接入充电。"
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "mg4.lowbat.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    func saveConfig(_ cfg: AppConfig) {
        let colorChanged = cfg.carColor != config.carColor
        config = cfg
        SharedStore.saveConfig(cfg)
        WidgetCenter.shared.reloadAllTimelines()
        // 颜色变了（或尚未缓存）就顺手拉取该颜色车图，保证“月光白”等各色都有图
        if colorChanged {
            Task {
                _ = await CarImageStore.ensureLocal(color: cfg.carColor)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// 载入演示数据（便于先看看效果 / 调试）
    func loadDemoData() {
        let snap = VehicleSnapshot.demo()
        snapshot = snap
        SharedStore.saveSnapshot(snap)
        errorMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
        // 演示数据也把真实车辆效果图拉下来，效果更完整
        Task { _ = await CarImageStore.ensureLocal(color: config.carColor) }
    }

    /// 载入“低电量”演示数据（调试低电提醒/横幅/小组件标识用，-lowdemo）
    func loadLowDemoData() {
        var snap = VehicleSnapshot.demo()
        snap.battery = 12
        snap.range = "52"
        snap.charging = false
        snapshot = snap
        SharedStore.saveSnapshot(snap)
        errorMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
        Task { _ = await CarImageStore.ensureLocal(color: config.carColor) }
    }
}

// ------------------------------------------------------------
// 调试：全屏放大渲染某个尺寸的小组件（布局自检用）
// ------------------------------------------------------------
struct DebugWidgetShot: View {
    @Environment(\.colorScheme) private var scheme
    let family: MG4WidgetFamily

    private var scale: CGFloat {
        UIScreen.main.bounds.width / (family == .systemAccessoryRectangular ? 156.0 : 329.0)
    }
    private let sizeMap: [MG4WidgetFamily: CGSize] = [
        .systemSmall: CGSize(width: 155, height: 155),
        .systemMedium: CGSize(width: 329, height: 155),
        .systemLarge: CGSize(width: 329, height: 345),
        .systemAccessoryRectangular: CGSize(width: 156, height: 72)
    ]

    private var content: WidgetContent {
        var c = WidgetContent.live()
        if c.snapshot == nil { c.snapshot = .demo() }
        return c
    }

    var body: some View {
        let cfg = content.config
        let snap = content.snapshot ?? .demo()
        let palette = resolvePalette(config: cfg, systemDark: scheme == .dark)
        let size = sizeMap[family] ?? CGSize(width: 329, height: 345)
        ZStack {
            Color.black.ignoresSafeArea()
            ZStack {
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
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
        }
    }
}
