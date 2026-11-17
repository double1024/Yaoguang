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
        let snapshot = context.isPreview ? .sample : (WidgetSharedStorage.load() ?? .sample)
        completion(FlightEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FlightEntry>) -> Void) {
        let now = Date()
        let entry = FlightEntry(date: now, snapshot: WidgetSharedStorage.load())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refreshInterval))))
    }
}

extension WidgetFlightSnapshot {
    /// 设计稿中的样例数据。
    static var sample: WidgetFlightSnapshot {
        WidgetFlightSnapshot(
            writtenAt: Date(),
            origin: "YVR",
            destination: "PEK",
            airlineName: "Air Canada",
            flightNumber: "AC029",
            aircraftType: "Boeing 787-9"
        )
    }
}

struct FlightWidget: Widget {
    static let kind = "FlightWidget"

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
