import Foundation
import SwiftUI

// ============================================================
// 通用模型 —— 与 Scriptable 版 MG4 小组件的数据结构保持一致
// 数据源 JSON: { "data": { "vehicle_value": {...},
//                          "vehicle_state": {...},
//                          "vehicle_position": "lat,lng" | [lat,lng] | {...} } }
// ============================================================

/// 一辆车的“此刻状态快照”（由网络数据规整后得到，供 App 与小组件共同消费）
struct VehicleSnapshot: Codable, Equatable {
    /// 动力电池电量 0-100 (%)
    var battery: Int?
    /// 续航里程原始值（km），可能为 "--" 或缺省
    var range: String?
    /// 总里程（km）
    var odometer: Int?
    /// 车内温度原始值（°C）
    var interiorTemp: String?
    /// 小电瓶(12V)电压（V）
    var voltage: Double?
    /// 门锁状态
    var locked: Bool?
    /// 是否充电中
    var charging: Bool?
    /// 车门/车窗/后备箱是否全部关闭
    var allClosed: Bool?
    /// 当前未关闭的车门/车窗/舱盖明细（nil/空 = 全部关闭），如 ["右前门","左后窗","后备箱"]
    var openParts: [String]?
    /// 四轮胎压（bar）
    var tyres: [String: Double]?
    /// CLTC 满电标称续航（km，来自接口 battery_pack_range，如 425）
    var cltcRange: Int?
    var lat: Double?
    var lng: Double?
    /// 位置文字描述（高德逆地理 / 缓存地址）
    var address: String?
    /// 该地址文本对应的真实坐标（用于“近距离复用地址”判定，防止地址粘滞滞后）
    var addrLat: Double?
    var addrLng: Double?
    /// 抓取时间（本机拿到响应的时刻）
    var fetchTime: Date?
    /// 车端数据时间（接口 `data.update_time`）。车机可能几分钟前才上报，
    /// 界面的「更新于」应以此为准；fetchTime 只代表「本机什么时候拉的」。
    var vehicleTime: Date? = nil
    /// 位置数据时间（接口 `vehicle_position.update_time`）：GPS 常比整车状态更旧
    var positionTime: Date? = nil
    /// 接口上报的里程表原始值（未做 0.1 km 换算），诊断页用来核对单位
    var odometerRaw: Int? = nil
    /// 车外温度（°C 字符串）
    var exteriorTemp: String? = nil
    /// 充电状态原始码（`vehicle_value.charge_status`），仅在诊断页展示
    var chargeStatusCode: Int? = nil
    /// 充电状态文案（未充电 / 已插枪 / 充电中 / 已充满）
    var chargeStatusText: String? = nil
    /// 充电剩余分钟（`chrgng_rmnng_time`；1023 是「无效」哨兵，已过滤）
    var chargeRemainingMinutes: Int? = nil
    /// 定位质量：卫星数 / 水平精度因子 / GPS 状态码 / 海拔（米）
    var satellites: Int? = nil
    var hdop: Int? = nil
    var gpsStatus: Int? = nil
    var altitude: Int? = nil
    /// 车内 / 车外 PM2.5（接口用 0 表示未采集）
    var pm25Interior: Int? = nil
    var pm25Exterior: Int? = nil
    /// 车机是否允许上报位置（false = 车机隐私设置关闭，接口不会给坐标）
    var positionAuthorized: Bool? = nil

    static func demo() -> VehicleSnapshot {
        VehicleSnapshot(battery: 68,
                        range: "326",
                        odometer: 23581,
                        interiorTemp: "26.0",
                        voltage: 12.6,
                        locked: true,
                        charging: false,
                        allClosed: true,
                        openParts: nil,
                        tyres: ["fl": 2.5, "fr": 2.5, "rl": 2.5, "rr": 2.4],
                        cltcRange: 425,
                        lat: 31.23, lng: 121.47,
                        address: "上海市·演示数据",
                        fetchTime: Date())
    }

