import Foundation

/// 默认展示的航班资料：香港快运航空 UO1800 环飞航班。
///
/// 主应用与小组件共用同一份默认数据；收到真实 ADS-B 数据前，界面显示这里的记录。
enum DefaultFlightProfile {
    static let airlineName = "HK Express"
    static let airlineNameLocalized = "香港快运航空"
    static let airlineIATA = "UO"
    static let airlineICAO = "HKE"

    /// 展示用呼号（ICAO 呼号 + IATA 航班号）。
    static let flightNumber = "UO1800"
    static let callsignICAO = "HKE1800"

    static let flightDate = "2020-11-01"

    static let originIATA = "HKG"
    static let originICAO = "VHHH"
    static let originName = "Hong Kong International Airport"
    static let originNameLocalized = "香港国际机场"

    static let destinationIATA = "HKG"
    static let destinationICAO = "VHHH"
    static let destinationName = "Hong Kong International Airport"
    static let destinationNameLocalized = "香港国际机场"

    static let scheduledDeparture = "14:30 HKT"
    static let scheduledArrival = "16:00 HKT"
    static let actualDeparture = "14:46 HKT"
    static let actualArrival = "15:57 HKT"
    static let duration = "1 小时 11 分钟"
    static let cruiseAltitudeFt = 25_000

    static let aircraftType = "Airbus A320-271N"
    static let aircraftTypeShort = "A320neo"
    static let registration = "B-LCR"
    static let aircraftName = "紫菜 / Nori"
    static let landingRunway = "25R"
}
