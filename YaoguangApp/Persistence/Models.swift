import Foundation
import SwiftData

// MARK: - SwiftData 持久化模型

@Model
final class Aircraft {
    @Attribute(.unique) var icaoHex: String
    var registration: String?
    var manufacturer: String?
    var aircraftType: String?
    var icaoType: String?
    var operatorName: String?
    var operatorICAO: String?
    var firstSeen: Date?
    var lastSeen: Date?
    var packetCount: UInt64 = 0

    init(icaoHex: String) {
        self.icaoHex = icaoHex
    }
}

// 注：复合索引宏 #Index/#Unique 在当前工具链（Swift 6.4.2 / Xcode 27.2）存在
// 宏展开顺序 bug（“requires that … conform to PersistentModel”），暂以 @Attribute(.unique)
// 提供单列唯一索引。复合索引（如 icaoHex+timestamp）待工具链修复后再补。
@Model
final class AircraftStateSample {
    @Attribute(.unique) var id: UUID
    var icaoHex: String
    var timestamp: Date
    var altitudeFt: Int32?
    var groundSpeedKt: Double?
    var trackDeg: Double?
    var verticalRateFpm: Int16?
    var callsign: String?
    var signalDbfs: Double?
    var flightID: UUID?

    init(id: UUID = UUID(), icaoHex: String, timestamp: Date) {
        self.id = id
        self.icaoHex = icaoHex
        self.timestamp = timestamp
    }
}

@Model
final class Flight {
    @Attribute(.unique) var id: UUID
    var icaoHex: String
    var callsign: String
    var firstSeen: Date
    var lastSeen: Date
    var originICAO: String?
    var destinationICAO: String?
    var routeSource: String?
    var status: String

    init(id: UUID = UUID(), icaoHex: String, callsign: String, firstSeen: Date, lastSeen: Date, status: String) {
        self.id = id
        self.icaoHex = icaoHex
        self.callsign = callsign
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.status = status
    }
}

@Model
final class FlightRoute {
    @Attribute(.unique) var callsignICAO: String
    var callsignIATA: String?
    var airlineICAO: String?
    var originICAO: String?
    var destinationICAO: String?
    var rawJSON: String?
    var fetchedAt: Date
    /// "adsbdb" 表示来自 API，"manual" 表示用户在编辑页手工修改。
    var routeSource: String?

    init(callsignICAO: String, fetchedAt: Date) {
        self.callsignICAO = callsignICAO
        self.fetchedAt = fetchedAt
    }
}

@Model
final class Airport {
    @Attribute(.unique) var icaoCode: String
    var iataCode: String?
    var name: String
    var municipality: String?
    var country: String?
    var countryISO: String?
    var latitude: Double?
    var longitude: Double?
    var elevation: Double?

    init(icaoCode: String, name: String) {
        self.icaoCode = icaoCode
        self.name = name
    }
}

@Model
final class Airline {
    @Attribute(.unique) var icaoCode: String
    var iataCode: String?
    var name: String
    var country: String?
    var callsign: String?

    init(icaoCode: String, name: String) {
        self.icaoCode = icaoCode
        self.name = name
    }
}

@Model
final class APICache {
    @Attribute(.unique) var requestKey: String
    var provider: String
    var requestURL: String
    var responseJSON: String
    var fetchedAt: Date
    var expiresAt: Date
    var httpStatusCode: Int
    var errorMessage: String?

    init(requestKey: String, provider: String, requestURL: String, responseJSON: String, fetchedAt: Date, expiresAt: Date, httpStatusCode: Int) {
        self.requestKey = requestKey
        self.provider = provider
        self.requestURL = requestURL
        self.responseJSON = responseJSON
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
        self.httpStatusCode = httpStatusCode
    }
}

// MARK: - 版本化 Schema 与迁移

enum YaoguangSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Aircraft.self, AircraftStateSample.self, Flight.self, FlightRoute.self,
         Airport.self, Airline.self, APICache.self]
    }
}

enum YaoguangMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [YaoguangSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - 跨层传输的 Sendable 值类型（非持久化，只用于进程内通信）

/// 一条解码后的有效状态样本，主线程 → 存储 Actor。
struct SampleSnapshot: Sendable {
    let icaoHex: String
    let timestamp: Date
    let altitudeFt: Int32?
    let groundSpeedKt: Double?
    let trackDeg: Double?
    let verticalRateFpm: Int16?
    let callsign: String?
    let signalDbfs: Double?
    let flightID: UUID?
}

/// 新航班记录，主线程 → 存储 Actor。
struct FlightRecord: Sendable {
    let icaoHex: String
    let callsign: String
    let firstSeen: Date
    let lastSeen: Date
}

/// 机场资料（来自 ADSBdb）。
struct AirportInfo: Sendable, Equatable {
    let icaoCode: String?
    let iataCode: String?
    let name: String?
    let municipality: String?
    let country: String?
    let countryISO: String?
    let latitude: Double?
    let longitude: Double?
    let elevation: Double?
}

/// 航空公司资料（来自 ADSBdb）。
struct AirlineInfo: Sendable, Equatable {
    let icaoCode: String?
    let iataCode: String?
    let name: String?
    let country: String?
    let callsign: String?
}

/// 航线信息（来自 ADSBdb callsign 端点）。
struct RouteInfo: Sendable, Equatable {
    let callsignICAO: String
    let callsignIATA: String?
    let airline: AirlineInfo?
    let origin: AirportInfo?
    let destination: AirportInfo?
}

/// 供编辑页使用的航线记录（含已展开的全名）。
struct EditableRoute: Sendable, Equatable {
    let callsignICAO: String
    let callsignIATA: String?
    let airlineICAO: String?
    let airlineName: String?
    let originICAO: String?
    let originName: String?
    let destinationICAO: String?
    let destinationName: String?
    let routeSource: String?
    let fetchedAt: Date
}

/// 飞机档案信息（来自 ADSBdb aircraft 端点）。
struct AircraftInfo: Sendable, Equatable {
    let registration: String?
    let manufacturer: String?
    let aircraftType: String?
    let icaoType: String?
    let operatorName: String?
    let operatorICAO: String?
}

// MARK: - 小组件共享快照

/// 主应用写入、WidgetKit 扩展读取的快照。扩展是独立进程，无法访问 SwiftData。
struct WidgetFlightSnapshot: Codable, Equatable {
    static let schemaVersion = 2

    var version: Int = WidgetFlightSnapshot.schemaVersion
    var writtenAt: Date
    var origin: String?
    var destination: String?
    var airlineName: String?
    var flightNumber: String?
    var aircraftType: String?
    /// 航司 logo 的 PNG 数据（主应用从 flightaware_logos 读取后嵌入）。
    var airlineLogoData: Data?
}

enum WidgetSharedStorage {
    static let appGroupIdentifier = "group.com.yaoguang.app"
    static let fileName = "widget-flight.json"

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    static func snapshotURL() -> URL? {
        containerURL()?.appendingPathComponent(fileName, isDirectory: false)
    }

    static func save(_ snapshot: WidgetFlightSnapshot) {
        guard let url = snapshotURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