    /// 数据是否“新鲜”（15 分钟内）——按车端时间算，没有车端时间才退回抓取时间
    var isFresh: Bool {
        guard let t = vehicleTime ?? fetchTime else { return false }
        return Date().timeIntervalSince(t) < 15 * 60
    }

    /// 位置数据是否已经明显滞后（超过 30 分钟）：用于在位置卡上给出提示
    var positionIsStale: Bool {
        guard let t = positionTime else { return false }
        return Date().timeIntervalSince(t) > 30 * 60
    }

    /// 是否处于“需要充电”状态：电量 ≤ 阈值 且 不在充电（App 横幅 / 小组件标识 / 通知共用的判定）
    func needsCharge(threshold: Int) -> Bool {
        guard let b = battery, charging != true else { return false }
        return b <= threshold
    }
}

/// 用户配置（写入 App Group，App 与小组件共享；键名与 Scriptable 版对齐）
struct AppConfig: Codable, Equatable {
    var apiURL: String = ""
    var carModel: String = "MG4"
    var carName: String = "电掣风行"
    var carPlate: String = "沪A·888888"
    /// 车辆识别码（VIN，17 位车架号；用户在设置中填写，车况页第一模块展示）
    var carVin: String = ""
    var carColor: String = "Grey"
    var theme: String = "auto"   // auto / dark / light
    /// 未锁/门窗未关时本地提醒（默认开）
    var lockRemind: Bool = true
    /// 低电量充电提醒（默认开）：电量 ≤ 阈值且未充电时横幅提示 + 刷新触发本地通知
    var lowBatteryRemind: Bool = true
    /// 低电量触发阈值（%），默认 20，可设 5~50
    var lowBatteryThreshold: Int = 20
    /// 地图坐标修正：车辆接口为 GPS(WGS-84) 时开启，映射到国内地图(GCJ-02)
    var mapFix: Bool = false
    /// 手动校准偏移（度）：在地图上点出车辆实际位置后，补偿接口上报偏差；车挪位后可清除
    var latOff: Double = 0
    var lngOff: Double = 0
    /// 手动填写的 CLTC 标称续航（km）：用于车况页“续航达成率”计算。
    /// 注意：**不要**再从接口的 `battery_pack_range` 猜——那是「当前可跑里程」，
    /// 抓包实测 75.7% 电量时该字段为 290（换算满电约 383 km），与 CLTC 437 不是一回事。
    var cltcNominal: Int? = nil
    /// 电池包容量（kWh）：用于把 SOC 换算成「剩余电量 kWh」。MG4 常见 42.8 / 51 / 64。
    /// 必须保持 Optional：老配置 JSON 里没有这个键。
    var packKWh: Double? = nil
    /// 里程单位开关：接口若以 0.1 km 上报（2381 表示 238.1 km），打开后除以 10。
    /// 抓包实测 MG4 上报 2381，需与车机仪表核对；默认按 km 直接显示。
    var odometerInDecikm: Bool = false

    /// 车型预设（点一下同时填容量与 CLTC），数值来自官方参数
    struct PackPreset: Identifiable {
        let id: String
        let label: String
        let kwh: Double
        let cltc: Int
    }
    static let packPresets: [PackPreset] = [
        PackPreset(id: "mg4-42", label: "MG4 42.8 kWh · CLTC 437", kwh: 42.8, cltc: 437),
        PackPreset(id: "mg4-51", label: "MG4 51 kWh · CLTC 425", kwh: 51, cltc: 425),
        PackPreset(id: "mg4-64", label: "MG4 64 kWh · CLTC 520", kwh: 64, cltc: 520)
    ]
    /// 兜底值：未填容量/CLTC 时按最常见的 42.8 kWh 版本算，避免达成率显示 "--"
    static let defaultPackKWh: Double = 42.8
    static let defaultCLTC: Int = 437
    /// 高德「Web 服务」Key：填写后用车况坐标做逆地理编码（坐标 → 中文地址）；
    /// 留空则完全不请求第三方，位置只显示「已定位」与坐标本身，坐标不外发。
    /// 必须保持 Optional：老配置 JSON 里没有这个键，非可选属性会让整个 config
    /// 解码失败、用户已填的接口地址与车辆信息被重置成默认值。
    var amapKey: String? = nil

