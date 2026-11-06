import SwiftUI
import SwiftData

@main
struct SoviApp: App {
    @State private var store: SoviStore?
    @State private var device = DeviceServices()
    @State private var chat = LiveChatController.forApp()
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
            let arguments = ProcessInfo.processInfo.arguments
            let inMemory = arguments.contains("--uitesting")
            let loaded: SoviStore
            if inMemory {
                let instant = arguments.contains("--past-appointment-fixture") ? "2026-11-05T17:00:00Z" : "2026-11-05T08:00:00Z"
                let fixtureClock = ISO8601DateFormatter().date(from: instant)!
                loaded = try SoviStore(container: SoviStore.makeContainer(inMemory: true), clock: { fixtureClock })
            } else {
                loaded = try SoviStore(container: SoviStore.makeContainer())
            }
            if inMemory && ProcessInfo.processInfo.arguments.contains("--case-demo-person") {
                try loaded.perform(.savePerson(FormPerson(label: "Person", isSelf: true, values: [
                    "firstName": "Erika", "lastName": "Musterfrau", "birthDate": "12.03.1960", "street": "Musterstraße", "house": "12", "postcode": "1010", "city": "Wien"
                ])))
            }
            store = loaded
            startupError = nil
        } catch { startupError = error.localizedDescription }
    }
}
