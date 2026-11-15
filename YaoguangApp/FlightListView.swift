import SwiftUI
import AppKit

struct FlightListView: View {
    @ObservedObject var receiver: ReceiverModel

    var body: some View {
        VStack(spacing: 0) {
            if receiver.aircraft.isEmpty {
                ContentUnavailableView(
                    "No Aircraft Received Yet",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Connect the RTL-SDR and wait for ADS-B broadcasts.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(receiver.aircraft) {
                    TableColumn(columnTitle("Flight")) { aircraft in
                        flightCell(aircraft)
                    }
                    .width(min: 115, ideal: 125, max: 140)
                    .alignment(.leading)

                    TableColumn(columnTitle("ICAO")) { aircraft in
                        Text(String(format: "%06X", aircraft.icao24))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 65, ideal: 72, max: 80)
                    .alignment(.leading)

                    TableColumn(columnTitle("GS", unit: "(kt)")) { aircraft in
                        numberCell(groundSpeed(aircraft))
                    }
                    .width(min: 68, ideal: 75, max: 85)
                    .alignment(.trailing)

                    TableColumn(columnTitle("TRK")) { aircraft in
                        numberCell(track(aircraft))
                    }
                    .width(min: 55, ideal: 62, max: 70)
                    .alignment(.trailing)

                    TableColumn(columnTitle("ALT", unit: "(FL)")) { aircraft in
                        numberCell(flightLevel(aircraft))
                    }
                    .width(min: 75, ideal: 82, max: 90)
                    .alignment(.trailing)

                    TableColumn(columnTitle("V/S", unit: "(m/s)")) { aircraft in
                        numberCell(verticalRate(aircraft))
                    }
                    .width(min: 78, ideal: 85, max: 95)
                    .alignment(.trailing)

                    TableColumn(columnTitle("SIG", unit: "(dBFS)")) { aircraft in
                        numberCell(aircraft.signalDbfs.map { String(format: "%.1f", $0) })
                    }
                    .width(min: 82, ideal: 90, max: 100)
                    .alignment(.trailing)

                    TableColumn(columnTitle("RX", unit: "(Age)")) { aircraft in
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(aircraft.packetCount) (\(packetAge(aircraft, now: context.date)))")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .width(min: 92, ideal: 100, max: 115)
                    .alignment(.trailing)
                }
                .tableStyle(.inset)
            }

            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text(receiver.status)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .font(.system(size: 13, design: .default))
    }

    private func columnTitle(_ title: String, unit: String? = nil) -> Text {
        let main = Text(title).font(.system(size: 11, weight: .semibold))
        guard let unit else { return main }
        return main + Text(" \(unit)")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
    }

    private func flightCell(_ aircraft: Aircraft) -> some View {
        let callsign = aircraft.callsign?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUnknown = callsign == nil || callsign?.isEmpty == true

        return HStack(spacing: 6) {
            AirlineLogoView(callsign: isUnknown ? nil : callsign)
            Text(isUnknown ? "Unknown" : callsign!)
                .font(.system(size: 13, weight: .bold))
                .italic(isUnknown)
                .foregroundStyle(isUnknown ? Color.secondary : Color.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(isUnknown ? "Unknown" : callsign!)
    }

    private func numberCell(_ value: String?) -> some View {
        Text(value ?? "—")
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func flightLevel(_ aircraft: Aircraft) -> String? {
        guard let altitude = aircraft.altitudeFt else { return nil }
        return String(format: "FL%03d", Int((Double(altitude) / 100.0).rounded()))
    }

    private func groundSpeed(_ aircraft: Aircraft) -> String? {
        guard aircraft.speedKind == UInt8(YAOGUANG_SPEED_GROUND) else { return nil }
        return aircraft.speedKt.map { String(format: "%.0f", $0) }
    }

    private func track(_ aircraft: Aircraft) -> String? {
        guard aircraft.directionKind == UInt8(YAOGUANG_DIRECTION_TRACK) else { return nil }
        return aircraft.directionDeg.map { String(format: "%.0f°", $0) }
    }

    private func verticalRate(_ aircraft: Aircraft) -> String? {
        guard let rate = aircraft.verticalRateFpm else { return nil }
        return String(format: "%+.1f", Double(rate) * 0.00508)
    }

    private func packetAge(_ aircraft: Aircraft, now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(aircraft.lastSeen)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

private struct AirlineLogoView: View {
    let callsign: String?

    @State private var logo: NSImage?

    var body: some View {
        Group {
            if let logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "airplane")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
        .task(id: callsign) {
            logo = Self.loadLogo(for: callsign)
        }
    }

    private static func loadLogo(for callsign: String?) -> NSImage? {
        guard let callsign else { return nil }
        let normalized = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // Airline flight callsigns use a three-letter ICAO designator followed by a flight number.
        guard normalized.count >= 4 else { return nil }
        let designator = String(normalized.prefix(3))
        let suffix = normalized.dropFirst(3)
        guard designator.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil,
              suffix.first?.isNumber == true else { return nil }

        guard let url = Bundle.main.url(
            forResource: designator,
            withExtension: "png",
            subdirectory: "flightaware_logos"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }
}
