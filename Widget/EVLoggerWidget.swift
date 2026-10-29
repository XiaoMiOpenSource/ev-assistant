import WidgetKit
import SwiftUI

// MARK: - 入口与 Provider
struct EVLoggerWidget: Widget {
    let kind: String = "EVLoggerWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EVProvider()) { entry in
            if #available(iOS 17.0, *) {
                EVRootView(entry: entry)
                    .containerBackground(for: .widget) { LinearGradient(
                        colors: [Color(red: 0.20, green: 0.62, blue: 1.00),
                                 Color(red: 0.04, green: 0.30, blue: 0.90)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ) }
            } else {
                EVRootView(entry: entry)
                    .padding()
                    .background(LinearGradient(
                        colors: [Color(red: 0.20, green: 0.62, blue: 1.00),
                                 Color(red: 0.04, green: 0.30, blue: 0.90)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
        }
        .configurationDisplayName("电耗")
        .description("电耗助手：本月费用、累计里程、续航达成率")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryCircular, .accessoryInline
        ])
    }
}

struct EVEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
    let metric: String
}

struct EVProvider: TimelineProvider {
    func placeholder(in context: Context) -> EVEntry {
        EVEntry(date: Date(), snap: nil, metric: "cost")
    }
    func getSnapshot(in context: Context, completion: @escaping (EVEntry) -> Void) {
        completion(EVEntry(date: Date(), snap: SharedData.readSnapshot(), metric: SharedData.readMetric()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EVEntry>) -> Void) {
        let entry = EVEntry(date: Date(),
                           snap: SharedData.readSnapshot(),
                           metric: SharedData.readMetric())
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: Date()) ?? Date().addingTimeInterval(21600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct EVRootView: View {
    @Environment(\.widgetFamily) var family
    let entry: EVEntry
    var body: some View {
        switch family {
        case .systemSmall:        SmallView(entry: entry)
        case .systemMedium:       MediumView(entry: entry)
        case .systemLarge:        LargeView(entry: entry)
        case .accessoryRectangular: AccRect(entry: entry)
        case .accessoryCircular:    AccCirc(entry: entry)
        case .accessoryInline:      AccInline(entry: entry)
        default: Text("电耗助手")
        }
    }
}

// MARK: - 公共子组件
private func fmtMoney(_ v: Double) -> String { "¥\(Int(v.rounded()))" }
private func fmtNum(_ v: Double, _ dp: Int = 0) -> String { String(format: "%.\(dp)f", v) }

/// App 设置里可选的小组件主指标（cost / cons / rate）。
/// systemSmall 一直按它出大数字；medium / large / 锁屏矩形这次也统一按它强调，
/// 否则用户选了「电耗」，桌面上还是费用当主角，会以为设置没生效。
private func normalizedMetric(_ m: String) -> String {
    switch m {
    case "cons", "rate": return m
    default: return "cost"
    }
}

private func primaryMetric(_ s: WidgetSnapshot, _ metric: String) -> (title: String, value: String) {
    switch normalizedMetric(metric) {
    case "rate": return ("达成率", "\(Int(s.rangeRatePercent.rounded()))%")
    case "cons": return ("平均电耗", "\(fmtNum(s.avgConsumption, 1)) kWh")
    default:     return ("本月费用", fmtMoney(s.monthCostCNY))
    }
}

/// 除主指标之外的其余指标，按固定顺序返回（不含单位混排，便于右侧窄列显示）
private func otherMetrics(_ s: WidgetSnapshot, _ metric: String) -> [(title: String, value: String)] {
    let all: [(String, String, String)] = [
        ("cost", "本月费用", fmtMoney(s.monthCostCNY)),
        ("rate", "达成率", "\(Int(s.rangeRatePercent.rounded()))%"),
        ("cons", "平均电耗", "\(fmtNum(s.avgConsumption, 1))"),
        ("dist", "累计里程", "\(Int(s.totalDistanceKm.rounded())) km"),
    ]
    let keep = normalizedMetric(metric)
    return all.filter { $0.0 != keep }.map { ($0.1, $0.2) }
}

// MARK: - systemSmall
private struct SmallView: View {
    let entry: EVEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "bolt.fill").font(.system(size: 12, weight: .bold))
                Text("电耗助手").font(.caption2.weight(.semibold))
                Spacer()
                if let s = entry.snap, s.hasData {
                    Text(s.windowLabel).font(.caption2).opacity(0.7)
                }
            }
            Spacer(minLength: 4)
            if let s = entry.snap, s.hasData {
                let metric = entry.metric
                if metric == "rate" {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(s.rangeRatePercent.rounded()))").font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("%").font(.caption2)
                    }
                    Text("达成率").font(.caption2).opacity(0.85)
                } else if metric == "cons" {
                    Text(fmtNum(s.avgConsumption, 1))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("kWh/100km").font(.caption2).opacity(0.85)
                } else {
                    Text(fmtMoney(s.monthCostCNY))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("本月充电费").font(.caption2).opacity(0.85)
                }
            } else {
                Text("去记一笔").font(.headline)
                Text("打开 App 录入").font(.caption2).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundColor(.white)
        .widgetURL(URL(string: (entry.snap?.hasData == true) ? "evstats://stats" : "evstats://record/new"))
    }
}

