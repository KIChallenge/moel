import SwiftUI
import SwiftData

@main
struct SoviApp: App {
    @State private var store: SoviStore?
    @State private var device = DeviceServices()
    @State private var chat = LiveChatController()
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    HomeView().environment(store).environment(device).environment(chat)
                        .environment(\.calendar, store.state.pathCalendar)
                        .environment(\.timeZone, store.state.pathCalendar.timeZone)
                } else {
                    VStack(spacing: 20) {
                        SoviMascot(size: 130)
                        if let startupError {
                            Text(startupError).font(.body)
                            Button("Erneut versuchen") { load() }
                        } else {
                            ProgressView().accessibilityLabel("Wird geladen")
                        }
                    }.padding(28)
                }
            }
            .tint(SoviTheme.accent)
            .task { if store == nil { load() } }
        }
    }

    private func load() {
        do {
            let inMemory = ProcessInfo.processInfo.arguments.contains("--uitesting")
            let loaded = try SoviStore(container: SoviStore.makeContainer(inMemory: inMemory))
            if inMemory && ProcessInfo.processInfo.arguments.contains("--case-demo-person") {
                try loaded.perform(.savePerson(FormPerson(label: "Fiktive Testperson", isSelf: true, values: [
                    "firstName": "Erika", "lastName": "Musterfrau", "birthDate": "12.03.1960", "street": "Musterstraße", "house": "12", "postcode": "1010", "city": "Wien"
                ])))
            }
            store = loaded
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
}
