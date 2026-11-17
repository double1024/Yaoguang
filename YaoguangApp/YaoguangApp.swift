import SwiftUI
import SwiftData

@main
struct YaoguangApp: App {
    private let store: HistoryStore
    private let resolver: FlightInfoResolver
    @StateObject private var receiver: ReceiverModel

    @MainActor
    init() {
        let container: ModelContainer
        do {
            container = try StoreLocation.makeModelContainer()
        } catch {
            fatalError("无法初始化本地存储：\(error)")
        }
        let store = HistoryStore(modelContainer: container)
        self.store = store
        let resolver = FlightInfoResolver(store: store)
        self.resolver = resolver
        _receiver = StateObject(wrappedValue: ReceiverModel(store: store, resolver: resolver))
        // 启动对账：结束上次运行遗留的 active 航班。
        Task { await store.reconcileActiveFlights(at: Date()) }
    }

    var body: some Scene {
        WindowGroup {
            FlightListView(receiver: receiver, resolver: resolver)
                .frame(minWidth: 700, minHeight: 440)
                .onAppear { receiver.start() }
                .onDisappear { receiver.stop() }
        }

        Settings {
            ReceiverSettingsView(receiver: receiver)
        }
    }
}

struct ReceiverSettingsView: View {
    @ObservedObject var receiver: ReceiverModel
    @AppStorage("lookupPriority") private var priorityRaw: String = LookupPriority.databaseFirst.rawValue
    @AppStorage("demoModeEnabled") private var demoModeEnabled: Bool = false

    var body: some View {
        Form {
            Section("小组件") {
                Toggle("演示模式", isOn: $demoModeEnabled)
                    .onChange(of: demoModeEnabled) { _, _ in
                        receiver.refreshWidget()
                    }
                Text("开启后桌面小组件每 5 秒轮播 10 条演示航线，不影响实时接收与存储。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("航线查询") {
                Picker("优先级", selection: $priorityRaw) {
                    ForEach(LookupPriority.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(LookupPriority(rawValue: priorityRaw)?.detail ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Receiver Connection") {
                HStack(alignment: .center, spacing: 16) {
                    Text("Reopens the RTL-SDR. The current flight list and packet counts will be cleared.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Reconnect") {
                        receiver.reconnect()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 440)
    }
}
