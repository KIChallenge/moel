import SwiftUI
import MapKit

/// Optional context sharing, kept out of the normal first-message flow.
struct ChatBackgroundSheet: View {
    @Environment(LiveChatController.self) private var chat
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var query = ""

    private var entries: [ChatBackground] {
        let anchor = store.state.lifeScenario?.snapshot ?? store.now
        let imported = store.state.chatAttachmentEventIDs
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = store.state.pathCalendar.timeZone
        return store.nodes.filter {
            !imported.contains($0.id) && $0.date.map { $0 <= anchor } == true
            && (query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query))
        }.sorted { $0.date! > $1.date! }.prefix(query.isEmpty ? 8 : 30).map {
            ChatBackground(id: $0.id.uuidString, title: String($0.displayTitle.prefix(140)),
                           date: formatter.string(from: $0.date!), is_synthetic: store.state.lifeScenario != nil)
        }
    }

    var body: some View {
        SheetPage(title: "Hintergrund teilen", startsCompact: true) {
            Text("Wähle bis zu vier Einträge für das neue Gespräch.")
            TextField("Eintrag suchen", text: $query).textFieldStyle(.roundedBorder)
            ForEach(entries) { entry in
                Button {
                    if selected.contains(entry.id) { selected.remove(entry.id) }
                    else { selected.insert(entry.id) }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title).font(.body.weight(.medium))
                            Text(entry.date).font(.caption).foregroundStyle(SoviTheme.secondary)
                        }
                        Spacer()
                        Image(systemName: selected.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!selected.contains(entry.id) && selected.count >= 4)
                .accessibilityAddTraits(selected.contains(entry.id) ? .isSelected : [])
            }
            Text("Nur ausgewählte Titel und Daten werden mit OpenAI geteilt.")
                .font(.footnote).foregroundStyle(SoviTheme.secondary)
            Button("Übernehmen") {
                // Include selected older entries even if they are hidden by a search.
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = store.state.pathCalendar.timeZone
                let chosen = store.nodes.filter {
                    selected.contains($0.id.uuidString) && !store.state.chatAttachmentEventIDs.contains($0.id)
                }.compactMap { node -> ChatBackground? in
                    guard let date = node.date else { return nil }
                    return ChatBackground(id: node.id.uuidString, title: String(node.displayTitle.prefix(140)),
                                          date: formatter.string(from: date), is_synthetic: store.state.lifeScenario != nil)
                }
                chat.setBackground(chosen)
                dismiss()
            }.buttonStyle(SheetPrimaryButtonStyle())
        }.onAppear { selected = Set(chat.background.map(\.id)) }
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
            ForEach(result.choices) { choice in
                Button { if choice.opens_composer == true { openAnswer() } else { send(choice.message) } } label: {
                    HStack { Text(choice.label); Spacer(); Image(systemName: "arrow.turn.down.right") }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SheetPrimaryButtonStyle(tone: choice.opens_composer == true ? .quiet : .blue))
                .disabled(busy).accessibilityIdentifier("chat.\(choice.id)")
            }
            if !mappedProviders.isEmpty {
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
            }
            if result.providers.contains(where: { !$0.insurance_verified }) {
                Text("Versicherungsvertrag und freie Termine nicht bestätigt").font(.caption).foregroundStyle(SoviTheme.secondary)
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
                    if let phone = provider.phone, let url = ChatDestination.allowedURL("tel:" + phone) {
                        Link(destination: url) { Label("Anrufen", systemImage: "phone") }.frame(minHeight: 44)
                    }
                    if let url = ChatDestination.allowedURL(provider.map_url) {
                        Link(destination: url) { Label("Wegbeschreibung", systemImage: "map") }.frame(minHeight: 44)
                    }
                    if let profile = provider.url, let url = ChatDestination.allowedURL(profile) {
                        Link("Praxisprofil öffnen", destination: url).frame(minHeight: 44)
                    }
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
            if result.status != "needs_clarification", !result.sources.isEmpty || !result.providers.isEmpty {
                DisclosureGroup("Quellen") {
                    ForEach(providerSources) { provider in
                        if let url = ChatDestination.allowedURL(provider.source_url) {
                            Link(provider.source_label, destination: url).frame(minHeight: 44)
                            Text("Verzeichnis abgerufen: \(provider.retrieved_at)").font(.caption)
                        }
                    }
                    ForEach(Array(result.sources.enumerated()), id: \.offset) { _, source in
                        if let url = ChatDestination.allowedURL(source.url) {
                            Link(source.title, destination: url).frame(minHeight: 44)
                        }
                    }
                }
            }
        }
        .environment(\.layoutDirection, result.language == "ar" ? .rightToLeft : .leftToRight)
    }

    private var providerSources: [ChatProvider] {
        var seen = Set<String>()
        return result.providers.filter { seen.insert($0.source_url).inserted }
    }
}
