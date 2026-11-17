import SwiftUI
import AppKit

struct FlightListView: View {
    @ObservedObject var receiver: ReceiverModel
    @ObservedObject var resolver: FlightInfoResolver

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
                    TableColumn(columnTitle("Callsign")) { aircraft in
                        callsignCell(aircraft)
                    }
                    .width(min: 90, ideal: 112, max: 132)
                    .alignment(.leading)

                    TableColumn(columnTitle("Route")) { aircraft in
                        routeCell(aircraft)
                    }
                    .width(min: 110, ideal: 140, max: 170)
                    .alignment(.leading)

                    TableColumn(columnTitle("ICAO")) { aircraft in
                        Text(String(format: "%06X", aircraft.icao24))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 58, ideal: 64, max: 72)
                    .alignment(.leading)

                    TableColumn(columnTitle("GS", unit: "(kt)")) { aircraft in
                        numberCell(aircraft.groundSpeedKt.map { String(format: "%.0f", $0) })
                    }
                    .width(min: 58, ideal: 66, max: 74)
                    .alignment(.trailing)

                    TableColumn(columnTitle("TRK")) { aircraft in
                        numberCell(aircraft.trackDeg.map { String(format: "%.0f°", $0) })
                    }
                    .width(min: 46, ideal: 52, max: 60)
                    .alignment(.trailing)

                    TableColumn(columnTitle("ALT", unit: "(FL)")) { aircraft in
                        numberCell(flightLevel(aircraft))
                    }
                    .width(min: 60, ideal: 68, max: 76)
                    .alignment(.trailing)

                    TableColumn(columnTitle("V/S", unit: "(m/s)")) { aircraft in
                        numberCell(verticalRate(aircraft))
                    }
                    .width(min: 62, ideal: 70, max: 78)
                    .alignment(.trailing)

                    TableColumn(columnTitle("SIG", unit: "(dBFS)")) { aircraft in
                        numberCell(aircraft.signalDbfs.map { String(format: "%.1f", $0) })
                    }
                    .width(min: 64, ideal: 72, max: 80)
                    .alignment(.trailing)

                    TableColumn(columnTitle("RX", unit: "(Age)")) { aircraft in
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("\(aircraft.packetCount) (\(packetAge(aircraft, now: context.date)))")
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .width(min: 80, ideal: 88, max: 98)
                    .alignment(.trailing)
                }
                .tableStyle(.inset)
            }

            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text(receiver.status)
                Spacer(minLength: 12)
                apiActivityView
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .font(.system(size: 13, design: .default))
    }

    // MARK: - 数据访问

    private func routeInfo(for aircraft: LiveAircraft) -> RouteInfo? {
        guard let callsign = aircraft.callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !callsign.isEmpty else { return nil }
        return resolver.routes[callsign]
    }

    // MARK: - 单元格

    private func columnTitle(_ title: String, unit: String? = nil) -> Text {
        let main = Text(title).font(.system(size: 11, weight: .semibold))
        guard let unit else { return main }
        return main + Text(" \(unit)")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
    }

    private func callsignCell(_ aircraft: LiveAircraft) -> some View {
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

    @ViewBuilder
    private func routeCell(_ aircraft: LiveAircraft) -> some View {
        if let route = routeInfo(for: aircraft),
           let origin = route.origin?.iataCode, let destination = route.destination?.iataCode {
            Text("\(origin) → \(destination)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .help(routeFullNames(route))
        } else {
            Text("—")
                .foregroundStyle(.secondary)
        }
    }

    private func routeFullNames(_ route: RouteInfo) -> String {
        let origin = route.origin?.name ?? route.origin?.icaoCode ?? route.origin?.iataCode ?? "?"
        let destination = route.destination?.name ?? route.destination?.icaoCode ?? route.destination?.iataCode ?? "?"
        return "\(origin) → \(destination)"
    }

    private func numberCell(_ value: String?) -> some View {
        Text(value ?? "—")
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func flightLevel(_ aircraft: LiveAircraft) -> String? {
        let altitude = aircraft.baroAltitudeFt ?? aircraft.altitudeFt
        guard let altitude else { return nil }
        return String(format: "FL%03d", Int((Double(altitude) / 100.0).rounded()))
    }

    private func verticalRate(_ aircraft: LiveAircraft) -> String? {
        guard let rate = aircraft.verticalRateFpm else { return nil }
        return String(format: "%+.1f", Double(rate) * 0.00508)
    }

    private func packetAge(_ aircraft: LiveAircraft, now: Date) -> String {
        let totalSeconds = max(0, Int(now.timeIntervalSince(aircraft.lastSeen)))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    /// 右下角 API 活动提示：进行中 / 成功 / 失败。
    @ViewBuilder
    private var apiActivityView: some View {
        switch resolver.activity {
        case .idle:
            EmptyView()
        case .loading(let message):
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(message)
            }
            .lineLimit(1)
            .truncationMode(.middle)
        case .success(let message):
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                Text(message)
            }
            .lineLimit(1)
            .truncationMode(.middle)
        case .failure(let message):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle")
                Text(message)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.orange)
        }
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
