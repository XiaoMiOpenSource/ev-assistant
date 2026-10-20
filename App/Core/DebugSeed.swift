#if DEBUG
import Foundation

// ============================================================
// 调试种子数据：仅在 Debug 构建 + 启动参数命中时执行
//   -demo         车况页载入演示快照
//   -seedrecords  写入一辆示例车 + 近 6 个月充电记录
// 用途：模拟器里验证记录/统计/图表/小组件渲染，避免手点录入。
// ============================================================

enum DebugSeed {
    static var wantsDemoCar: Bool { CommandLine.arguments.contains("-demo") }
    static var wantsRecords: Bool { CommandLine.arguments.contains("-seedrecords") }

    @MainActor
    static func seedRecordsIfNeeded() {
        guard wantsRecords, Store.shared.vehicles.isEmpty else { return }
        let store = Store.shared
        let car = Vehicle(id: UUID(), name: "MG4 EV", ratedRangeKm: 425, rangeStandard: 0,
                          batteryKWh: 51, usableKWh: 47.5, createdAt: Date())
        store.saveVehicle(car)

        let cal = Calendar.current
        let samples: [(monthBack: Int, day: Int, energy: Double, cost: Double, socB: Double, socA: Double, type: Int16, note: String)] = [
            (5, 8, 32.4, 32.4, 22, 90, 0, "家充 · 谷电"),
            (4, 12, 28.6, 54.2, 18, 86, 1, "特来电快充"),
            (3, 6, 35.1, 35.1, 15, 92, 0, "家充"),
            (3, 21, 24.8, 46.9, 30, 88, 1, "高速服务区"),
            (2, 9, 30.2, 30.2, 25, 91, 0, "家充"),
            (1, 14, 27.5, 52.1, 20, 87, 1, "商场快充"),
            (0, 3, 33.8, 33.8, 12, 95, 0, "家充"),
            (0, 12, 26.3, 49.7, 24, 84, 1, "公司楼下快充"),
        ]
        // 先按时间排好，再按顺序递增里程表，保证「区间里程 = 两笔读数之差」是真实用车节奏
        var dated: [(date: Date, s: (monthBack: Int, day: Int, energy: Double, cost: Double, socB: Double, socA: Double, type: Int16, note: String))] = []
        for s in samples {
            let date = cal.date(byAdding: .day, value: -(s.monthBack * 30 + s.day), to: Date()) ?? Date()
            dated.append((date, s))
        }
        dated.sort { $0.date < $1.date }

        var odo: Double = 21000
        for (index, item) in dated.enumerated() {
            let s = item.s
            odo += Double(220 + index * 15)
            let rec = ChargeRecord(id: UUID(), vehicleID: car.id, date: item.date, odometerKm: odo,
                                   energyKWh: s.energy, costCNY: s.cost, chargerType: s.type,
                                   socBefore: s.socB, socAfter: s.socA, note: s.note, createdAt: item.date)
            store.saveRecordQuiet(rec)
        }
        store.setActive(car.id)
    }
}
#endif
