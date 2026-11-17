import Foundation
import SwiftData

/// 独立的持久化写入 Actor。
///
/// 持有一个后台 `ModelContext`，主线程只把数据推入，绝不在此 Actor 之外操作 ModelContext。
/// 写入采用「内存缓存 + 批量 save」：状态样本累计到阈值或由外部定时触发 flush。
@ModelActor
actor HistoryStore {
    /// 样本批量写入阈值。
    private let sampleBatchSize = 100
    /// 数据永久保存（不自动过期），由用户手动删除。
    /// 用极大间隔表达「永不过期」，避免 nil/可选判断散落各处。
    private let permanentTTL: TimeInterval = 100 * 365 * 24 * 3600

    /// 待写入样本计数（对象已 insert 进 context，save 时统一落盘）。
    private var pendingSampleCount = 0

    /// 飞机档案内存缓存，避免每包都查询。
    private var aircraftByHex: [String: Aircraft] = [:]

    // MARK: - 实时写入

    /// 每收到一包就调用：更新飞机档案的首见/最近见/包数。
    func recordPacket(icaoHex: String, timestamp: Date) {
        let aircraft = cachedAircraft(icaoHex: icaoHex)
        if aircraft.firstSeen == nil {
            aircraft.firstSeen = timestamp
        }
        aircraft.lastSeen = timestamp
        aircraft.packetCount &+= 1
    }

    /// 采样通过时追加一条历史状态样本。
    func appendSample(_ sample: SampleSnapshot) {
        let record = AircraftStateSample(icaoHex: sample.icaoHex, timestamp: sample.timestamp)
        record.altitudeFt = sample.altitudeFt
        record.groundSpeedKt = sample.groundSpeedKt
        record.trackDeg = sample.trackDeg
        record.verticalRateFpm = sample.verticalRateFpm
        record.callsign = sample.callsign
        record.signalDbfs = sample.signalDbfs
        record.flightID = sample.flightID
        modelContext.insert(record)
        pendingSampleCount += 1
        if pendingSampleCount >= sampleBatchSize {
            flush()
        }
    }

    /// 开新航班。
    func openFlight(_ record: FlightRecord, id: UUID) {
        let flight = Flight(id: id, icaoHex: record.icaoHex, callsign: record.callsign,
                            firstSeen: record.firstSeen, lastSeen: record.lastSeen,
                            status: "active")
        modelContext.insert(flight)
    }

    /// 结束航班。
    func closeFlight(id: UUID, at: Date) {
        guard let flight = fetchFlight(id: id) else { return }
        flight.status = "ended"
        flight.lastSeen = at
    }

    /// 把一次 ADSBdb 航线查询结果写入：FlightRoute + Airline + Airport + APICache，并回填航班。
    func storeRoute(_ route: RouteInfo, flightID: UUID?, rawJSON: String?, requestURL: String) {
        let now = Date()

        // FlightRoute
        let flightRoute: FlightRoute
        if let existing = fetchFlightRoute(callsignICAO: route.callsignICAO) {
            flightRoute = existing
        } else {
            flightRoute = FlightRoute(callsignICAO: route.callsignICAO, fetchedAt: now)
            modelContext.insert(flightRoute)
        }
        flightRoute.callsignIATA = route.callsignIATA
        flightRoute.airlineICAO = route.airline?.icaoCode
        flightRoute.originICAO = route.origin?.icaoCode
        flightRoute.destinationICAO = route.destination?.icaoCode
        flightRoute.rawJSON = rawJSON
        flightRoute.fetchedAt = now
        flightRoute.routeSource = "adsbdb"

        // Airline
        if let airline = route.airline, let icao = airline.icaoCode, let name = airline.name {
            upsertAirline(icao: icao, info: airline, name: name)
        }
        // Airport（出发/到达分别 upsert）
        if let origin = route.origin { upsertAirport(info: origin) }
        if let destination = route.destination { upsertAirport(info: destination) }

        // 回填航班记录的航线快照
        if let flightID, let flight = fetchFlight(id: flightID) {
            flight.originICAO = route.origin?.icaoCode
            flight.destinationICAO = route.destination?.icaoCode
            flight.routeSource = "adsbdb"
        }

        // APICache
        let key = "callsign:\(route.callsignICAO)"
        upsertAPICache(requestKey: key, provider: "adsbdb", requestURL: requestURL,
                       responseJSON: rawJSON ?? "", fetchedAt: now, httpStatusCode: 200, error: nil)
    }

    /// 写入飞机档案信息（aircraft 端点）。
    func storeAircraftInfo(_ info: AircraftInfo, icaoHex: String, rawJSON: String?, requestURL: String) {
        let now = Date()
        let aircraft = cachedAircraft(icaoHex: icaoHex)
        aircraft.registration = info.registration
        aircraft.manufacturer = info.manufacturer
        aircraft.aircraftType = info.aircraftType
        aircraft.icaoType = info.icaoType
        aircraft.operatorName = info.operatorName
        aircraft.operatorICAO = info.operatorICAO

        let key = "aircraft:\(icaoHex)"
        upsertAPICache(requestKey: key, provider: "adsbdb", requestURL: requestURL,
                       responseJSON: rawJSON ?? "", fetchedAt: now, httpStatusCode: 200, error: nil)
    }

    /// 记录一次 API 失败（不打断实时接收）。
    func recordAPIFailure(requestKey: String, provider: String, requestURL: String, error: String) {
        upsertAPICache(requestKey: requestKey, provider: provider, requestURL: requestURL,
                       responseJSON: "", fetchedAt: Date(), httpStatusCode: 0, error: error)
    }

    // MARK: - 缓存读取

    /// 读取航线。数据永久保存，库中有记录即直接返回（无过期判断）。
    func storedRoute(callsign: String) -> RouteInfo? {
        guard let route = fetchFlightRoute(callsignICAO: callsign.uppercased()) else {
            return nil
        }
        return RouteInfo(
            callsignICAO: route.callsignICAO,
            callsignIATA: route.callsignIATA,
            airline: airlineInfo(for: route.airlineICAO),
            origin: airportInfo(for: route.originICAO),
            destination: airportInfo(for: route.destinationICAO)
        )
    }

    /// 读取飞机档案。数据永久保存，库中有记录即直接返回（无过期判断）。
    func cachedAircraftInfo(icaoHex: String) -> AircraftInfo? {
        let key = "aircraft:\(icaoHex)"
        guard fetchAPICache(requestKey: key) != nil else { return nil }
        guard let aircraft = fetchAircraft(icaoHex: icaoHex) else { return nil }
        return AircraftInfo(
            registration: aircraft.registration,
            manufacturer: aircraft.manufacturer,
            aircraftType: aircraft.aircraftType,
            icaoType: aircraft.icaoType,
            operatorName: aircraft.operatorName,
            operatorICAO: aircraft.operatorICAO
        )
    }

    // MARK: - 航线编辑

    /// 读取用于编辑的原始航线记录（不做 Airport/Airline 展开）。
    func editableRoute(callsign: String) -> EditableRoute? {
        guard let route = fetchFlightRoute(callsignICAO: callsign.uppercased()) else { return nil }
        return EditableRoute(
            callsignICAO: route.callsignICAO,
            callsignIATA: route.callsignIATA,
            airlineICAO: route.airlineICAO,
            airlineName: airlineInfo(for: route.airlineICAO)?.name,
            originICAO: route.originICAO,
            originName: airportInfo(for: route.originICAO)?.name,
            destinationICAO: route.destinationICAO,
            destinationName: airportInfo(for: route.destinationICAO)?.name,
            routeSource: route.routeSource,
            fetchedAt: route.fetchedAt
        )
    }

    /// 保存手工编辑。输入为空的机场/航司会被清除。
    /// 本地不存在的机场/航司会用提供的全名新建记录，保证外键始终有效。
    func saveManualRoute(
        callsignICAO: String,
        originICAO: String?,
        originName: String?,
        destinationICAO: String?,
        destinationName: String?,
        airlineICAO: String?,
        airlineName: String?
    ) -> RouteInfo {
        let now = Date()
        let key = callsignICAO.uppercased()

        let route: FlightRoute
        if let existing = fetchFlightRoute(callsignICAO: key) {
            route = existing
        } else {
            route = FlightRoute(callsignICAO: key, fetchedAt: now)
            modelContext.insert(route)
        }

        route.originICAO = normalized(originICAO)
        route.destinationICAO = normalized(destinationICAO)
        route.airlineICAO = normalized(airlineICAO)
        route.routeSource = "manual"
        route.fetchedAt = now

        // 补齐本地缺失的机场/航司记录
        if let originICAO = normalized(originICAO) {
            ensureAirport(icaoCode: originICAO, name: originName)
        }
        if let destinationICAO = normalized(destinationICAO) {
            ensureAirport(icaoCode: destinationICAO, name: destinationName)
        }
        if let airlineICAO = normalized(airlineICAO) {
            ensureAirline(icaoCode: airlineICAO, name: airlineName)
        }

        return RouteInfo(
            callsignICAO: route.callsignICAO,
            callsignIATA: route.callsignIATA,
            airline: airlineInfo(for: route.airlineICAO),
            origin: airportInfo(for: route.originICAO),
            destination: airportInfo(for: route.destinationICAO)
        )
    }

    /// 机场/航司是否存在（供编辑页提示是否需要填写全名）。
    func knownAirportName(icaoCode: String) -> String? { airportInfo(for: normalized(icaoCode))?.name }
    func knownAirlineName(icaoCode: String) -> String? { airlineInfo(for: normalized(icaoCode))?.name }

    private func normalized(_ code: String?) -> String? {
        guard let code else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 本地已有则保持，缺失则以给定全名（缺省回退为 ICAO 码）新建。
    private func ensureAirport(icaoCode: String, name: String?) {
        if fetchAirport(icaoCode: icaoCode) != nil { return }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmedName?.isEmpty == false) ? trimmedName! : icaoCode
        modelContext.insert(Airport(icaoCode: icaoCode, name: finalName))
    }

    private func ensureAirline(icaoCode: String, name: String?) {
        if fetchAirline(icaoCode: icaoCode) != nil { return }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = (trimmedName?.isEmpty == false) ? trimmedName! : icaoCode
        modelContext.insert(Airline(icaoCode: icaoCode, name: finalName))
    }

    // MARK: - 落盘与对账

    /// 批量落盘。有变更才 save；失败时数据仍留在 context，下次重试。
    func flush() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
            pendingSampleCount = 0
        } catch {
            // 保留变更，等待下次 flush；不在此处吞掉崩溃级错误之外的细节。
        }
    }

    /// 启动对账：把上次运行遗留的 active 航班置为 ended。
    func reconcileActiveFlights(at now: Date) {
        let status = "active"
        let descriptor = FetchDescriptor<Flight>(predicate: #Predicate { $0.status == status })
        guard let actives = try? modelContext.fetch(descriptor) else { return }
        for flight in actives {
            flight.status = "ended"
            flight.lastSeen = now
        }
        try? modelContext.save()
    }

    // MARK: - 统计查询（供后续 UI / 设置页使用）

    func countAircraft() -> Int { (try? modelContext.fetchCount(FetchDescriptor<Aircraft>())) ?? 0 }
    func countStateSamples() -> Int { (try? modelContext.fetchCount(FetchDescriptor<AircraftStateSample>())) ?? 0 }
    func countFlights() -> Int { (try? modelContext.fetchCount(FetchDescriptor<Flight>())) ?? 0 }

    // MARK: - 私有辅助

    private func cachedAircraft(icaoHex: String) -> Aircraft {
        if let cached = aircraftByHex[icaoHex] { return cached }
        if let existing = fetchAircraft(icaoHex: icaoHex) {
            aircraftByHex[icaoHex] = existing
            return existing
        }
        let created = Aircraft(icaoHex: icaoHex)
        modelContext.insert(created)
        aircraftByHex[icaoHex] = created
        // 防止缓存无界增长；超限时清空字典（对象仍在 context，下次走查询）。
        if aircraftByHex.count > 4096 {
            aircraftByHex.removeAll(keepingCapacity: false)
        }
        return created
    }

    private func fetchAircraft(icaoHex: String) -> Aircraft? {
        let hex = icaoHex
        var descriptor = FetchDescriptor<Aircraft>(predicate: #Predicate { $0.icaoHex == hex })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchFlight(id: UUID) -> Flight? {
        let target = id
        var descriptor = FetchDescriptor<Flight>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchFlightRoute(callsignICAO: String) -> FlightRoute? {
        let key = callsignICAO
        var descriptor = FetchDescriptor<FlightRoute>(predicate: #Predicate { $0.callsignICAO == key })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchAirport(icaoCode: String) -> Airport? {
        let code = icaoCode
        var descriptor = FetchDescriptor<Airport>(predicate: #Predicate { $0.icaoCode == code })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchAirline(icaoCode: String) -> Airline? {
        let code = icaoCode
        var descriptor = FetchDescriptor<Airline>(predicate: #Predicate { $0.icaoCode == code })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func fetchAPICache(requestKey: String) -> APICache? {
        let key = requestKey
        var descriptor = FetchDescriptor<APICache>(predicate: #Predicate { $0.requestKey == key })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func upsertAirport(info: AirportInfo) {
        guard let icao = info.icaoCode, let name = info.name else { return }
        let airport: Airport
        if let existing = fetchAirport(icaoCode: icao) {
            airport = existing
        } else {
            airport = Airport(icaoCode: icao, name: name)
            modelContext.insert(airport)
        }
        airport.name = name
        airport.iataCode = info.iataCode
        airport.municipality = info.municipality
        airport.country = info.country
        airport.countryISO = info.countryISO
        airport.latitude = info.latitude
        airport.longitude = info.longitude
        airport.elevation = info.elevation
    }

    private func upsertAirline(icao: String, info: AirlineInfo, name: String) {
        let airline: Airline
        if let existing = fetchAirline(icaoCode: icao) {
            airline = existing
        } else {
            airline = Airline(icaoCode: icao, name: name)
            modelContext.insert(airline)
        }
        airline.name = name
        airline.iataCode = info.iataCode
        airline.country = info.country
        airline.callsign = info.callsign
    }

    private func upsertAPICache(requestKey: String, provider: String, requestURL: String,
                                responseJSON: String, fetchedAt: Date, httpStatusCode: Int, error: String?) {
        let cache: APICache
        if let existing = fetchAPICache(requestKey: requestKey) {
            cache = existing
        } else {
            cache = APICache(requestKey: requestKey, provider: provider, requestURL: requestURL,
                             responseJSON: responseJSON, fetchedAt: fetchedAt,
                             expiresAt: fetchedAt.addingTimeInterval(permanentTTL),
                             httpStatusCode: httpStatusCode)
            modelContext.insert(cache)
        }
        cache.provider = provider
        cache.requestURL = requestURL
        cache.responseJSON = responseJSON
        cache.fetchedAt = fetchedAt
        cache.expiresAt = fetchedAt.addingTimeInterval(permanentTTL)
        cache.httpStatusCode = httpStatusCode
        cache.errorMessage = error
    }

    private func airportInfo(for icaoCode: String?) -> AirportInfo? {
        guard let icaoCode, let airport = fetchAirport(icaoCode: icaoCode) else { return nil }
        return AirportInfo(
            icaoCode: airport.icaoCode,
            iataCode: airport.iataCode,
            name: airport.name,
            municipality: airport.municipality,
            country: airport.country,
            countryISO: airport.countryISO,
            latitude: airport.latitude,
            longitude: airport.longitude,
            elevation: airport.elevation
        )
    }

    private func airlineInfo(for icaoCode: String?) -> AirlineInfo? {
        guard let icaoCode, let airline = fetchAirline(icaoCode: icaoCode) else { return nil }
        return AirlineInfo(
            icaoCode: airline.icaoCode,
            iataCode: airline.iataCode,
            name: airline.name,
            country: airline.country,
            callsign: airline.callsign
        )
    }
}
