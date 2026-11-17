import SwiftUI

/// Callsign 航线编辑页。
///
/// 手动输入机场/航司 ICAO：本地已有则显示全名（只读）；本地缺失则要求填写全名并新建记录。
struct RouteEditorView: View {
    let callsign: String
    @ObservedObject var resolver: FlightInfoResolver
    let onDismiss: () -> Void

    @State private var originICAO = ""
    @State private var originName = ""
    @State private var destinationICAO = ""
    @State private var destinationName = ""
    @State private var airlineICAO = ""
    @State private var airlineName = ""

    @State private var loadedOriginName: String?
    @State private var loadedDestinationName: String?
    @State private var loadedAirlineName: String?
    @State private var routeSource: String?
    @State private var fetchedAt: Date?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Form {
                Section("Route") {
                    airportFields(
                        title: "出发机场",
                        icao: $originICAO,
                        name: $originName,
                        knownName: loadedOriginName
                    )
                    airportFields(
                        title: "到达机场",
                        icao: $destinationICAO,
                        name: $destinationName,
                        knownName: loadedDestinationName
                    )
                }

                Section("Airline") {
                    LabeledContent("航司 ICAO") {
                        TextField("如 ACA", text: $airlineICAO)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                            .onChange(of: airlineICAO) { _, newValue in
                                airlineICAO = newValue.uppercased()
                            }
                    }
                    if let known = loadedAirlineName {
                        LabeledContent("航司全名", value: known)
                    } else if !airlineICAO.isEmpty {
                        LabeledContent("航司全名") {
                            TextField("本地无此航司，请填写全名", text: $airlineName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                Section("Info") {
                    LabeledContent("Callsign", value: callsign)
                    LabeledContent("数据来源", value: sourceLabel)
                    if let fetchedAt {
                        LabeledContent("更新时间", value: Self.dateFormatter.string(from: fetchedAt))
                    }
                }
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            footer
        }
        .frame(width: 520, height: 560)
        .task { await load() }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("编辑航线")
                    .font(.headline)
                Text(callsign)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func airportFields(
        title: String,
        icao: Binding<String>,
        name: Binding<String>,
        knownName: String?
    ) -> some View {
        LabeledContent("\(title) ICAO") {
            TextField("如 CYVR", text: icao)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onChange(of: icao.wrappedValue) { _, newValue in
                    icao.wrappedValue = newValue.uppercased()
                }
        }
        if let knownName {
            LabeledContent("\(title)全名", value: knownName)
        } else if !icao.wrappedValue.isEmpty {
            LabeledContent("\(title)全名") {
                TextField("本地无此机场，请填写全名", text: name)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Button("取消") { onDismiss() }
                .keyboardShortcut(.cancelAction)
            Button("重新查询") {
                Task {
                    await resolver.refreshRouteFromAPI(callsign: callsign, flightID: nil)
                    await load()
                }
            }
            Button("保存") {
                Task { await save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isLoading || isSaving)
        }
        .padding(20)
    }

    // MARK: - 逻辑

    private var sourceLabel: String {
        switch routeSource {
        case "manual": return "手工修改"
        case "adsbdb": return "ADSBdb"
        case .some(let other): return other
        case nil: return "未知"
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let route = await resolver.editableRoute(callsign: callsign) else { return }
        originICAO = route.originICAO ?? ""
        destinationICAO = route.destinationICAO ?? ""
        airlineICAO = route.airlineICAO ?? ""
        loadedOriginName = route.originName
        loadedDestinationName = route.destinationName
        loadedAirlineName = route.airlineName
        routeSource = route.routeSource
        fetchedAt = route.fetchedAt
        errorMessage = nil
    }

    private func save() async {
        errorMessage = nil

        let origin = originICAO.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationICAO.trimmingCharacters(in: .whitespacesAndNewlines)

        if origin.isEmpty || destination.isEmpty {
            errorMessage = "出发机场和到达机场的 ICAO 不能为空。"
            return
        }
        if loadedOriginName == nil, originName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "本地无机场 \(origin)，请填写其全名。"
            return
        }
        if loadedDestinationName == nil, destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "本地无机场 \(destination)，请填写其全名。"
            return
        }
        let airline = airlineICAO.trimmingCharacters(in: .whitespacesAndNewlines)
        if !airline.isEmpty, loadedAirlineName == nil,
           airlineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "本地无航司 \(airline)，请填写全名或留空。"
            return
        }

        isSaving = true
        defer { isSaving = false }

        await resolver.saveManualRoute(
            callsignICAO: callsign,
            originICAO: origin, originName: originName,
            destinationICAO: destination, destinationName: destinationName,
            airlineICAO: airline.isEmpty ? nil : airline,
            airlineName: airlineName
        )
        onDismiss()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