    /// 可选车辆颜色（存储键 -> 展示名）
    static let colorNames: [String: String] = [
        "Purple": "东来紫", "Green": "清波翠", "Red": "珊瑚红", "Blue": "海岛蓝",
        "Grey": "星野灰", "White": "月光白", "Mulan-Grey": "老款MG4灰色"
    ]

    static let themeNames: [String: String] = [
        "auto": "跟随系统", "dark": "深色模式", "light": "浅色模式"
    ]

    /// 用户是否还没填 API 地址
    var needsSetup: Bool { apiURL.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// 主题模式（与 Scriptable 版一致：auto 跟随系统）
enum ThemeMode: String {
    case auto, dark, light
    init(raw: String?) { self = ThemeMode(rawValue: raw ?? "") ?? .auto }
    /// nil=跟随系统；true=深色；false=浅色
    var forcedDark: Bool? {
        switch self {
        case .dark: return true
        case .light: return false
        case .auto: return nil
        }
    }
}

// ------------------------------------------------------------
// 调色板：把 Scriptable 版三套主题的颜色取值集中管理
// （App 与小组件统一取色，保持与原脚本观感一致）
// ------------------------------------------------------------

extension Color {
    /// 从 0xRRGGBB 构造
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

struct Palette {
    let bg: Color
    let card: Color
    let text: Color
    let sub: Color
    let green: Color
    let red: Color
    let orange: Color
    let blue: Color
    let darkGray: Color
    let footer: Color
    let lockOn: Color
    let lockOff: Color
    let doorOn: Color
    let doorOff: Color

    static func dark() -> Palette {
        Palette(bg: Color(hex: 0x1c1c1e), card: Color(hex: 0x2c2c2e), text: Color(hex: 0xffffff),
                sub: Color(hex: 0x8e8e93), green: Color(hex: 0x30d158), red: Color(hex: 0xff453a),
                orange: Color(hex: 0xff9f0a), blue: Color(hex: 0x0a84ff), darkGray: Color(hex: 0x3a3a3c),
                footer: Color(hex: 0x252525, alpha: 0.6), lockOn: Color(hex: 0x1a3a1a),
                lockOff: Color(hex: 0x3e2c2c), doorOn: Color(hex: 0x1a3a1a), doorOff: Color(hex: 0x3e2c1a))
    }

    static func light() -> Palette {
        Palette(bg: Color(hex: 0xf2f2f7), card: Color(hex: 0xffffff), text: Color(hex: 0x1c1c1e),
                sub: Color(hex: 0x6e6e73), green: Color(hex: 0x34c759), red: Color(hex: 0xff3b30),
                orange: Color(hex: 0xff9500), blue: Color(hex: 0x007aff), darkGray: Color(hex: 0xd1d1d6),
                footer: Color(hex: 0xe5e5ea, alpha: 0.8), lockOn: Color(hex: 0xd4f5d4),
                lockOff: Color(hex: 0xfde2e2), doorOn: Color(hex: 0xd4f5d4), doorOff: Color(hex: 0xfff3e0))
    }
}

/// 由主题 + 系统环境解析实际配色
func resolvePalette(config: AppConfig, systemDark: Bool) -> Palette {
    switch ThemeMode(raw: config.theme).forcedDark {
    case .some(true): return .dark()
    case .some(false): return .light()
    case .none: return systemDark ? .dark() : .light()
    }
}

// ------------------------------------------------------------
// 数值/显示工具（与原脚本规则一致）
// ------------------------------------------------------------

enum VehicleFormat {
    /// 总里程加千分位逗号，如 23581 -> 23,581
    static func odometer(_ km: Int?) -> String {
        guard let km else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: km)) ?? "\(km)"
    }

    /// 电压保留 1 位小数
    static func voltageText(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.1f", v)
    }

    /// 胎压保留 1 位小数
    static func pressure(_ v: Double?) -> String {
        guard let v else { return "--" }
        return String(format: "%.1f", v)
    }

    /// 更新时间 HH:mm
    static func timeText(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

/// 车辆距离（米，Haversine，与原脚本同算法）
func distanceMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
    let R = 6378137.0
    let p1 = lat1 * .pi / 180
    let p2 = lat2 * .pi / 180
    let dp = (lat2 - lat1) * .pi / 180
    let dl = (lng2 - lng1) * .pi / 180
    let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c
}

// ------------------------------------------------------------
// 坐标系统修正：WGS-84（GPS 原始）→ GCJ-02（国内地图“火星坐标”）
// 车辆接口多为 GPS 坐标；Apple/高德国内地图用 GCJ-02，直接投点会偏移数百米。
// 该函数在境外直接原样返回。
// ------------------------------------------------------------
func wgs2gcj(lat: Double, lng: Double) -> (lat: Double, lng: Double) {
    let a = 6378245.0
    let ee = 0.00669342162296594323
    func outOfChina(_ lat: Double, _ lng: Double) -> Bool {
        !(72.004 <= lng && lng <= 137.8347 && 0.8293 <= lat && lat <= 55.8271)
    }
    func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * .pi) + 40.0 * sin(y / 3.0 * .pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * .pi) + 320 * sin(y * .pi / 30.0)) * 2.0 / 3.0
        return ret
    }
    func transformLng(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * .pi) + 20.0 * sin(2.0 * x * .pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * .pi) + 40.0 * sin(x / 3.0 * .pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * .pi) + 300.0 * sin(x / 30.0 * .pi)) * 2.0 / 3.0
        return ret
    }
    guard !outOfChina(lat, lng) else { return (lat, lng) }
    var dLat = transformLat(lng - 105.0, lat - 35.0)
    var dLng = transformLng(lng - 105.0, lat - 35.0)
    let radLat = lat / 180.0 * .pi
    var magic = sin(radLat)
    magic = 1 - ee * magic * magic
    let sqrtMagic = sqrt(magic)
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
    dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * .pi)
    return (lat + dLat, lng + dLng)
}

