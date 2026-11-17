import Foundation

/// 主应用写入、小组件扩展读取的共享快照。
///
/// 扩展是独立进程，不能直接访问主应用的 SwiftData 存储；主应用把最新一架飞机
/// 的展示字段（含航司 logo 的 PNG 数据）写成 JSON，扩展按需读取。
struct WidgetFlightSnapshot: Codable, Equatable {
    static let schemaVersion = 2

    var version: Int = WidgetFlightSnapshot.schemaVersion
    var writtenAt: Date
    var origin: String?
    var destination: String?
    var airlineName: String?
    var flightNumber: String?
    var aircraftType: String?
    /// 航司 logo 的 PNG 数据（由主应用从 flightaware_logos 读取后嵌入）。
    var airlineLogoData: Data?

    var cardData: FlightCardData {
        FlightCardData(
            origin: normalized(origin) ?? "-",
            destination: normalized(destination) ?? "-",
            airlineName: normalized(airlineName),
            flightNumberText: normalized(flightNumber).map { "Flight \($0)" },
            aircraftText: normalized(aircraftType).map { $0 },
            airlineLogoData: airlineLogoData
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum WidgetDefaultFlight {
    static let origin = "HKG"
    static let destination = "HKG"
    static let airlineName = "HK Express"
    static let flightNumber = "UO1800"
    static let aircraftType = "Airbus A320-271N"

    /// 默认航司 logo（HKE），从小组件自带资源读取。
    static func airlineLogoData() -> Data? {
        guard let url = Bundle.main.url(forResource: "HKE", withExtension: "png") else { return nil }
        return try? Data(contentsOf: url)
    }
}

enum WidgetSharedStorage {
    static let fileName = "widget-flight.json"
    static let directoryName = "Yaoguang"

    /// 与主程序共享：~/Library/Application Support/Yaoguang/widget-flight.json
    static func snapshotURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true) else {
            return nil
        }
        let root = appSupport.appendingPathComponent(directoryName, isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(fileName, isDirectory: false)
    }

    static func load() -> WidgetFlightSnapshot? {
        guard let url = snapshotURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(WidgetFlightSnapshot.self, from: data),
              snapshot.version == WidgetFlightSnapshot.schemaVersion else { return nil }
        return snapshot
    }

    static func save(_ snapshot: WidgetFlightSnapshot) {
        guard let url = snapshotURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let data = try? encoder.encode(snapshot) else { return }
        // 原子写入，避免扩展读到半截文件。
        try? data.write(to: url, options: .atomic)
    }
}
