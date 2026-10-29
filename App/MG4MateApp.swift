import SwiftUI

// ============================================================
// 电车助手 —— 车况（原 MG4Widget）+ 电耗记录（原 EVLogger）合并版
// 单一进程、单一 App Group 容器：车况快照可直接带进充电记录。
// ============================================================

@main
struct MG4MateApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var carModel = CarModel()

    init() {
        // 启动自检：上次有没有走到首屏（写进 Documents/diagnostic.log）
        _ = DiagLog.bootStart()
    }

    /// 外观设置来自车况配置（auto / dark / light），合并后对四个 Tab 一起生效
    private var forcedScheme: ColorScheme? {
        ThemeMode(raw: carModel.config.theme).forcedDark.map { $0 ? .dark : .light }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .environmentObject(carModel)
                .tint(.brand)
                .preferredColorScheme(forcedScheme)
        }
    }
}

/// 四个 Tab（合并前：车况是独立 App，记录/统计/设置是电耗助手）
enum AppTab: Hashable { case car, records, stats, settings }

struct RootTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var carModel: CarModel
    @State private var didSelectInitialTab = false

    var body: some View {
        Group {
            if let shot = debugShotFamily {
                DebugWidgetShot(family: shot)
            } else {
                tabs
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $store.selectedTab) {
            DashboardView()
                .tabItem { Label("车况", systemImage: "car.side.fill") }
                .tag(AppTab.car)

            RecordsView()
                .tabItem { Label("记录", systemImage: "list.bullet.rectangle.portrait") }
                .tag(AppTab.records)

            StatsView()
                .tabItem { Label("统计", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.stats)

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .onAppear {
            DiagLog.mark("首屏出现，启动完成")
            DiagLog.bootFinished()
            selectInitialTab()
            #if DEBUG
            if DebugSeed.wantsDemoCar { carModel.loadDemoData() }
            DebugSeed.seedRecordsIfNeeded()
            if CommandLine.arguments.contains("-newrecord") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    store.selectedTab = .records
                    store.newRecordTick &+= 1
                }
            }
            #endif
        }
        .onOpenURL(perform: handle)
    }

    /// 首次启动：配好车况数据源就落在「车况」，否则落在「记录」，避免一进来就是空配置页
    private func selectInitialTab() {
        guard !didSelectInitialTab else { return }
        didSelectInitialTab = true
        if let i = CommandLine.arguments.firstIndex(of: "-tab"), i + 1 < CommandLine.arguments.count {
            switch CommandLine.arguments[i + 1] {
            case "car": store.selectedTab = .car
            case "stats": store.selectedTab = .stats
            case "settings": store.selectedTab = .settings
            default: store.selectedTab = .records
            }
            return
        }
        let configured = !SharedStore.loadConfig().needsSetup
        store.selectedTab = configured ? .car : .records
    }

    private func handle(_ url: URL) {
        switch url.scheme {
        case "mg4widget":
            store.selectedTab = .car
        case "mg4mate":
            switch url.host {
            case "car": store.selectedTab = .car
            case "records": store.selectedTab = .records
            case "stats": store.selectedTab = .stats
            case "settings": store.selectedTab = .settings
            case "record":
                store.selectedTab = .records
                store.newRecordTick &+= 1
            default: store.selectedTab = .car
            }
        default:  // evstats://
            guard url.scheme == "evstats" else { return }
            switch url.host {
            case "stats":
                store.selectedTab = .stats
            case "record":
                store.selectedTab = .records
                store.newRecordTick &+= 1
            case "car":
                store.selectedTab = .car
            default:
                store.selectedTab = .stats
            }
        }
    }

    /// 调试全屏渲染小组件：-wlarge / -wmedium / -wsmall / -wlock
    private var debugShotFamily: MG4WidgetFamily? {
        let args = CommandLine.arguments
        if args.contains("-wlarge") { return .systemLarge }
        if args.contains("-wmedium") { return .systemMedium }
        if args.contains("-wsmall") { return .systemSmall }
        if args.contains("-wlock") { return .systemAccessoryRectangular }
        return nil
    }
}
