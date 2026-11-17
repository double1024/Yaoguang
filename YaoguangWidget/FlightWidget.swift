import WidgetKit
import SwiftUI

struct FlightEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetFlightSnapshot?
}

struct FlightTimelineProvider: TimelineProvider {
    private let refreshInterval: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> FlightEntry {
        FlightEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (FlightEntry) -> Void) {
        // 画布预览用样例；桌面用真实快照，没有则回退样例。
        let loaded = WidgetSharedStorage.load()
        if let demo = Self.demoFlightEntry(at: Date()) {
            completion(demo)
            return
        }
        let snapshot = context.isPreview ? .sample : (loaded ?? .sample)
        completion(FlightEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlightEntry>) -> Void) {
        let now = Date()

        // 演示模式：固定显示香港快运 UO1800 公益航班。
        if let demo = Self.demoFlightEntry(at: now) {
            completion(Timeline(entries: [demo], policy: .after(now.addingTimeInterval(refreshInterval))))
            return
        }

        let entry = FlightEntry(date: now, snapshot: WidgetSharedStorage.load())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refreshInterval))))
    }

    /// 演示航班：香港快运航空 UO1800，香港环飞。
    static func demoFlightEntry(at date: Date) -> FlightEntry? {
        guard WidgetSharedStorage.load()?.demoMode == true else { return nil }
        let snapshot = WidgetFlightSnapshot(
            writtenAt: date,
            origin: "HKG",
            destination: "HKG",
            airlineName: "HK Express",
            flightNumber: "UO1800",
            aircraftType: "A320neo",
            manufacturer: "Airbus",
            demoMode: true,
            airlineLogoData: demoLogoData()
        )
        return FlightEntry(date: date, snapshot: snapshot)
    }

    /// 读取扩展自带的 HK Express logo。
    static func demoLogoData() -> Data? {
        guard let url = Bundle.main.url(forResource: "HKE", withExtension: "png") else { return nil }
        return try? Data(contentsOf: url)
    }
}

extension WidgetFlightSnapshot {
    /// 无数据时的中性占位（不再回退默认航班）。
    static var sample: WidgetFlightSnapshot {
        WidgetFlightSnapshot(
            writtenAt: Date(),
            origin: "-",
            destination: "-",
            airlineName: nil,
            flightNumber: nil,
            aircraftType: nil,
            airlineLogoData: nil
        )
    }
}

struct FlightWidget: Widget {
    static let kind = "FlightWidget"

    init() {
        ContentView.registerFonts()
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: FlightTimelineProvider()) { entry in
            ContentView(flight: (entry.snapshot ?? .sample).cardData)
                .containerBackground(for: .widget) {
                    // 透明，让桌面通过卡片 40% 白色底显现。
                    Color.clear
                }
        }
        .configurationDisplayName("Flight")
        .description("显示最近收到的一架飞机的航线信息。")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct FlightWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlightWidget()
    }
}
