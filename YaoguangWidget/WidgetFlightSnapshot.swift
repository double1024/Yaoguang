import Foundation

/// 主应用写入、小组件扩展读取的共享快照。
///
/// 扩展是独立进程，不能直接访问主应用的 SwiftData 存储；主应用把最新一架飞机
/// 的展示字段（含航司 logo 的 PNG 数据）写成 JSON，扩展按需读取。
struct WidgetFlightSnapshot: Codable, Equatable {
    static let schemaVersion = 3

    var version: Int = WidgetFlightSnapshot.schemaVersion
    var writtenAt: Date
    var origin: String?
    var destination: String?
    var airlineName: String?
    var flightNumber: String?
    var aircraftType: String?
    /// 飞机制造商（如 Airbus）。
    var manufacturer: String?
    /// 演示模式开关：为 true 时小组件忽略此快照内容，改用内置演示数据轮播。
    var demoMode: Bool?
    /// 航司 logo 的 PNG 数据（由主应用从 flightaware_logos 读取后嵌入）。
    var airlineLogoData: Data?

    var cardData: FlightCardData {
        let aircraftName = [normalized(manufacturer), normalized(aircraftType)]
            .compactMap { $0 }
            .joined(separator: " ")
        return FlightCardData(
            origin: normalized(origin) ?? "-",
            destination: normalized(destination) ?? "-",
            airlineName: normalized(airlineName),
            flightNumberText: normalized(flightNumber).map { "Flight No. \($0)" },
            aircraftText: aircraftName.isEmpty ? nil : "Aircraft: \(aircraftName)",
            airlineLogoData: airlineLogoData
        )
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}


enum WidgetSharedStorage {
    static let appGroupIdentifier = "53Q9GARPRK.com.yaoguang.shared"
    static let fileName = "widget-flight.json"

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static func snapshotURL() -> URL? {
        guard let container = containerURL() else { return nil }
        return container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// 读取快照。
    /// 不校验 version：新增字段都是可选的，旧文件解码后缺失字段为 nil，
    /// 这样调整字段不会让已有数据整份失效。
    static func load() -> WidgetFlightSnapshot? {
        guard let url = snapshotURL(), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(WidgetFlightSnapshot.self, from: data)
    }
}
