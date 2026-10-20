import WidgetKit
import SwiftUI

// ============================================================
// 合并后的小组件扩展入口：一个扩展里挂两个 Widget
//   · 车况（MG4StatusWidget）：电量 / 续航 / 门锁 / 位置
//   · 电耗（EVLoggerWidget）：本月费用 / 累计里程 / 续航达成率
// 两者共用同一个 App Group 容器，安装一次即可同时添加。
// ============================================================

@main
struct MG4MateWidgetBundle: WidgetBundle {
    var body: some Widget {
        MG4Widget()
        EVLoggerWidget()
    }
}
