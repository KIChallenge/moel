import SwiftUI

struct LocalControlsSheet: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var devices
    @Environment(LiveChatController.self) private var chat
    @State private var showsForms = false
    @State private var confirmsDeletion = false
    @State private var confirmsReload = false
    @State private var busy = false
    @State private var error: String?
    @State private var resultMessage: String?

    var body: some View {
        SheetPage(title: "Deine Daten", startsCompact: true) {
            SheetSection(title: "Profil") {
                Button("Profile und Formulare") { showsForms = true }
                    .frame(minHeight: 44).accessibilityIdentifier("controls.forms")
            }

            SheetSection(title: "Standort") {
                if chat.shareLocation {
                    Button("Standort nicht mehr verwenden") {
                        do { try chat.setLocationSharing(false) }
                        catch { self.error = error.localizedDescription }
                    }.frame(minHeight: 44)
                } else {
                    Button("Standort erlauben") {
                        Task {
                            do {
                                let allowed = try await chat.enableLocationFromWelcome()
                                if !allowed { resultMessage = String(localized: "Du kannst den Standort in den iPhone-Einstellungen erlauben.") }
                            } catch { self.error = error.localizedDescription }
                        }
                    }.frame(minHeight: 44)
                }
                Link("Berechtigungen verwalten", destination: URL(string: UIApplication.openSettingsURLString)!)
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
        .sheet(isPresented: $showsForms) { FormLibrarySheet() }
    }

    private var notificationControls: some View {
        SheetSection(title: "Erinnerungen") {
            Text(devices.notificationStatus).font(.subheadline)
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

    private func reset(reload: Bool) {
        busy = true
        Task {
            devices.stopAudio()
            await devices.cancelAllNotifications()
            do {
                try DraftExportFiles.clear()
                try PrototypeForm.clearExports()
                if !reload { try chat.clearLocalData() } else { chat.reset() }
                try store.perform(reload ? .reloadDemo : .deleteLocalData)
                resultMessage = reload ? "Pfad zurückgesetzt." : "Daten gelöscht."
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
