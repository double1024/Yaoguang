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
    static let service = "com.yaoguang.app.widget"
    static let account = "flight-snapshot"
    static let accessGroup = "53Q9GARPRK.yaoguang.shared"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
        ]
    }

    static func load() -> WidgetFlightSnapshot? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(WidgetFlightSnapshot.self, from: data)
    }
}
