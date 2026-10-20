import SwiftUI
import CoreData

// MARK: - 值类型 DTO（视图层消费，派生值不落库 —— 与蓝图一致）
struct Vehicle: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var ratedRangeKm: Double
    var rangeStandard: Int16
    var batteryKWh: Double
    var usableKWh: Double?
    var createdAt: Date

    var effectiveUsableKWh: Double {
        if let u = usableKWh, u > 0 { return u }
        return batteryKWh * 0.9
    }
    var standardName: String { RangeStandard(raw: rangeStandard).name }
}

struct ChargeRecord: Identifiable, Hashable, Codable {
    var id: UUID
    var vehicleID: UUID
    var date: Date
    var odometerKm: Double
    var energyKWh: Double
    var costCNY: Double
    var chargerType: Int16
    var socBefore: Double?
    var socAfter: Double?
    var note: String
    var createdAt: Date
}

enum ChargerType: Int16, CaseIterable {
    case home = 0, fast = 1, slow = 2
    var name: String { switch self { case .home: return "家充"; case .fast: return "快充"; case .slow: return "慢充" } }
    var color: Color { switch self { case .home: return Color(red: 0.05, green: 0.65, blue: 0.42); case .fast: return .orange; case .slow: return .blue } }
    var icon: String { switch self { case .home: return "house.fill"; case .fast: return "bolt.fill"; case .slow: return "powerplug.fill" } }
}

struct RangeStandard {
    let raw: Int16
    var name: String { switch raw { case 1: return "WLTP"; case 2: return "自定义"; default: return "CLTC" } }
}

enum StatsWindow: String, CaseIterable {
    case all = "global", threeMonths = "3m", currentMonth = "1m"
    var name: String { switch self { case .all: return "全部时间"; case .threeMonths: return "近 3 月"; case .currentMonth: return "当月" } }
    var sinceStartOfMonthBack: Int { switch self { case .all: return 0; case .threeMonths: return 2; case .currentMonth: return 0 } }
    var includeOnlyCurrentMonth: Bool { self == .currentMonth }
}

// MARK: - Core Data 纯本地持久层（程序化建模，无云端依赖）

