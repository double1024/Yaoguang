import SwiftUI

@main
struct YaoguangApp: App {
    @StateObject private var receiver = ReceiverModel()

    var body: some Scene {
        WindowGroup {
            FlightListView(receiver: receiver)
                .frame(minWidth: 760, minHeight: 460)
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

    var body: some View {
        Form {
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
