import Foundation
import Combine
import WidgetKit

/// 实时接收界面的内存状态（区别于 SwiftData 的 `Aircraft` 档案模型）。
struct LiveAircraft: Identifiable {
    let icao24: UInt32
    var callsign: String?

    // 原始字段（沿用既有 UI 展示与类型区分）
    var speedKt: Double?
    var speedKind: UInt8 = 0
    var directionDeg: Double?
    var directionKind: UInt8 = 0
    var altitudeFt: Int32?
    var altitudeKind: UInt8 = 0
    var verticalRateFpm: Int16?
    var signalDbfs: Double?
    var packetCount: UInt64 = 0
    var lastSeen = Date()

    // 解析后的字段（只保留用于历史存储的语义：地速/航迹/气压高度）
    var groundSpeedKt: Double?
    var trackDeg: Double?
    var baroAltitudeFt: Int32?

    var id: UInt32 { icao24 }
}

@MainActor
final class ReceiverModel: ObservableObject {
    private let maxTrackedAircraft = 10
    private let store: HistoryStore
    private let resolver: FlightInfoResolver

    @Published private(set) var aircraft: [LiveAircraft] = []
    @Published private(set) var status = "Receiver not started"
    @Published private(set) var validPacketCount: UInt64 = 0
    /// 小组件快照的写入状态，便于排查「小组件不更新」。
    @Published private(set) var widgetStatus = "widget: —"

    private var handle: OpaquePointer?
    private var pollTimer: Timer?
    private var aircraftByICAO: [UInt32: LiveAircraft] = [:]
    private var pollTick: UInt64 = 0

    // 采样与航班生命周期状态（内存）
    private var lastSample: [UInt32: (at: Date, fingerprint: String)] = [:]
    private var activeFlight: [UInt32: (callsign: String, id: UUID)] = [:]
    private let sampleInterval: TimeInterval = 1.0
    private let flightGapInterval: TimeInterval = 10 * 60

    init(store: HistoryStore, resolver: FlightInfoResolver) {
        self.store = store
        self.resolver = resolver
    }

    func start() {
        guard handle == nil else { return }
        validPacketCount = 0
        aircraftByICAO.removeAll()
        aircraft = []
        lastSample.removeAll()
        activeFlight.removeAll()
        guard let newHandle = yaoguang_start() else {
            status = "Unable to create receiver thread"
            return
        }
        handle = newHandle
        status = "Initializing RTL-SDR…"
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let handle {
            yaoguang_stop(handle)
            self.handle = nil
        }
        status = "Receiver stopped"
        let now = Date()
        for icao in activeFlight.keys {
            closeActiveFlight(icao: icao, at: now)
        }
        Task { await store.flush() }
    }

    func reconnect() {
        stop()
        start()
    }

    private func poll() {
        guard let handle else { return }
        var update = YaoguangUpdate()
        var callsignBuffer = [CChar](repeating: 0, count: 9)
        let result = callsignBuffer.withUnsafeMutableBufferPointer { buffer in
            yaoguang_poll_update(handle, &update, buffer.baseAddress, buffer.count)
        }

        if result == 2 {
            status = "RTL-SDR ready — waiting for ADS-B"
        } else if result == 1 {
            let receivedAt = Date()
            validPacketCount &+= 1
            merge(update, callsign: decodeCString(callsignBuffer), receivedAt: receivedAt)
            status = "Receiving ADS-B"
        } else if result == -2 {
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let length = errorBuffer.withUnsafeMutableBufferPointer { buffer in
                yaoguang_last_error(handle, buffer.baseAddress, buffer.count)
            }
            if length > 0 {
                status = decodeCString(errorBuffer)
            } else {
                status = "Receiver stopped or an error occurred"
            }
        }
    }