final class PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer   // 纯本地容器

    init() {
        let model = PersistenceController.makeModel()
        let container = NSPersistentContainer(name: "EVLogger", managedObjectModel: model)
        let desc = NSPersistentStoreDescription(url: Self.storeURL())
        // 历史追踪必须保持开启：旧版本已用该选项创建过 store，关闭会被 Core Data 强制只读
        desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [desc]
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.container = container

        container.loadPersistentStores { _, error in
            if let error = error as NSError? { NSLog("EVLogger store load error: \(error)"); return }
            // 加载完成后通知 Store 重读镜像（loadPersistentStores 异步，首次 fetch 可能拿空库）
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .EVDataChanged, object: nil)
            }
        }
    }

    static func storeURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("EVLogger.sqlite")
    }

    /// 后台自动备份目录（应用沙盒内，可被“文件”App 访问）
    static var backupDir: URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("EVLoggerBackups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }


    // 程序化构建模型（含 v1.1 字段；不新增字段以避免旧库不兼容——温度等采用 UserDefaults 元数据）
    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        func attr(_ name: String, _ type: NSAttributeType) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            return a
        }
        func entity(_ name: String, _ attrs: [NSAttributeDescription]) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = name
            e.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            e.properties = attrs
            return e
        }

        let vehicleEntity = entity("Vehicle", [
            attr("id", .UUIDAttributeType),
            attr("name", .stringAttributeType),
            attr("ratedRangeKm", .doubleAttributeType),
            attr("rangeStandard", .integer16AttributeType),
            attr("batteryKWh", .doubleAttributeType),
            attr("usableKWh", .doubleAttributeType),
            attr("createdAt", .dateAttributeType),
        ])

        let recordEntity = entity("ChargeRecord", [
            attr("id", .UUIDAttributeType),
            attr("vehicleID", .UUIDAttributeType),
            attr("date", .dateAttributeType),
            attr("odometerKm", .doubleAttributeType),
            attr("energyKWh", .doubleAttributeType),
            attr("costCNY", .doubleAttributeType),
            attr("chargerType", .integer16AttributeType),
            attr("socBefore", .doubleAttributeType),
            attr("socAfter", .doubleAttributeType),
            attr("note", .stringAttributeType),
            attr("createdAt", .dateAttributeType),
        ])

        model.entities = [vehicleEntity, recordEntity]
        return model
    }

    // MARK: 读取
    func fetchVehicles() -> [Vehicle] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "Vehicle")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        guard let objs = try? container.viewContext.fetch(req) else { return [] }
        return objs.map { obj in
            Vehicle(
                id: (obj.value(forKey: "id") as? UUID) ?? UUID(),
                name: (obj.value(forKey: "name") as? String) ?? "我的车",
                ratedRangeKm: (obj.value(forKey: "ratedRangeKm") as? Double) ?? 0,
                rangeStandard: (obj.value(forKey: "rangeStandard") as? Int16) ?? 0,
                batteryKWh: (obj.value(forKey: "batteryKWh") as? Double) ?? 0,
                usableKWh: { let v = (obj.value(forKey: "usableKWh") as? Double) ?? 0; return v > 0 ? v : nil }(),
                createdAt: (obj.value(forKey: "createdAt") as? Date) ?? Date()
            )
        }
    }

    func fetchRecords() -> [ChargeRecord] {
        let req = NSFetchRequest<NSManagedObject>(entityName: "ChargeRecord")
        req.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        guard let objs = try? container.viewContext.fetch(req) else { return [] }
        return objs.map { obj in
            ChargeRecord(
                id: (obj.value(forKey: "id") as? UUID) ?? UUID(),
                vehicleID: (obj.value(forKey: "vehicleID") as? UUID) ?? UUID(),
                date: (obj.value(forKey: "date") as? Date) ?? Date(),
                odometerKm: (obj.value(forKey: "odometerKm") as? Double) ?? 0,
                energyKWh: (obj.value(forKey: "energyKWh") as? Double) ?? 0,
                costCNY: (obj.value(forKey: "costCNY") as? Double) ?? 0,
                chargerType: (obj.value(forKey: "chargerType") as? Int16) ?? 0,
                socBefore: optionalDouble(obj, "socBefore"),
                socAfter: optionalDouble(obj, "socAfter"),
                note: (obj.value(forKey: "note") as? String) ?? "",
                createdAt: (obj.value(forKey: "createdAt") as? Date) ?? Date()
            )
        }
    }

    private func optionalDouble(_ obj: NSManagedObject, _ key: String) -> Double? {
        guard let v = obj.value(forKey: key) as? Double, v > 0 else { return nil }
        return v
    }

    // MARK: 写入
    @discardableResult
    func upsertVehicle(_ v: Vehicle) -> Bool {
        let ctx = container.viewContext
        let obj = findOrCreate(ctx, entity: "Vehicle", id: v.id)
        obj.setValue(v.id, forKey: "id")
        obj.setValue(v.name, forKey: "name")
        obj.setValue(v.ratedRangeKm, forKey: "ratedRangeKm")
        obj.setValue(v.rangeStandard, forKey: "rangeStandard")
        obj.setValue(v.batteryKWh, forKey: "batteryKWh")
        obj.setValue(v.usableKWh ?? 0, forKey: "usableKWh")
        obj.setValue(v.createdAt, forKey: "createdAt")
        do { try ctx.save(); return true }
        catch { NSLog("EVLogger upsertVehicle: \(error)"); return false }
    }

    @discardableResult
    func upsertRecord(_ r: ChargeRecord) -> Bool {
        let ctx = container.viewContext
        let obj = findOrCreate(ctx, entity: "ChargeRecord", id: r.id)
        obj.setValue(r.id, forKey: "id")
        obj.setValue(r.vehicleID, forKey: "vehicleID")
        obj.setValue(r.date, forKey: "date")
        obj.setValue(r.odometerKm, forKey: "odometerKm")
        obj.setValue(r.energyKWh, forKey: "energyKWh")
        obj.setValue(r.costCNY, forKey: "costCNY")
        obj.setValue(r.chargerType, forKey: "chargerType")
        obj.setValue(r.socBefore ?? 0, forKey: "socBefore")
        obj.setValue(r.socAfter ?? 0, forKey: "socAfter")
        obj.setValue(r.note, forKey: "note")
        obj.setValue(r.createdAt, forKey: "createdAt")
        do { try ctx.save(); return true }
        catch { NSLog("EVLogger upsertRecord: \(error)"); return false }
    }

    @discardableResult
    func delete(entity: String, id: UUID) -> Bool {
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let obj = (try? container.viewContext.fetch(req))?.first else { return true }
        container.viewContext.delete(obj)
        do { try container.viewContext.save(); return true }
        catch { NSLog("EVLogger delete: \(error)"); return false }
    }

    func deleteAll() {
        let ctx = container.viewContext
        ["Vehicle", "ChargeRecord"].forEach { en in
            let req = NSFetchRequest<NSManagedObject>(entityName: en)
            if let objs = try? ctx.fetch(req) { objs.forEach { ctx.delete($0) } }
        }
        try? ctx.save()
    }

    private func findOrCreate(_ ctx: NSManagedObjectContext, entity: String, id: UUID) -> NSManagedObject {
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let obj = (try? ctx.fetch(req))?.first { return obj }
        return NSEntityDescription.insertNewObject(forEntityName: entity, into: ctx)
    }
}

extension Notification.Name {
    static let EVDataChanged = Notification.Name("EVDataChanged")
}
