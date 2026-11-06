import SwiftUI
import MapKit

struct LiveChatSettingsSheet: View {
    @Environment(LiveChatController.self) private var chat
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var enabled = false
    @State private var gps = false
    @State private var consent = false
    @State private var error: String?
    @State private var responseLanguage = "auto"
    @State private var selectedBackground: Set<String> = []
    @State private var backgroundFilter = ""

    private var shareableNodes: [PathNode] {
        let localIDs = store.state.chatAttachmentEventIDs
        return store.nodes.filter { !localIDs.contains($0.id) }
    }

    private var recentBackground: [ChatBackground] {
        let anchor = store.state.lifeScenario?.snapshot ?? store.now
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = store.state.pathCalendar.timeZone
        return shareableNodes.filter { $0.date != nil && $0.date! <= anchor
            && (backgroundFilter.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(backgroundFilter)) }
            .sorted { $0.date! > $1.date! }.prefix(backgroundFilter.isEmpty ? 8 : 30).map {
                ChatBackground(id: $0.id.uuidString, title: String($0.displayTitle.prefix(140)), date: formatter.string(from: $0.date!), is_synthetic: store.state.lifeScenario != nil)
            }
    }

    var body: some View {
        SheetPage(title: "Online-Chat") {
            SheetSection(title: "Verbindung") {
                Text("sovi.elzahaby.at").font(.subheadline.monospaced())
                SecureField("API-Zugangscode", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("chat.token")
                Text("Der Zugangscode wird im Schlüsselbund dieses Geräts gespeichert. Trage hier nicht deinen OpenAI-Schlüssel ein.")
                    .font(.footnote).foregroundStyle(SoviTheme.secondary)
                Toggle("Online-Chat verwenden", isOn: $enabled).accessibilityIdentifier("chat.enabled")
                Toggle("Aktuellen Standort mitsenden", isOn: $gps)
                    .disabled(!enabled).accessibilityIdentifier("chat.gps")
                Picker("Antwortsprache", selection: $responseLanguage) {
                    Text("Automatisch").tag("auto")
                    Text("Deutsch").tag("de"); Text("English").tag("en")
                    Text("العربية").tag("ar"); Text("Türkçe").tag("tr")
                }
            }
            SheetSection(title: "Was wird übermittelt?") {
                Text("Nachrichten dieses Online-Gesprächs und nur die unten von dir angekreuzten Hintergrund-Einträge gehen an den Sovi-Server und OpenAI. Dokumente und der übrige Pfad bleiben auf dem Gerät. Freiwillige GPS-Daten gehen nur an den Sovi-Server.")
                Text("Nenne für andere Personen keine Namen oder vertraulichen Dokumentdetails. Der Online-Verlauf bleibt nur bis zum neuen Gespräch oder App-Neustart im Arbeitsspeicher. Bereits übermittelte Daten können nicht zurückgerufen werden; Server- und OpenAI-Aufbewahrung sind davon getrennt.")
                    .font(.footnote)
                Toggle("Ich stimme dieser Übermittlung für den Online-Chat zu", isOn: $consent)
                    .disabled(!enabled).accessibilityIdentifier("chat.consent")
            }
            SheetSection(title: "Hintergrund freiwillig teilen") {
                Text("Wähle höchstens vier Einträge. Sovi fragt nach, bevor es einen Zusammenhang mit deinem Anliegen annimmt. Die Auswahl gilt nur für diese App-Sitzung; Änderungen starten ein neues Online-Gespräch.")
                    .font(.footnote)
                TextField("Ältere Einträge finden", text: $backgroundFilter)
                ForEach(recentBackground) { record in
                    Toggle(isOn: Binding(get: { selectedBackground.contains(record.id) }, set: { checked in
                        if checked { selectedBackground.insert(record.id) } else { selectedBackground.remove(record.id) }
                    })) {
                        VStack(alignment: .leading) {
                            Text(record.title)
                            Text(record.date).font(.caption)
                        }
                    }.disabled(!selectedBackground.contains(record.id) && selectedBackground.count >= 4)
                }
            }
            SheetSection(title: "Orientierung") {
                Text("Sovi hilft beim Finden einer ersten Anlaufstelle. Der Chat stellt keine Diagnose und beurteilt keine Dringlichkeit. Bei einem medizinischen Notfall in Österreich: 144.")
                    .font(.footnote)
                Button("Speichern") {
                    do {
                        try chat.configure(token: token, enabled: enabled, shareLocation: gps, responseLanguage: responseLanguage)
                        let chosen = shareableNodes.filter { selectedBackground.contains($0.id.uuidString) }.compactMap { node -> ChatBackground? in
                            guard let date = node.date else { return nil }
                            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = store.state.pathCalendar.timeZone
                            return ChatBackground(id: node.id.uuidString, title: String(node.displayTitle.prefix(140)), date: formatter.string(from: date), is_synthetic: store.state.lifeScenario != nil)
                        }
                        chat.setBackground(enabled ? chosen : [])
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .disabled(enabled && !consent)
                .frame(minHeight: 44).accessibilityIdentifier("chat.save")
                Button("Zugangscode und Online-Verlauf löschen", role: .destructive) {
                    do { try chat.deleteCredentials(); dismiss() } catch { self.error = error.localizedDescription }
                }.frame(minHeight: 44)
            }
        }
        .onAppear {
            token = chat.editableToken; enabled = chat.enabled; gps = chat.shareLocation; consent = chat.enabled
            responseLanguage = chat.responseLanguage; selectedBackground = Set(chat.background.map(\.id))
        }
        .sheetError($error)
    }
}

struct LiveChatResultView: View {
    let result: LiveChatReply
    let busy: Bool
    let send: (String) -> Void
    let openAnswer: () -> Void
    @State private var selectedProvider: String?

    private var mappedProviders: [ChatProvider] {
        result.providers.filter {
            guard let lat = $0.latitude, let lon = $0.longitude else { return false }
            return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !result.choices.isEmpty {
                Text("Du kannst auswählen oder selbst antworten.").font(.caption).foregroundStyle(SoviTheme.secondary)
            }
            ForEach(result.choices) { choice in
                Button { if choice.opens_composer == true { openAnswer() } else { send(choice.message) } } label: {
                    HStack { Text(choice.label); Spacer(); Image(systemName: "arrow.turn.down.right") }
                        .font(.body.weight(.medium)).padding(16)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(busy).accessibilityIdentifier("chat.\(choice.id)")
            }
            if !mappedProviders.isEmpty {
                Text("Anlaufstellen auf der Karte").font(.headline)
                Map(initialPosition: .automatic, interactionModes: [.zoom], selection: $selectedProvider) {
                    ForEach(mappedProviders) { provider in
                        Marker(provider.name, coordinate: CLLocationCoordinate2D(latitude: provider.latitude!, longitude: provider.longitude!))
                            .tint(SoviTheme.accent).tag(provider.id)
                    }
                }
                .mapControls { MapCompass(); MapScaleView() }
                .frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 20))
                .id(mappedProviders.map(\.id))
                .accessibilityLabel("Karte der vorgeschlagenen Anlaufstellen")
                .accessibilityIdentifier("chat.map")
                if let selected = result.providers.first(where: { $0.id == selectedProvider }) {
                    Text(selected.name + " · " + selected.address).font(.subheadline)
                }
            }
            ForEach(result.providers) { provider in
                VStack(alignment: .leading, spacing: 10) {
                    Text(provider.name).font(.headline)
                    Text(provider.specialty).font(.subheadline)
                    Text(provider.address).font(.subheadline)
                    if let distance = provider.distance_km {
                        Text("\(distance.formatted(.number.precision(.fractionLength(1)))) km Luftlinie")
                            .font(.caption)
                    }
                    Text("Versicherungsvertrag und freie Termine nicht bestätigt")
                        .font(.caption).foregroundStyle(SoviTheme.secondary)
                    if let phone = provider.phone, let url = ChatDestination.allowedURL("tel:" + phone) {
                        Link(destination: url) { Label("Anrufen", systemImage: "phone") }.frame(minHeight: 44)
                    }
                    if let url = ChatDestination.allowedURL(provider.map_url) {
                        Link(destination: url) { Label("Wegbeschreibung", systemImage: "map") }.frame(minHeight: 44)
                    }
                    if let profile = provider.url, let url = ChatDestination.allowedURL(profile) {
                        Link("Praxisprofil öffnen", destination: url).frame(minHeight: 44)
                    }
                    if let url = ChatDestination.allowedURL(provider.source_url) {
                        Link(provider.source_label, destination: url).font(.caption).frame(minHeight: 44)
                    }
                    Text("Verzeichnis abgerufen: \(provider.retrieved_at)").font(.caption2)
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(SoviTheme.softGreen.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(selectedProvider == provider.id ? SoviTheme.accent : .clear, lineWidth: 2).allowsHitTesting(false))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("chat.provider")
            }
            ForEach(Array(result.actions.enumerated()), id: \.offset) { _, action in
                if let url = action.safeURL {
                    Link(destination: url) {
                        HStack { Text(action.label); Spacer(); Image(systemName: url.scheme == "tel" ? "phone" : "arrow.up.right") }
                            .padding(16).frame(minHeight: 44)
                            .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            Text(result.notice).font(.footnote).foregroundStyle(SoviTheme.secondary)
            ForEach(Array(result.sources.enumerated()), id: \.offset) { _, source in
                if let url = ChatDestination.allowedURL(source.url) {
                    Link(source.title, destination: url).font(.caption).frame(minHeight: 44)
                }
            }
        }
        .environment(\.layoutDirection, result.language == "ar" ? .rightToLeft : .leftToRight)
    }
}
