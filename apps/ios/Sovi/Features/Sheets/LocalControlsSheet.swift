import SwiftUI

struct LocalControlsSheet: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var devices
    @Environment(LiveChatController.self) private var chat
    @State private var showsChatSettings = false
    @State private var showsForms = false
    @State private var showsWelcome = false
    @State private var confirmsDeletion = false
    @State private var confirmsReload = false
    @State private var busy = false
    @State private var error: String?
    @State private var resultMessage: String?

    var body: some View {
        SheetPage(title: "Einstellungen", startsCompact: true) {
            SheetSection(title: "Datenschutz") {
                Label("Auf diesem Gerät gespeichert", systemImage: "lock.shield")
                    .font(.subheadline)
                Button("Online-Chat konfigurieren") { showsChatSettings = true }.frame(minHeight: 44)
                Button("Profile und Formulare") { showsForms = true }.frame(minHeight: 44).accessibilityIdentifier("controls.forms")
                Button("Willkommensgespräch") { showsWelcome = true }.frame(minHeight: 44)
            }

            SheetSection(title: "Darstellung und Audio") {
                Toggle("Gerader Pfad", isOn: preferenceBinding(\AppState.straightPath) { value in
                    .setPreferences(notifications: nil, spokenReplies: nil, straightPath: value)
                })
                Toggle("Antworten vorlesen", isOn: preferenceBinding(\AppState.spokenReplies) { value in
                    if !value { devices.stopAudio() }
                    return .setPreferences(notifications: nil, spokenReplies: value, straightPath: nil)
                })
                Button("Audio stoppen") { devices.stopAudio() }
                    .frame(minHeight: 44)
            }

            notificationControls

            SheetSection(title: "Daten") {
                Button("Alle Daten löschen", role: .destructive) { confirmsDeletion = true }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("controls.delete")
                Button("Pfad zurücksetzen") { confirmsReload = true }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("controls.reload")
                if let resultMessage {
                    Label(resultMessage, systemImage: "checkmark.circle")
                        .font(.subheadline)
                }
            }
        }
        .disabled(busy)
        .confirmationDialog("Alle Daten löschen?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { reset(reload: false) }
                .accessibilityIdentifier("controls.confirmDelete")
        } message: {
            Text("Alle lokalen Daten werden dauerhaft gelöscht.")
        }
        .confirmationDialog("Pfad zurücksetzen?", isPresented: $confirmsReload, titleVisibility: .visible) {
            Button("Zurücksetzen", role: .destructive) { reset(reload: true) }
                .accessibilityIdentifier("controls.confirmReload")
        } message: {
            Text("Alle Einträge und Änderungen werden ersetzt.")
        }
        .task { await devices.refreshNotificationStatus() }
        .sheetError($error)
        .sheet(isPresented: $showsChatSettings) { LiveChatSettingsSheet().environment(chat) }
        .sheet(isPresented: $showsForms) { FormLibrarySheet() }
        .sheet(isPresented: $showsWelcome) { WelcomeChatView() }
    }

    private var notificationControls: some View {
        SheetSection(title: "Erinnerungen") {
            Text(devices.notificationStatus).font(.subheadline)
            Label(store.state.notificationsEnabled ? "Ein" : "Aus",
                  systemImage: store.state.notificationsEnabled ? "bell" : "bell.slash")
            if store.state.notificationsEnabled {
                Button("Erinnerungen ausschalten") {
                    do {
                        try store.perform(.setPreferences(notifications: false, spokenReplies: nil, straightPath: nil))
                        Task { await devices.reconcileNotifications(state: store.state) }
                    } catch { self.error = error.localizedDescription }
                }
                .frame(minHeight: 44)
            } else {
                Button("Erinnerungen erlauben") {
                    Task {
                        guard await devices.requestNotifications() else {
                            error = devices.errorMessage ?? "Mitteilungen sind nicht erlaubt."
                            return
                        }
                        do {
                            try store.perform(.setPreferences(notifications: true, spokenReplies: nil, straightPath: nil))
                            await devices.reconcileNotifications(state: store.state)
                            if let message = devices.errorMessage { error = message }
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .frame(minHeight: 44)
            }
        }
    }

    private func preferenceBinding(_ keyPath: KeyPath<AppState, Bool>, command: @escaping (Bool) -> AppCommand) -> Binding<Bool> {
        Binding(get: { store.state[keyPath: keyPath] }, set: { value in
            do { try store.perform(command(value)) }
            catch { self.error = error.localizedDescription }
        })
    }

    private func reset(reload: Bool) {
        busy = true
        Task {
            devices.stopAudio()
            await devices.cancelAllNotifications()
            do {
                try DraftExportFiles.clear()
                try PrototypeForm.clearExports()
                if !reload { try chat.deleteCredentials() } else { chat.reset() }
                try store.perform(reload ? .reloadDemo : .deleteLocalData)
                resultMessage = reload ? "Pfad zurückgesetzt." : "Daten gelöscht."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
