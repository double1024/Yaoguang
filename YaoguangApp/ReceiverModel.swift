import Foundation
import Combine

struct Aircraft: Identifiable {
    let icao24: UInt32
    var callsign: String?
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

    var id: UInt32 { icao24 }
}

@MainActor
final class ReceiverModel: ObservableObject {
    private let maxTrackedAircraft = 10

    @Published private(set) var aircraft: [Aircraft] = []
    @Published private(set) var status = "Receiver not started"
    @Published private(set) var validPacketCount: UInt64 = 0

    private var handle: OpaquePointer?
    private var pollTimer: Timer?
    private var aircraftByICAO: [UInt32: Aircraft] = [:]

    func start() {
        guard handle == nil else { return }
        validPacketCount = 0
        aircraftByICAO.removeAll()
        aircraft = []
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
        if aircraftByICAO[icao] == nil, aircraftByICAO.count >= maxTrackedAircraft,
           let oldestICAO = aircraftByICAO.values.min(by: { $0.lastSeen < $1.lastSeen })?.icao24 {
            aircraftByICAO.removeValue(forKey: oldestICAO)
        }
        var aircraft = aircraftByICAO[icao] ?? Aircraft(icao24: icao)
        let fields = update.fields
        aircraft.packetCount &+= 1

        if fields & UInt32(YAOGUANG_FIELD_CALLSIGN) != 0, !callsign.isEmpty {
            aircraft.callsign = callsign
        }
        if fields & UInt32(YAOGUANG_FIELD_SPEED) != 0 {
            aircraft.speedKt = update.speed_kt
            aircraft.speedKind = update.speed_kind
        }
        if fields & UInt32(YAOGUANG_FIELD_DIRECTION) != 0 {
            aircraft.directionDeg = update.direction_deg
            aircraft.directionKind = update.direction_kind
        }
        if fields & UInt32(YAOGUANG_FIELD_ALTITUDE) != 0 {
            aircraft.altitudeFt = update.altitude_ft
            aircraft.altitudeKind = update.altitude_kind
        }
        if fields & UInt32(YAOGUANG_FIELD_VERTICAL_RATE) != 0 {
            aircraft.verticalRateFpm = update.vertical_rate_fpm
        }
        if fields & UInt32(YAOGUANG_FIELD_SIGNAL) != 0 {
            aircraft.signalDbfs = Double(update.signal_dbfs)
        }
        aircraft.lastSeen = receivedAt
        aircraftByICAO[icao] = aircraft
        publishAircraftInRecentOrder()
    }

    private func publishAircraftInRecentOrder() {
        aircraft = aircraftByICAO.values.sorted {
            if $0.lastSeen != $1.lastSeen { return $0.lastSeen > $1.lastSeen }
            return $0.icao24 < $1.icao24
        }
    }

}
