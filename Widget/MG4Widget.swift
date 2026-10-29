import WidgetKit
import SwiftUI

// ============================================================
// WidgetKit 扩展入口：kind = MG4StatusWidget
// ============================================================

struct StatusEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), content: .demo())
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        // 画廊预览优先给真实数据，其次演示数据
        let live = WidgetContent.live()
        completion(StatusEntry(date: Date(), content: live.snapshot == nil ? .demo() : live))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let config = SharedStore.loadConfig()

        Task {
            var content = WidgetContent.live()

            // 与 Scriptable 版行为一致：配置了 API 且数据缺失/过期时，在刷新时拉一次
            if !config.needsSetup && (content.snapshot == nil || content.snapshot?.isFresh != true) {
                do {
                    // geocode: false —— 小组件不做逆地理：时间线刷新预算有限，
                    // 也不该在 App 没打开时把坐标发给第三方；地址直接用 App 写进快照的缓存文本。
                    let fresh = try await MG4Service(config: config, geocode: false).fetchAndCache()
                    content = WidgetContent(snapshot: fresh, config: SharedStore.loadConfig(),
                                           carImage: CarImageStore.localImage(color: config.carColor))
                } catch {
                    // 拉取失败则沿用缓存（可能已过期）；无缓存保持占位
                    if content.snapshot == nil {
                        content.placeholder = "刷新失败，请打开 App 检查"
                    }
                }
            }

            let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [StatusEntry(date: Date(), content: content)], policy: .after(next)))
        }
    }
}

struct MG4Widget: Widget {
    let kind: String = "MG4StatusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MG4WidgetEntryView(content: entry.content)
        }
        .configurationDisplayName("车况")
        .description("查看电量、续航、门锁与车辆位置状态")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

