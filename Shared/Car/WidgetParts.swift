import SwiftUI
import UIKit

// ============================================================
// 通用可视化部件（App 仪表页与小组件共用）
// ============================================================

/// 车辆效果图：优先使用本地缓存（App 刷新时下载），否则回退为 SF Symbol 剪影
struct CarArtwork: View {
    let color: String
    let palette: Palette
    var maxWidth: CGFloat? = nil
    var maxHeight: CGFloat? = nil

    private static var cache: [String: UIImage] = [:]

    private var image: UIImage? {
        if let img = Self.cache[color] { return img }
        if let img = CarImageStore.localImage(color: color) {
            Self.cache[color] = img
            return img
        }
        return nil
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.card)
                    Image(systemName: "car.fill")
                        .font(.system(size: 30))
                        .foregroundColor(palette.sub)
                }
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
    }
}

/// 细圆角电量进度条（≤ lowThreshold 红色，否则绿色；与低电量提醒阈值联动）。
/// maxWidth = nil 时撑满父容器宽度（用 GeometryReader 自适应）。
struct BatteryBar: View {
    let value: Int?
    let palette: Palette
    var maxWidth: CGFloat? = nil
    var height: CGFloat = 6
    /// 低电量阈值（%），电量 ≤ 该值显示红色
    var lowThreshold: Int = 20

    private var pct: CGFloat {
        guard let value else { return 0 }
        return CGFloat(min(max(value, 0), 100)) / 100
    }

    private var fillColor: Color {
        guard let value, value <= lowThreshold else { return palette.green }
        return palette.red
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.darkGray)
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(height, geo.size.width * pct), height: height)
            }
        }
        .frame(height: height)
        .frame(width: maxWidth)
    }
}

/// 状态胶囊（锁 / 门窗），on/off 两种底色与图标。
/// 传入相同 minWidth 可让“已锁 / 门窗关”两组胶囊外观等宽一致；
/// expands=true 时胶囊撑满整行（大号组件纵向排列用）。
struct StateChip: View {
    let on: Bool
    let onIcon: String
    let offIcon: String
    let onText: String
    let offText: String
    let onBg: Color
    let offBg: Color
    let onFg: Color
    let offFg: Color
    var iconSize: CGFloat = 9
    var fontSize: CGFloat = 9
    var minWidth: CGFloat? = nil
    var expands: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: on ? onIcon : offIcon)
                .font(.system(size: iconSize, weight: .semibold))
            Text(on ? onText : offText)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: expands ? .infinity : nil)
        .frame(minWidth: minWidth)
        .foregroundColor(on ? onFg : offFg)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(on ? onBg : offBg))
    }
}

/// 低电量「请充电」胶囊（红色调；App 车况页横幅与小组件共用）
struct LowBatteryChip: View {
    let palette: Palette
    var fontSize: CGFloat = 10
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "battery.25")
                .font(.system(size: fontSize - 1, weight: .semibold))
            Text(compact ? "低电" : "请充电")
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(palette.red)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, compact ? 1.5 : 2.5)
        .background(Capsule().fill(palette.red.opacity(0.14)))
    }
}

/// 带 SF Symbol 的一行小指标（App 与小组件通用）
struct MiniStatRow: View {
    let icon: String
    let text: String
    let color: Color
    var fontSize: CGFloat = 11
    var iconSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .frame(width: 14)
                .foregroundColor(color)
            Text(text)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