/// 从 Scriptable 版一致的“坏地址”清单判断是否需要重新取地址
func isBadAddress(_ text: String?) -> Bool {
    guard let text else { return true }
    let bad = ["等待位置数据...", "等待位置...", "车辆未上报位置", "位置服务异常", ""]
    return bad.contains(text.trimmingCharacters(in: .whitespaces))
}

// ------------------------------------------------------------
// 地图坐标：显示 / 导航 / 逆地理编码共用同一套换算
// （三处若各算各的，地址文本就会和地图上的点、导航终点错开）
// ------------------------------------------------------------

/// 坐标是否落在中国大陆范围内（高德逆地理只覆盖国内，境外没必要发请求）
/// 边界与 wgs2gcj 内部的 outOfChina 保持一致。
func isInChina(lat: Double, lng: Double) -> Bool {
    72.004 <= lng && lng <= 137.8347 && 0.8293 <= lat && lat <= 55.8271
}

/// 把接口上报坐标换算成地图坐标：按配置决定是否 WGS-84 → GCJ-02，再叠加手动校准偏移。
func mapDisplayCoord(lat: Double, lng: Double, config: AppConfig) -> (lat: Double, lng: Double) {
    let fixed: (lat: Double, lng: Double) = config.mapFix
        ? wgs2gcj(lat: lat, lng: lng)
        : (lat: lat, lng: lng)
    return (lat: fixed.lat + config.latOff, lng: fixed.lng + config.lngOff)
}
