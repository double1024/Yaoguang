import Foundation
import Security

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


enum WidgetSharedStorage {
    static let appGroupIdentifier = "53Q9GARPRK.com.yaoguang.shared"
    static let fileName = "widget-flight.json"

    private static let keychainService = "com.yaoguang.app.widget"
    private static let keychainAccount = "flight-snapshot"
    private static let keychainAccessGroup = "53Q9GARPRK.yaoguang.shared"

    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static func snapshotURL() -> URL? {
        guard let container = containerURL() else { return nil }
        return container
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func load() -> WidgetFlightSnapshot? {
        if let url = snapshotURL(), let data = try? Data(contentsOf: url), let snapshot = decode(data) {
            return snapshot
        }
        return loadFromKeychain()
    }

    private static func loadFromKeychain() -> WidgetFlightSnapshot? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return decode(data)
    }

    private static func decode(_ data: Data) -> WidgetFlightSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(WidgetFlightSnapshot.self, from: data)
    }
}
