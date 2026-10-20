import Foundation
import UIKit

// ============================================================
// 数据服务 —— 抓取车辆 API、规整字段、逆地理编码（逻辑对齐 Scriptable 原脚本）
// ============================================================

enum ServiceError: LocalizedError {
    case emptyURL
    case badPayload(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .emptyURL:
            return "尚未配置 API 地址，请先在 App 设置中填写"
        case .badPayload(let m):
            return "数据格式异常：\(m)"
        case .network(let m):
            return "网络请求失败：\(m)"
        }
    }
}

struct MG4Service {
    let config: AppConfig

    /// 抓取一次车况并（在位置变动等情况下）逆地理编码，随后写入共享存储
    func fetchAndCache() async throws -> VehicleSnapshot {
        guard !config.apiURL.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: config.apiURL) else {
            throw ServiceError.emptyURL
        }
        let snapshot = try await fetch(from: url)
        SharedStore.saveSnapshot(snapshot)
        return snapshot
    }

    func fetch(from url: URL) async throws -> VehicleSnapshot {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        let data: Data
        do {
            let (d, _) = try await URLSession.shared.data(for: request)
            data = d
        } catch {
            throw ServiceError.network(error.localizedDescription)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = json["data"] as? [String: Any] else {
            throw ServiceError.badPayload("缺少 data 字段")
        }

        return try await buildSnapshot(from: body)
    }

    // MARK: - 数据规整

    private func buildSnapshot(from body: [String: Any]) async throws -> VehicleSnapshot {
        let vehicle = body["vehicle_value"] as? [String: Any] ?? [:]
        let state = body["vehicle_state"] as? [String: Any] ?? [:]

        // --- 电量 / 续航 / 里程 ---
        // 电量自动识别量程：≤100 视为已是百分比（自建桥接常归一化为 0~100）；
        // >100 视为千分制，÷10 得百分比（iSMART/原脚本口径）。
        let battery: Int? = VehicleParse.number(vehicle["battery_pack_prc"]).map { v in
            Int((v <= 100 ? v : v / 10).rounded())
        }

        // 续航：与原脚本 `a || b || '--'` 语义一致 —— 0 / 空串视为“缺省”，
        // 继续尝试下一个候选字段，避免聚合接口某状态下发 0 时界面误显示 “0 km”。
        let rangeRaw = VehicleParse.firstUsable(vehicle["clstr_elec_rng_to_eptv"],
                                                vehicle["battery_pack_range"])
        // CLTC 满电标称续航：多数聚合接口用 battery_pack_range 表示满电参考里程
        let cltc: Int? = VehicleParse.number(vehicle["battery_pack_range"])
            .flatMap { $0 >= 50 ? Int($0.rounded()) : nil }
        let odometer: Int? = {
            guard let n = VehicleParse.number(vehicle["odometer"]), n > 0 else { return nil }
            return Int(n)
        }()

        // --- 门锁 / 充电 / 门窗（状态为 true 即“打开/未关”，与原脚本一致）---
        let locked = VehicleParse.bool(state["lock"])
        let charging = VehicleParse.bool(state["charge"])

        // 逐项收集未关闭部件（顺序：四门 → 舱盖/后备箱/天窗 → 四窗）
        let partDefs: [(key: String, name: String)] = [
            ("driver_door", "左前门"), ("passenger_door", "右前门"),
            ("rear_left_door", "左后门"), ("rear_right_door", "右后门"),
            ("bonnet", "前舱盖"), ("boot", "后备箱"), ("sunroof", "天窗"),
            ("driver_window", "左前窗"), ("passenger_window", "右前窗"),
            ("rear_left_window", "左后窗"), ("rear_right_window", "右后窗")]
        let openParts: [String] = partDefs
            .filter { VehicleParse.bool(state[$0.key]) == true }
            .map(\.name)
        let allClosed = openParts.isEmpty

        // --- 温度 / 小电瓶电压 / 胎压 ---
        let temp = VehicleParse.string(vehicle["interior_temperature"])
        let voltage = VehicleParse.number(vehicle["vehicle_battery"]).map { $0 / 100.0 }
        var tyres: [String: Double]? = nil
        let tyreKeys: [(String, String)] = [
            ("fl", "front_left_tyre_pressure"), ("fr", "front_right_tyre_pressure"),
            ("rl", "rear_left_tyre_pressure"), ("rr", "rear_right_tyre_pressure")]
        for (k, field) in tyreKeys {
            guard let v = VehicleParse.number(vehicle[field]) else { continue }
            if tyres == nil { tyres = [:] }
            tyres?[k] = (v / 100.0 * 10).rounded() / 10   // 保留 1 位小数
        }

        // --- 位置 ---
        let (lat, lng) = VehicleParse.location(body["vehicle_position"])
        let old = SharedStore.loadSnapshot()
        let fallbackAddr = old?.address
        let fallbackValid = fallbackAddr != nil && !isBadAddress(fallbackAddr)
        var address: String
        // 地址文本对应的坐标：地址复用判定依据（防止“地址粘滞”滞后）
        var addrLat = old?.addrLat
        var addrLng = old?.addrLng

        // 仅在“新位置离该地址文本自己的坐标”100m 内时沿用缓存文本；
        // 车挪到邻近街道（旧逻辑阈值 200m 会命中）时将重新逆地理，保证显示跟得上。
        if let refLat = old?.addrLat, let refLng = old?.addrLng,
           let lat, let lng, !isBadAddress(fallbackAddr),
           distanceMeters(lat1: lat, lng1: lng, lat2: refLat, lng2: refLng) < 100 {
            address = fallbackAddr ?? "等待位置数据..."
        } else if let lat, let lng {
            // 不做任何第三方逆地理：只用本地缓存的地址文本，否则只显示「已定位」，坐标不外发
            if fallbackValid {
                address = fallbackAddr!
            } else {
                address = "已定位"
                addrLat = nil
                addrLng = nil
            }
        } else if let fallbackAddr, !isBadAddress(fallbackAddr) {
            address = fallbackAddr
        } else {
            address = "车辆未上报位置"
            addrLat = nil
            addrLng = nil
        }

        return VehicleSnapshot(battery: battery,
                               range: rangeRaw,
                               odometer: odometer,
                               interiorTemp: temp,
                               voltage: voltage,
                               locked: locked,
                               charging: charging,
                               allClosed: allClosed,
                               openParts: allClosed ? nil : openParts,
                               tyres: tyres,
                               cltcRange: cltc,
                               lat: lat, lng: lng,
                               address: address,
                               addrLat: addrLat, addrLng: addrLng,
                               fetchTime: Date())
    }

}

