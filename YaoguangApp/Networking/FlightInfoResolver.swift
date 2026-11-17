import Foundation
import Combine

/// API 查询的实时活动，用于在界面上提示「正在进行 / 已成功 / 失败」。
enum APIActivity: Equatable {
    case idle
    case loading(String)
    case success(String)
    case failure(String)
}

/// 编排 ADSBdb 查询：内存缓存 + 存储缓存去重 + URLSession 拉取 + 回写存储 + 发布给 UI。
@MainActor
final class FlightInfoResolver: ObservableObject {
    @Published private(set) var routes: [String: RouteInfo] = [:]            // key: callsignICAO
    @Published private(set) var aircraftInfo: [String: AircraftInfo] = [:]   // key: icaoHex
    @Published private(set) var activity: APIActivity = .idle

    private let store: HistoryStore
    private let client = ADSBDBClient()
    private var inFlight: Set<String> = []

    init(store: HistoryStore) {
        self.store = store
    }

    /// 查询航线（按呼号），flightID 用于回填对应航班记录。
    func resolveRoute(callsign: String, flightID: UUID?) async {
        let key = callsign.uppercased()
        guard !inFlight.contains(key) else { return }
        if routes[key] != nil { return }
        if let cached = await store.cachedRoute(callsign: key) {
            routes[key] = cached
            activity = .success("Callsign \(key)：\(routeSummary(cached))（缓存）")
            return
        }
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
            activity = .failure("Callsign \(key) 获取失败：\(error)")
            await store.recordAPIFailure(requestKey: "callsign:\(key)", provider: "adsbdb", requestURL: url, error: String(describing: error))
        }
    }

    /// 查询飞机档案（按 ICAO hex）。
    func resolveAircraft(icaoHex: String) async {
        let key = icaoHex.uppercased()
        guard !inFlight.contains("aircraft:\(key)") else { return }
        if aircraftInfo[key] != nil { return }
        if let cached = await store.cachedAircraftInfo(icaoHex: key) {
            aircraftInfo[key] = cached
            activity = .success("ICAO \(key)：\(aircraftSummary(cached))（缓存）")
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
            await store.recordAPIFailure(requestKey: "aircraft:\(key)", provider: "adsbdb", requestURL: url, error: String(describing: error))
        }
    }

    // MARK: - 摘要文本

    private func routeSummary(_ info: RouteInfo) -> String {
        guard let origin = info.origin?.iataCode, let destination = info.destination?.iataCode else {
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
