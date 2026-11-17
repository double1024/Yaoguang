import SwiftUI
import CoreText

/// 329 × 155 飞行卡片。
///
/// 布局、偏移、配色与字号与设计稿一致；色块按设计意图叠在航线文字之上，形成半透明压色效果。
/// 仅次要点做了可用性处理：尺寸随容器自适应、字体运行时注册、缺失数据时不显示占位文字。
struct ContentView: View {
    let flight: FlightCardData

    private static let accent = Color(red: 0.50, green: 0.23, blue: 0.27).opacity(0.50)
    private static let routeGreen = Color(red: 0.08, green: 0.50, blue: 0.24)
    private static let airlineGray = Color(red: 0.45, green: 0.45, blue: 0.45)
    private static let detailGold = Color(red: 0.60, green: 0.48, blue: 0.17)

    var body: some View {
        // 以 329 × 155 为设计基准，按实际可用尺寸等比缩放。
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 329, proxy.size.height / 155)
            card
                .frame(width: 329, height: 155)
                .scaleEffect(scale, anchor: .center)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 21.67, style: .continuous))
    }

    private var card: some View {
        ZStack {
            // 1. 白色卡面
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 329, height: 155)
                .background(.white)
                .cornerRadius(21.67)
                .offset(x: 0, y: 0)

            // 2. 航司 logo 占位 + 航司名
            HStack(spacing: 15) {
                airlineMark
                if let airline = flight.airlineName {
                    Text(airline)
                        .font(.custom(Self.displayFont, size: 20))
                        .foregroundColor(Self.airlineGray)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 277)
            .offset(x: -6, y: -47.50)

            // 3. 底部两行：航班号 / 机型
            HStack(spacing: 42) {
                if let flightNumber = flight.flightNumberText {
                    Text(flightNumber)
                        .font(.custom(Self.detailFont, size: 12))
                        .foregroundColor(Self.detailGold)
                        .lineLimit(1)
                }
                if let aircraft = flight.aircraftText {
                    Text(aircraft)
                        .font(.custom(Self.detailFont, size: 12))
                        .foregroundColor(Self.detailGold)
                        .lineLimit(1)
                }
            }
            .offset(x: 2.50, y: 51)

            // 4. 航线：两端 64pt，箭头 48pt
            HStack(spacing: 0) {
                Text(flight.origin)
                    .font(.custom(Self.displayFont, size: 64))
                Text("-->")
                    .font(.custom(Self.displayFont, size: 48))
                Text(flight.destination)
                    .font(.custom(Self.displayFont, size: 64))
            }
            .foregroundColor(Self.routeGreen)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .offset(x: 0, y: 6)

            // 5. 半透明色块：叠在航线文字之上（设计意图）
            Rectangle()
                .foregroundColor(.clear)
                .frame(width: 329, height: 64)
                .background(Self.accent)
                .offset(x: 0, y: 2.50)
        }
        .frame(width: 329, height: 155)
        .background(Color(red: 1, green: 1, blue: 1).opacity(0.40))
    }

    private var airlineMark: some View {
        Rectangle()
            .foregroundColor(.clear)
            .frame(width: 30, height: 30)
            .background(Self.accent)
    }

    // MARK: - 字体

    static let displayFont = "Staatliches"
    static let detailFont = "Anta"

    /// 小组件扩展进程需要显式注册字体；失败时回退系统字体，避免文字消失。
    static func registerFonts() {
        for name in ["Staatliches-Regular", "Anta-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// 卡片展示所需的字段。缺失数据不显示占位符，避免出现 "Unknown"。
struct FlightCardData: Equatable {
    var origin: String = "---"
    var destination: String = "---"
    var airlineName: String?
    var flightNumberText: String?
    var aircraftText: String?
}
