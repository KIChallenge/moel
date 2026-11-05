import SwiftUI

/// The same bubbles and free-text interaction as Sovi Focus, entirely on device.
struct WelcomeChatView: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var device
    @Environment(LiveChatController.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var showsProfile = false
    @State private var requestingPermission = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                SoviMascot(size: 46).accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text("Willkommen bei Sovi").font(.headline)
                    Text("Nur auf diesem Gerät").font(.caption).foregroundStyle(SoviTheme.secondary)
                }
                Spacer()
                Button(store.state.welcome?.completed == true ? "Schließen" : "Später") {
                    if store.state.welcome?.completed != true { answer(nil, finish: true) }
                    else { dismiss() }
                }.frame(minHeight: 44).disabled(requestingPermission).accessibilityIdentifier("welcome.later")
            }.padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        Text("Deine Antworten helfen beim Vorausfüllen von Formularen. Du kannst jede Frage überspringen und alles später ändern. Dieses Gespräch bleibt gespeichert; es wird nicht an den Online-Chat gesendet.")
                            .font(.caption).foregroundStyle(SoviTheme.secondary)
                        ForEach(store.state.welcome?.history ?? []) { turn in
                            SoviChatBubble(text: turn.text, isUser: turn.role == "user", read: turn.role == "assistant" ? { device.speak(turn.text, enabled: true) } : nil)
                                .id(turn.id)
                        }
                        if store.state.welcome?.completed == true {
                            Button("Angaben prüfen") { showsProfile = true }.buttonStyle(SheetPrimaryButtonStyle())
                            Button("Los geht’s") { dismiss() }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("welcome.done")
                        } else if store.state.welcome?.isLocationStep == true {
                            Button("Standort erlauben") { requestLocation() }.buttonStyle(SheetPrimaryButtonStyle()).disabled(requestingPermission).accessibilityIdentifier("welcome.location")
                            Button("Ohne Standort weiter") {
                                do {
                                    try chat.configure(token: chat.editableToken, enabled: chat.enabled, shareLocation: false, responseLanguage: chat.responseLanguage)
                                    answer(String(localized: "Ohne Standort weiter"))
                                } catch { self.error = error.localizedDescription }
                            }.frame(minHeight: 44).disabled(requestingPermission)
                        } else if store.state.welcome?.isNotificationStep == true {
                            Button("Erinnerungen erlauben") { requestNotifications() }.buttonStyle(SheetPrimaryButtonStyle()).disabled(requestingPermission).accessibilityIdentifier("welcome.notifications")
                            Button("Ohne Erinnerungen weiter") {
                                do {
                                    try store.perform(.setPreferences(notifications: false, spokenReplies: nil, straightPath: nil))
                                    Task { await device.cancelAllNotifications() }
                                    answer(String(localized: "Ohne Erinnerungen weiter"))
                                } catch { self.error = error.localizedDescription }
                            }.frame(minHeight: 44).disabled(requestingPermission)
                        } else if store.state.welcome?.field == .insurer {
                            ForEach(["ÖGK", "SVS", "BVAEB", "KFA"], id: \.self) { value in
                                Button(value) { answer(value) }.buttonStyle(SheetPrimaryButtonStyle())
                            }
                        }
                        if let error { Text(error).foregroundStyle(.red).font(.subheadline).accessibilityIdentifier("welcome.error") }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
                    .task(id: store.state.welcome?.history.last?.id) {
                        // Wait for the new bubble to enter layout; show its beginning,
                        // rather than skipping over it to the end of a long checklist.
                        await Task.yield()
                        guard !Task.isCancelled, let id = store.state.welcome?.history.last?.id else { return }
                        proxy.scrollTo(id, anchor: .top)
                    }
                    .task(id: focused) {
                        guard focused else { return }
                        await Task.yield()
                        if let id = store.state.welcome?.history.last?.id { proxy.scrollTo(id, anchor: .top) }
                    }
            }
            if store.state.welcome?.completed != true && store.state.welcome?.field != nil {
                Divider()
                HStack {
                    TextField("Schreib Sovi …", text: $text, axis: .vertical)
                        .lineLimit(1...3).focused($focused).autocorrectionDisabled()
                        .textInputAutocapitalization(store.state.welcome?.field == .email ? .never : .sentences)
                        .padding(12).background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18))
                        .accessibilityIdentifier("welcome.composer")
                    Button { answer(text) } label: { Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Nachricht senden").accessibilityIdentifier("welcome.send")
                }.padding(.horizontal, 16).padding(.top, 8)
                Button("Überspringen") { answer(nil) }.frame(minHeight: 44).accessibilityIdentifier("welcome.skip")
            }
        }.background(SoviTheme.background).foregroundStyle(SoviTheme.ink)
            .interactiveDismissDisabled(store.state.welcome?.completed != true)
            .task { do { try store.perform(.startWelcome) } catch { self.error = error.localizedDescription } }
            .onDisappear { device.stopAudio() }
            .sheet(isPresented: $showsProfile) {
                if let id = store.state.welcome?.personID, let person = store.state.formPeople?.first(where: { $0.id == id }) { FormPersonEditor(person: person) }
            }
    }
    private func answer(_ value: String?, finish: Bool = false) {
        do {
            try store.perform(.answerWelcome(value, finish: finish))
            text = ""; error = nil; focused = false; device.stopAudio()
            if finish { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
    private func requestLocation() {
        requestingPermission = true
        Task { @MainActor in
            do {
                let allowed = try await chat.enableLocationFromWelcome()
                answer(String(localized: allowed ? "Standort erlaubt" : "Standort nicht verfügbar – Ort bei Bedarf eingeben"))
            } catch { self.error = error.localizedDescription }
            requestingPermission = false
        }
    }
    private func requestNotifications() {
        requestingPermission = true
        Task { @MainActor in
            let allowed = await device.requestNotifications()
            if !allowed { device.errorMessage = nil } // Declining an optional welcome step is not an error.
            do {
                try store.perform(.setPreferences(notifications: allowed, spokenReplies: nil, straightPath: nil))
                answer(String(localized: allowed ? "Erinnerungen erlaubt" : "Ohne Erinnerungen weiter"))
                await device.reconcileNotifications(state: store.state)
            } catch { self.error = error.localizedDescription }
            requestingPermission = false
        }
    }
}
