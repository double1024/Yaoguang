import SwiftUI
import AppKit
import CoreText

/// 329 × 155 登机牌风格飞行卡片。
///
/// - 玻璃卡片背景（macOS 26+ glassEffect，自动适配深/浅色）
/// - 中央 barcode 装饰条 + 航线大字
/// - 顶部航司 logo + 名称，底部航班号 + 机型（居中）
struct ContentView: View {
    let flight: FlightCardData
    @Environment(\.colorScheme) private var colorScheme

    private static let displayFont = "Staatliches"
    private static let detailFont = "Anta"

    var body: some View {
        ZStack {
            // 1. 玻璃卡片背景：只用 glassEffect + 一层很淡的色调，
            //    避免再叠加 regularMaterial 导致过白、过硬。
            RoundedRectangle(cornerRadius: 21.67, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.black.opacity(0.28)
                      : Color.white.opacity(0.16))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 21.67, style: .continuous))

            // 2. barcode 装饰条（登机牌风格，居中）
            barcodeBand

            // 3. 内容
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                route
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: 329, height: 155)
        .clipShape(RoundedRectangle(cornerRadius: 21.67, style: .continuous))
    }

    // MARK: - barcode 条

    /// 原始 barcode_bg.png 的 alpha 只有 13（约 5%），几乎不可见，
    /// 因此使用提亮版 barcode_bg_visible.png，并用 opacity 控制最终强度。
    @ViewBuilder
    private var barcodeBand: some View {
        if let image = Self.bundleImage(named: "barcode_bg_visible") {
            Image(nsImage: image)
                .resizable()
                .frame(width: 329, height: 64)
                .frame(maxHeight: .infinity, alignment: .center)
                .opacity(colorScheme == .dark ? 0.22 : 0.28)
                .blendMode(colorScheme == .dark ? .screen : .multiply)
                .allowsHitTesting(false)
        }
    }

    private static func bundleImage(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(named: name)
    }

    // MARK: - 三个区块

    private var header: some View {
        HStack(spacing: 10) {
            logo
            if let name = flight.airlineName {
                Text(name)
                    .font(.custom(Self.displayFont, size: 18))
                    .foregroundColor(airlineNameColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }

    private var route: some View {
        HStack(spacing: 0) {
            Text(flight.origin)
                .font(.custom(Self.displayFont, size: 56))
            Text(" --> ")
                .font(.custom(Self.displayFont, size: 38))
            Text(flight.destination)
                .font(.custom(Self.displayFont, size: 56))
        }
        .foregroundColor(routeColor)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }

    /// 航班号 + 机型，整行居中。
    private var footer: some View {
        HStack(spacing: 42) {
            if let flightNumber = flight.flightNumberText {
                Text(flightNumber)
                    .font(.custom(Self.detailFont, size: 12))
                    .foregroundColor(detailColor)
                    .lineLimit(1)
            }
            if let aircraft = flight.aircraftText {
                Text(aircraft)
                    .font(.custom(Self.detailFont, size: 12))
                    .foregroundColor(detailColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - 航司 logo

    @ViewBuilder
    private var logo: some View {
        if let data = flight.airlineLogoData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: "airplane")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }

    // MARK: - 自适应颜色

    private var routeColor: Color {
        colorScheme == .dark
            ? Color(red: 0.46, green: 0.84, blue: 0.58)
            : Color(red: 0.08, green: 0.50, blue: 0.24)
    }

    private var detailColor: Color {
        colorScheme == .dark
            ? Color(red: 0.86, green: 0.74, blue: 0.36)
            : Color(red: 0.60, green: 0.48, blue: 0.17)
    }

    private var airlineNameColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.75)
            : Color(red: 0.45, green: 0.45, blue: 0.45)
    }

    // MARK: - 字体注册

    /// 小组件扩展进程需要显式注册字体；失败时回退系统字体。
    static func registerFonts() {
        for name in ["Staatliches-Regular", "Anta-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// 卡片展示所需的字段。缺失数据不显示占位符。
struct FlightCardData: Equatable {
    var origin: String = "-"
    var destination: String = "-"
    var airlineName: String?
    var flightNumberText: String?
    var aircraftText: String?
    var airlineLogoData: Data?
}