    private func decodeCString(_ buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func merge(_ update: YaoguangUpdate, callsign: String, receivedAt: Date) {
        let icao = update.icao24
        let isNew = aircraftByICAO[icao] == nil

        // 淘汰最久未更新的飞机（顺带关闭其航班）
        if isNew, aircraftByICAO.count >= maxTrackedAircraft,
           let oldestICAO = aircraftByICAO.values.min(by: { $0.lastSeen < $1.lastSeen })?.icao24 {
            aircraftByICAO.removeValue(forKey: oldestICAO)
            closeActiveFlight(icao: oldestICAO, at: receivedAt)
            lastSample.removeValue(forKey: oldestICAO)
        }

        var aircraft = aircraftByICAO[icao] ?? LiveAircraft(icao24: icao)
        let fields = update.fields
        aircraft.packetCount &+= 1

        if fields & UInt32(YAOGUANG_FIELD_CALLSIGN) != 0, !callsign.isEmpty {
            aircraft.callsign = callsign
        }
        if fields & UInt32(YAOGUANG_FIELD_SPEED) != 0 {
            aircraft.speedKt = update.speed_kt
            aircraft.speedKind = update.speed_kind
            if update.speed_kind == UInt8(YAOGUANG_SPEED_GROUND) {
                aircraft.groundSpeedKt = update.speed_kt
            }
        }
        if fields & UInt32(YAOGUANG_FIELD_DIRECTION) != 0 {
            aircraft.directionDeg = update.direction_deg
            aircraft.directionKind = update.direction_kind
            if update.direction_kind == UInt8(YAOGUANG_DIRECTION_TRACK) {
                aircraft.trackDeg = update.direction_deg
            }
        }
        if fields & UInt32(YAOGUANG_FIELD_ALTITUDE) != 0 {
            aircraft.altitudeFt = update.altitude_ft
            aircraft.altitudeKind = update.altitude_kind
            if update.altitude_kind == UInt8(YAOGUANG_ALTITUDE_BAROMETRIC) {
                aircraft.baroAltitudeFt = update.altitude_ft
            }
        }
        if fields & UInt32(YAOGUANG_FIELD_VERTICAL_RATE) != 0 {
            aircraft.verticalRateFpm = update.vertical_rate_fpm
        }
        if fields & UInt32(YAOGUANG_FIELD_SIGNAL) != 0 {
            aircraft.signalDbfs = Double(update.signal_dbfs)
        }
        aircraft.lastSeen = receivedAt
        aircraftByICAO[icao] = aircraft

        // 首见：触发飞机档案查询
        if isNew {
            let hex = Self.hexString(icao)
            Task { await resolver.resolveAircraft(icaoHex: hex) }
        }

        // 呼号处理：航班识别 + 航线查询
        if fields & UInt32(YAOGUANG_FIELD_CALLSIGN) != 0, !callsign.isEmpty {
            handleCallsign(callsign, icao: icao, at: receivedAt)
        }

        // 每包收包统计
        let hex = Self.hexString(icao)
        Task { await store.recordPacket(icaoHex: hex, timestamp: receivedAt) }

        // 采样
        maybeSample(aircraft, receivedAt: receivedAt)

        // 周期任务：每秒 flush；每 60 秒扫一次失联航班
        pollTick &+= 1
        if pollTick % 10 == 0 {
            Task { await store.flush() }
        }
        if pollTick % 600 == 0 {
            sweepStaleFlights(now: receivedAt)
        }

        publishAircraftInRecentOrder()
        publishWidgetSnapshot()
    }

    private func handleCallsign(_ rawCallsign: String, icao: UInt32, at: Date) {
        let callsign = rawCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !callsign.isEmpty else { return }

        if let existing = activeFlight[icao], existing.callsign == callsign {
            return // 同一航班继续
        }

        if let existing = activeFlight[icao] {
            Task { await store.closeFlight(id: existing.id, at: at) }
        }

        let flightID = UUID()
        activeFlight[icao] = (callsign: callsign, id: flightID)
        let hex = Self.hexString(icao)
        Task { await store.openFlight(FlightRecord(icaoHex: hex, callsign: callsign, firstSeen: at, lastSeen: at), id: flightID) }
        Task { await resolver.resolveRoute(callsign: callsign, flightID: flightID) }
    }

    private func maybeSample(_ aircraft: LiveAircraft, receivedAt: Date) {
        let icao = aircraft.icao24
        let fingerprint = Self.fingerprint(aircraft)

        if let last = lastSample[icao] {
            if receivedAt.timeIntervalSince(last.at) < sampleInterval { return }
            if last.fingerprint == fingerprint { return }
        }

        lastSample[icao] = (at: receivedAt, fingerprint: fingerprint)
        let snapshot = SampleSnapshot(
            icaoHex: Self.hexString(icao),
            timestamp: receivedAt,
            altitudeFt: aircraft.baroAltitudeFt,
            groundSpeedKt: aircraft.groundSpeedKt,
            trackDeg: aircraft.trackDeg,
            verticalRateFpm: aircraft.verticalRateFpm,
            callsign: aircraft.callsign,
            signalDbfs: aircraft.signalDbfs,
            flightID: activeFlight[icao]?.id
        )
        Task { await store.appendSample(snapshot) }
    }

    private func sweepStaleFlights(now: Date) {
        for (icao, aircraft) in aircraftByICAO where now.timeIntervalSince(aircraft.lastSeen) > flightGapInterval {
            closeActiveFlight(icao: icao, at: aircraft.lastSeen)
        }
    }

    private func closeActiveFlight(icao: UInt32, at: Date) {
        guard let flight = activeFlight.removeValue(forKey: icao) else { return }
        Task { await store.closeFlight(id: flight.id, at: at) }
    }

    private func publishAircraftInRecentOrder() {
        aircraft = aircraftByICAO.values.sorted {
            if $0.lastSeen != $1.lastSeen { return $0.lastSeen > $1.lastSeen }
            return $0.icao24 < $1.icao24
        }
    }

    // MARK: - 小组件快照

    private var lastWidgetKey: String = ""
    private var lastWidgetWrite = Date.distantPast

    /// 把最近一架飞机的展示信息写入 App Group，供小组件读取。
    /// 变更才写，且最多每 5 秒一次，避免高频磁盘写入。
    private func publishWidgetSnapshot() {
        guard let latest = aircraft.first else {
            widgetStatus = "widget: 无飞机"
            return
        }
        guard let callsign = latest.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !callsign.isEmpty else {
            widgetStatus = "widget: 无呼号"
            return
        }

        let route = resolver.routes[callsign]
        let info = resolver.aircraftInfo[Self.hexString(latest.icao24)]

        let origin = route?.origin?.iataCode ?? route?.origin?.icaoCode
        let destination = route?.destination?.iataCode ?? route?.destination?.icaoCode
        let airline = route?.airline?.name
        let flightNumber = callsign
        let aircraftType = info?.aircraftType ?? info?.icaoType

        // 只要拿到呼号，并且航线或机型任一项已解析，就更新小组件；
        // 缺失的航线用 "-" 占位，避免一直卡在等待航线。
        guard origin != nil || destination != nil || aircraftType != nil else {
            widgetStatus = "widget: 等待航线/机型（\(callsign)）"
            return
        }

        let designator = route?.airline?.icaoCode ?? Self.airlineDesignator(callsign)
        let logoData = Self.airlineLogoData(designator: designator)

        let key = [origin, destination, airline, flightNumber, aircraftType, logoData?.base64EncodedString() ?? ""]
            .map { $0 ?? "" }.joined(separator: "|")
        guard key != lastWidgetKey || Date().timeIntervalSince(lastWidgetWrite) >= 5 else { return }
        lastWidgetKey = key
        lastWidgetWrite = Date()

        WidgetSharedStorage.save(WidgetFlightSnapshot(
            writtenAt: Date(),
            origin: origin ?? "-",
            destination: destination ?? "-",
            airlineName: airline,
            flightNumber: flightNumber,
            aircraftType: aircraftType,
            airlineLogoData: logoData
        ))
        WidgetCenter.shared.reloadTimelines(ofKind: "FlightWidget")
        widgetStatus = "widget: 已更新 \(callsign)"
        print("[widget] snapshot written: \(callsign) \(origin ?? "-")->\(destination ?? "-") type=\(aircraftType ?? "-")")
    }

    /// 从呼号取三字 ICAO 航司码（如 "HKE1800" → "HKE"）。
    private static func airlineDesignator(_ callsign: String) -> String? {
        guard callsign.count >= 3 else { return nil }
        return String(callsign.prefix(3))
    }

    /// 从 flightaware_logos 读取航司 logo 的 PNG 数据。
    private static func airlineLogoData(designator: String?) -> Data? {
        guard let designator else { return nil }
        let code = String(designator.prefix(3)).uppercased()
        guard let url = Bundle.main.url(forResource: code, withExtension: "png", subdirectory: "flightaware_logos") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }


    private static func hexString(_ icao24: UInt32) -> String {
        String(format: "%06X", icao24)
    }

    private static func fingerprint(_ aircraft: LiveAircraft) -> String {
        "\(aircraft.baroAltitudeFt.map(String.init) ?? "-")|" +
        "\(aircraft.groundSpeedKt.map { String(format: "%.0f", $0) } ?? "-")|" +
        "\(aircraft.trackDeg.map { String(format: "%.0f", $0) } ?? "-")|" +
        "\(aircraft.verticalRateFpm.map(String.init) ?? "-")"
    }
}
