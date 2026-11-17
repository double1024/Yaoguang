import Foundation

/// 主应用写入、小组件扩展读取的共享快照。
///
/// 扩展是独立进程，不能直接访问主应用的 SwiftData 存储；主应用把最新一架飞机
/// 的展示字段写成 JSON，扩展按需读取。
struct WidgetFlightSnapshot: Codable, Equatable {
    static let schemaVersion = 1

    var version: Int = WidgetFlightSnapshot.schemaVersion
    var writtenAt: Date
    var origin: String?
    var destination: String?
    var airlineName: String?
    var flightNumber: String?
    var aircraftType: String?

    var cardData: FlightCardData {
        FlightCardData(
            origin: normalized(origin) ?? "---",
            destination: normalized(destination) ?? "---",
            airlineName: normalized(airlineName),
            flightNumberText: normalized(flightNumber).map { "Flight No. \($0)" },
            aircraftText: normalized(aircraftType).map { "Aircraft: \($0)" }
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
    static let aircraftType = "A320neo"
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
