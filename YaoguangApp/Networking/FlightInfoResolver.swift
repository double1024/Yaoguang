import Foundation
import Combine
import SwiftUI

/// API 查询的实时活动，用于在界面上提示「正在进行 / 已成功 / 失败」。
enum APIActivity: Equatable {
    case idle
    case loading(String)
    case success(String)
    case failure(String)
}

/// 航线查询优先级。
enum LookupPriority: String, CaseIterable, Identifiable {
    case databaseFirst
    case apiFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .databaseFirst: return "数据库优先"
        case .apiFirst: return "API 优先"
        }
    }

    var detail: String {
        switch self {
        case .databaseFirst: return "数据库中已有航线时直接使用，不再请求 API。"
        case .apiFirst: return "每次都请求 API，成功时覆盖本地记录。"
        }
    }
}

/// 编排 ADSBdb 查询：按设置的优先级决定查库还是查 API，并发布给 UI。
@MainActor
final class FlightInfoResolver: ObservableObject {
    @Published private(set) var routes: [String: RouteInfo] = [:]            // key: callsignICAO
    @Published private(set) var aircraftInfo: [String: AircraftInfo] = [:]   // key: icaoHex
    @Published private(set) var activity: APIActivity = .idle

    private let store: HistoryStore
    private let client = ADSBDBClient()
    private var inFlight: Set<String> = []

    /// 与设置页共享的优先级开关（存 UserDefaults）。
    @AppStorage("lookupPriority") private var priorityRaw: String = LookupPriority.databaseFirst.rawValue

    private var priority: LookupPriority {
        LookupPriority(rawValue: priorityRaw) ?? .databaseFirst
    }

    init(store: HistoryStore) {
        self.store = store
    }

    /// 查询航线（按呼号），flightID 用于回填对应航班记录。
    func resolveRoute(callsign: String, flightID: UUID?) async {
        let key = callsign.uppercased()
        if routes[key] != nil { return }
        await loadRoute(callsign: key, flightID: flightID)
    }

    /// 强制走 API 重新查询（编辑页「重新查询」使用，绕过优先级设置）。
    func refreshRouteFromAPI(callsign: String, flightID: UUID?) async {
        let key = callsign.uppercased()
        routes.removeValue(forKey: key)
        await loadRoute(callsign: key, flightID: flightID, forceAPI: true)
    }

    private func loadRoute(callsign key: String, flightID: UUID?, forceAPI: Bool = false) async {
        guard !inFlight.contains(key) else { return }

        // 1. 数据库优先：库中有记录就直接用
        if !forceAPI, priority == .databaseFirst {
            if let stored = await store.storedRoute(callsign: key) {
                routes[key] = stored
                activity = .success("Callsign \(key)：\(routeSummary(stored))（数据库）")
                return
            }
        }

        // 2. 请求 API
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        activity = .loading("正在获取 Callsign：\(key) 航线…")
        let url = "https://api.adsbdb.com/v0/callsign/\(key)"
        do {
            let result = try await client.fetchRoute(callsign: key)
            routes[key] = result.info
            activity = .success("Callsign \(key)：\(routeSummary(result.info))")
            await store.storeRoute(result.info, flightID: flightID, rawJSON: result.rawJSON, requestURL: url)
        } catch {
            // API 失败时回退到数据库中的既有记录（如果有）
            if let stored = await store.storedRoute(callsign: key) {
                routes[key] = stored
                activity = .failure("Callsign \(key) 请求失败，使用数据库记录")
            } else {
                activity = .failure("Callsign \(key) 获取失败：\(error)")
            }
            await store.recordAPIFailure(requestKey: "callsign:\(key)", provider: "adsbdb",
                                         requestURL: url, error: String(describing: error))
        }
    }

    /// 查询飞机档案（按 ICAO hex）。不参与优先级开关：库中有记录即不再请求。
    func resolveAircraft(icaoHex: String) async {
        let key = icaoHex.uppercased()
        guard !inFlight.contains("aircraft:\(key)") else { return }
        if aircraftInfo[key] != nil { return }
        if let cached = await store.cachedAircraftInfo(icaoHex: key) {
            aircraftInfo[key] = cached
            activity = .success("ICAO \(key)：\(aircraftSummary(cached))（数据库）")
            return
        }
        inFlight.insert("aircraft:\(key)")
        defer { inFlight.remove("aircraft:\(key)") }
        activity = .loading("正在获取 ICAO：\(key) 信息…")
        let url = "https://api.adsbdb.com/v0/aircraft/\(key)"
        do {
            let result = try await client.fetchAircraft(icaoHex: key)
            aircraftInfo[key] = result.info
            activity = .success("ICAO \(key)：\(aircraftSummary(result.info))")
            await store.storeAircraftInfo(result.info, icaoHex: key, rawJSON: result.rawJSON, requestURL: url)
        } catch {
            activity = .failure("ICAO \(key) 获取失败：\(error)")
            await store.recordAPIFailure(requestKey: "aircraft:\(key)", provider: "adsbdb",
                                         requestURL: url, error: String(describing: error))
        }
    }

    // MARK: - 编辑

    /// 读取编辑用的航线原始记录。
    func editableRoute(callsign: String) async -> EditableRoute? {
        await store.editableRoute(callsign: callsign)
    }

    func knownAirportName(_ icaoCode: String) async -> String? {
        await store.knownAirportName(icaoCode: icaoCode)
    }

    func knownAirlineName(_ icaoCode: String) async -> String? {
        await store.knownAirlineName(icaoCode: icaoCode)
    }

    /// 保存手工编辑并立即刷新表格。
    @discardableResult
    func saveManualRoute(
        callsignICAO: String,
        originICAO: String?,
        originName: String?,
        destinationICAO: String?,
        destinationName: String?,
        airlineICAO: String?,
        airlineName: String?
    ) async -> RouteInfo {
        let info = await store.saveManualRoute(
            callsignICAO: callsignICAO,
            originICAO: originICAO, originName: originName,
            destinationICAO: destinationICAO, destinationName: destinationName,
            airlineICAO: airlineICAO, airlineName: airlineName
        )
        routes[callsignICAO.uppercased()] = info
        activity = .success("Callsign \(callsignICAO.uppercased())：已保存手工航线")
        return info
    }

    // MARK: - 摘要文本

    private func routeSummary(_ info: RouteInfo) -> String {
        guard let origin = info.origin?.iataCode ?? info.origin?.icaoCode,
              let destination = info.destination?.iataCode ?? info.destination?.icaoCode else {
            return "无航线记录"
        }
        let airline = info.airline?.name.map { "（\($0)）" } ?? ""
        return "\(origin) → \(destination)\(airline)"
    }

    private func aircraftSummary(_ info: AircraftInfo) -> String {
        let type = info.aircraftType ?? info.icaoType ?? "未知机型"
        let registration = info.registration.map { " \($0)" } ?? ""
        return "\(type)\(registration)"
    }
}
