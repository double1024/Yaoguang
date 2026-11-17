import Foundation

/// ADSBdb 客户端：封装 URLSession 请求与 JSON 解析，返回结构化结果 + 原始 JSON。
struct ADSBDBClient: Sendable {
    private let baseURL = URL(string: "https://api.adsbdb.com/v0")!
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    struct RouteResult: Sendable {
        let info: RouteInfo
        let rawJSON: String
    }

    struct AircraftResult: Sendable {
        let info: AircraftInfo
        let rawJSON: String
    }

    func fetchRoute(callsign: String) async throws -> RouteResult {
        let url = baseURL.appendingPathComponent("callsign").appendingPathComponent(callsign)
        let data = try await get(url)
        let decoded = try JSONDecoder().decode(ADSBDBResponse<FlightRoutePayload>.self, from: data)
        let fr = decoded.response.flightroute
        let info = RouteInfo(
            callsignICAO: fr.callsign_icao ?? callsign.uppercased(),
            callsignIATA: fr.callsign_iata,
            airline: fr.airline.map { AirlineInfo(icaoCode: $0.icao, iataCode: $0.iata, name: $0.name, country: $0.country, callsign: $0.callsign) },
            origin: fr.origin.map(airportInfo),
            destination: fr.destination.map(airportInfo)
        )
        return RouteResult(info: info, rawJSON: String(data: data, encoding: .utf8) ?? "")
    }

    func fetchAircraft(icaoHex: String) async throws -> AircraftResult {
        let url = baseURL.appendingPathComponent("aircraft").appendingPathComponent(icaoHex)
        let data = try await get(url)
        let decoded = try JSONDecoder().decode(ADSBDBResponse<AircraftPayload>.self, from: data)
        let a = decoded.response.aircraft
        let info = AircraftInfo(
            registration: a.registration,
            manufacturer: a.manufacturer,
            aircraftType: a.type,
            icaoType: a.icao_type,
            operatorName: a.registered_owner,
            operatorICAO: a.registered_owner_operator_flag_code
        )
        return AircraftResult(info: info, rawJSON: String(data: data, encoding: .utf8) ?? "")
    }

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ADSBDBError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw ADSBDBError.httpStatus(http.statusCode)
        }
        return data
    }
}

enum ADSBDBError: Error, CustomStringConvertible {
    case invalidResponse
    case httpStatus(Int)

    var description: String {
        switch self {
        case .invalidResponse: return "invalid HTTP response"
        case .httpStatus(let code): return "HTTP \(code)"
        }
    }
}

// MARK: - 响应模型

private struct ADSBDBResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let response: T
}

private struct FlightRoutePayload: Decodable, Sendable {
    let flightroute: FlightRouteData
}

private struct FlightRouteData: Decodable, Sendable {
    let callsign: String?
    let callsign_icao: String?
    let callsign_iata: String?
    let airline: AirlineData?
    let origin: AirportData?
    let destination: AirportData?
}

private struct AirlineData: Decodable, Sendable {
    let name: String?
    let icao: String?
    let iata: String?
    let country: String?
    let callsign: String?
}

private struct AirportData: Decodable, Sendable {
    let country_iso_name: String?
    let country_name: String?
    let elevation: Double?
    let iata_code: String?
    let icao_code: String?
    let latitude: Double?
    let longitude: Double?
    let municipality: String?
    let name: String?
}

private struct AircraftPayload: Decodable, Sendable {
    let aircraft: AircraftData
}

private struct AircraftData: Decodable, Sendable {
    let type: String?
    let icao_type: String?
    let manufacturer: String?
    let mode_s: String?
    let registration: String?
    let registered_owner: String?
    let registered_owner_operator_flag_code: String?
}

private func airportInfo(_ data: AirportData) -> AirportInfo {
    AirportInfo(
        icaoCode: data.icao_code,
        iataCode: data.iata_code,
        name: data.name,
        municipality: data.municipality,
        country: data.country_name,
        countryISO: data.country_iso_name,
        latitude: data.latitude,
        longitude: data.longitude,
        elevation: data.elevation
    )
}