// MARK: - systemMedium
private struct MediumView: View {
    let entry: EVEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bolt.fill").font(.system(size: 12, weight: .bold))
                Text("电耗助手 · \(entry.snap?.windowLabel ?? "近 3 月")").font(.caption.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).opacity(0.7)
            }
            if let s = entry.snap, s.hasData {
                let primary = primaryMetric(s, entry.metric)
                let rest = otherMetrics(s, entry.metric)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(primary.title).font(.system(size: 9)).opacity(0.8)
                        Text(primary.value)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 3) {
                        ForEach(rest.indices, id: \.self) { i in
                            HStack(spacing: 4) {
                                Text(rest[i].title).font(.system(size: 9)).opacity(0.75)
                                Text(rest[i].value)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                Spacer(minLength: 4)
                MiniBars(values: s.cost6, color: Color(red: 0.36, green: 0.94, blue: 0.71))
                    .frame(height: 30)
                Text("近 6 月费用").font(.caption2).opacity(0.7)
            } else {
                Text("还没有数据")
                Text("打开「电耗助手」记下第一笔").font(.caption2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundColor(.white)
        .widgetURL(URL(string: "evstats://stats"))
    }
}

// MARK: - systemLarge
private struct LargeView: View {
    let entry: EVEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt.fill").font(.system(size: 12, weight: .bold))
                Text("电耗助手 · 月报").font(.caption.weight(.semibold))
                Spacer()
                Text(entry.snap?.vehicleName ?? "").font(.caption2).opacity(0.75)
            }
            if let s = entry.snap, s.hasData {
                let primary = primaryMetric(s, entry.metric)
                let rest = otherMetrics(s, entry.metric)
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(primary.title).font(.system(size: 9)).opacity(0.8)
                        Text(primary.value)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.55)
                    }
                    Spacer(minLength: 0)
                    ForEach(rest.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rest[i].title).font(.system(size: 9)).opacity(0.8)
                            Text(rest[i].value)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                }
                Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1)
                Text("近 6 月达成率").font(.caption2).opacity(0.85)
                MiniLine(values: s.rate6, color: Color(red: 0.85, green: 0.85, blue: 1.0))
                    .frame(height: 70)
                Spacer()
                Text("点击查看详细").font(.caption2).opacity(0.7)
            } else {
                Text("还没有数据").font(.headline)
                Text("打开「电耗助手」记下第一笔").font(.caption2)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundColor(.white)
        .widgetURL(URL(string: "evstats://stats"))
    }
}

// MARK: - Lock screen
private struct AccRect: View {
    let entry: EVEntry
    var body: some View {
        if let s = entry.snap, s.hasData {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                    Text("电耗助手").font(.caption2.weight(.bold))
                    Spacer()
                }
                let primary = primaryMetric(s, entry.metric)
                Text(normalizedMetric(entry.metric) == "rate"
                     ? "达成率 \(primary.value)"
                     : "\(primary.title) \(primary.value) · \(Int(s.rangeRatePercent.rounded()))% 达成率")
                    .font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                Text("\(fmtNum(s.avgConsumption, 1)) kWh/100km · 累计 \(Int(s.totalDistanceKm.rounded())) km")
                    .font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
        } else {
            Text("⚡ 电耗助手 · 去记一笔").font(.caption2)
        }
    }
}
private struct AccCirc: View {
    let entry: EVEntry
    var body: some View {
        if let s = entry.snap, s.hasData {
            ZStack {
                Circle().stroke(Color.white.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(s.rangeRatePercent/100, 0), 1)))
                    .stroke(Color.white, style: .init(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(s.rangeRatePercent.rounded()))").font(.system(size: 12, weight: .bold))
                    Text("%").font(.system(size: 8))
                }
            }
        } else {
            Image(systemName: "bolt.fill")
        }
    }
}
private struct AccInline: View {
    let entry: EVEntry
    var body: some View {
        if let s = entry.snap, s.hasData {
            Text("⚡ 电耗助手 · 本月 \(fmtMoney(s.monthCostCNY))  ·  达成率 \(Int(s.rangeRatePercent.rounded()))%")
        } else {
            Text("⚡ 电耗助手 · 打开记一笔")
        }
    }
}

// MARK: - 微图表（Canvas 绘制，避免依赖 Charts 框架）
private struct MiniBars: View {
    let values: [MonthlyMini]
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let maxV = max(values.map(\.value).max() ?? 1, 1)
            let stepX = size.width / CGFloat(values.count)
            let barW = max(stepX * 0.55, 2)
            for (i, v) in values.enumerated() {
                let h = CGFloat(v.value / maxV) * size.height
                let x = stepX * CGFloat(i) + (stepX - barW) / 2
                let y = size.height - h
                let rect = CGRect(x: x, y: y, width: barW, height: h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 2.5), with: .color(color))
            }
        }
    }
}
private struct MiniLine: View {
    let values: [MonthlyMini]
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            guard values.count >= 2 else { return }
            let maxV = max(values.map(\.value).max() ?? 100, 100)
            let minV = min(values.map(\.value).min() ?? 0, 0)
            let range = max(maxV - minV, 1)
            let stepX = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - CGFloat((v.value - minV) / range) * size.height
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color), lineWidth: 2)
            // 点
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - CGFloat((v.value - minV) / range) * size.height
                let r = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
                ctx.fill(Path(ellipseIn: r), with: .color(color))
            }
        }
    }
}