// MARK: - 宽容解析（服务端字段可能是 NSNumber / String / Bool）

enum VehicleParse {
    static func number(_ v: Any?) -> Double? {
        guard let v else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String, let d = Double(s) { return d }
        return nil
    }

    static func string(_ v: Any?) -> String? {
        guard let v else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    /// 按顺序取第一个“可用”值：字段缺失、空串或数值为 0 时跳过（对齐原脚本 `a || b || '--'`）。
    /// 用例如续航：车辆某状态可能下发 0，此时应回退到备用字段或显示 "--"。
    static func firstUsable(_ values: Any?...) -> String? {
        for v in values {
            guard let s = string(v)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { continue }
            // "0" / "0.0" / "-0" 视为无效值
            if let n = Double(s), n == 0 { continue }
            return s
        }
        return nil
    }

    /// 与原脚本一致：仅当严格等于 true 才视为真
    static func bool(_ v: Any?) -> Bool? {
        guard let b = v as? Bool else { return nil }
        return b
    }

    /// 位置解析：兼容 "lat,lng" / [lat, lng] / {"latitude":..,"longitude":..} / {"lat":..,"lng":..}
    /// 解析后自动纠正“lng,lat 反序”：中国范围内纬度 18~54、经度 73~136 互不重叠，
    /// 可据此识别接口误按“经度,纬度”上报的情况，避免逆地理解析到错误地点。
    static func location(_ v: Any?) -> (Double?, Double?) {
        var lat: Double?
        var lng: Double?
        if let s = v as? String, s.contains(",") {
            let parts = s.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 2 { lat = parts[0]; lng = parts[1] }
        } else if let arr = v as? [Any], arr.count >= 2 {
            lat = number(arr[0]); lng = number(arr[1])
        } else if let dict = v as? [String: Any] {
            lat = number(dict["latitude"]) ?? number(dict["lat"])
            lng = number(dict["longitude"]) ?? number(dict["lng"])
        }
        return normalizeChina(lat, lng)
    }

    /// 纬度 18~54（中国陆域/海南 ≥18）；经度 73~136。两个值域互不重叠，
    /// 因此“首值落在经度带、次值落在纬度带”即为反序上报（经度,纬度），直接交换。
    private static func normalizeChina(_ lat: Double?, _ lng: Double?) -> (Double?, Double?) {
        guard let la = lat, let ln = lng else { return (lat, lng) }
        if (73.0...136.0).contains(la) && (18.0...54.0).contains(ln) {
            return (ln, la)   // 实为“经度,纬度”，交换
        }
        return (lat, lng)
    }
}

// MARK: - 车辆图片缓存（回归 1.0.8 方案：下载原图 → 原名缓存 → 直接显示，不做任何后处理）

enum CarImageStore {
    /// 只读本地缓存，不联网（开源版移除了远端车图下载，避免任何第三方请求）
    @discardableResult
    static func ensureLocal(color: String) async -> UIImage? {
        localImage(color: color)
    }

    /// 读取本地缓存（小组件使用，避免无谓联网）
    static func localImage(color: String) -> UIImage? {
        guard let url = SharedStore.carImageURL(color: color),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}
