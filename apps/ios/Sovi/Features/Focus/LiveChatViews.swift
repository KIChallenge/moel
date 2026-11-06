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

/// The conversation chooses a service; MapKit supplies the actual practices.
@MainActor
enum NearbyPracticeLookup {
    static func results(for search: ChatNearbySearch, language: ChatLanguage) async throws -> [ChatProvider] {
        let center: CLLocationCoordinate2D
        switch search.area.source {
        case "device_gps":
            guard let point = search.area.coordinates else { return [] }
            center = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        case "user_text":
            guard let place = search.area.query, !place.isEmpty, place.count <= 160 else { return [] }
            let areas = try await CLGeocoder().geocodeAddressString(place + ", Österreich")
            guard let location = areas.first(where: { $0.isoCountryCode == "AT" })?.location else { return [] }
            center = location.coordinate
        default: return []
        }
        guard CLLocationCoordinate2DIsValid(center), search.query.count <= 75, !search.query.isEmpty else { return [] }
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        for radius in [15_000.0, 45_000.0] {
            try Task.checkCancellation()
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = search.query
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
            request.regionPriority = .required
            request.resultTypes = .pointOfInterest
            let result: MKLocalSearch.Response
            do {
                result = try await MKLocalSearch(request: request).start()
            } catch let error as MKError where error.code == .placemarkNotFound { continue }
            try Task.checkCancellation()
            var seen = Set<String>()
            let sorted = result.mapItems.compactMap { item -> (ChatProvider, Double)? in
                guard let name = item.name, let point = item.placemark.location, item.placemark.isoCountryCode == "AT",
                      let address = item.placemark.title, !address.isEmpty else { return nil }
                let distance = point.distance(from: origin)
                let id = name + "|" + address
                guard distance <= radius, seen.insert(id).inserted else { return nil }
                var directions = URLComponents(string: "https://maps.apple.com/")!
                directions.queryItems = [URLQueryItem(name: "daddr", value: "\(point.coordinate.latitude),\(point.coordinate.longitude)")]
                let url = directions.url!.absoluteString
                let digits = item.phoneNumber?.filter { $0 == "+" || ($0.isASCII && $0.isNumber) }
                let provider = ChatProvider(id: id, name: name, specialty: search.query, address: address,
                    distance_km: search.area.source == "device_gps" ? distance / 1000 : nil, phone: digits, url: nil,
                    map_url: url, insurance_verified: false, source_url: url, source_label: "Apple Maps",
                    retrieved_at: Date().formatted(.iso8601), latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
                return (provider, distance)
            }.sorted { $0.1 < $1.1 }
            if !sorted.isEmpty { return sorted.prefix(3).map(\.0) }
        }
        return []
    }
}

struct LiveChatResultView: View {
    let result: LiveChatReply
    let active: Bool
    let looking: Bool
    let mapNotice: String?
    let busy: Bool
    let send: (String) -> Void
    let openAnswer: () -> Void
    @State private var selectedProvider: String?
    private var providers: [ChatProvider] { result.providers }

    private var language: ChatLanguage { result.language.flatMap(ChatLanguage.init(rawValue:)) ?? .app }

    private var mappedProviders: [ChatProvider] {
        providers.filter {
            guard let lat = $0.latitude, let lon = $0.longitude else { return false }
            return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(active ? result.choices : []) { choice in
                Button { if choice.opens_composer == true { openAnswer() } else { send(choice.message) } } label: {
                    HStack { Text(choice.label); Spacer(); Image(systemName: "arrow.turn.down.right") }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SheetPrimaryButtonStyle(tone: choice.opens_composer == true ? .quiet : .blue))
                .disabled(busy).accessibilityIdentifier("chat.\(choice.id)")
            }
            if looking { ProgressView(language.text("Praxen werden gesucht …")) }
            if let mapNotice { Text(mapNotice).font(.subheadline) }
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
            if providers.contains(where: { !$0.insurance_verified }) {
                Text("Versicherungsvertrag und freie Termine nicht bestätigt").font(.caption).foregroundStyle(SoviTheme.secondary)
            }
            if !providers.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(providers) { provider in
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
                            .containerRelativeFrame(.horizontal) { width, _ in providers.count > 1 ? max(1, width - 30) : width }
                            .id(provider.id)
                        }
                    }.scrollTargetLayout().padding(.bottom, 4)
                }
                .scrollIndicators(providers.count > 1 ? .visible : .hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedProvider, anchor: .leading)
                .accessibilityIdentifier("chat.providerCarousel")
            }
            ForEach(Array(result.actions.enumerated()), id: \.offset) { _, action in
                if let url = action.safeURL, !(action.type == "map_search" && !providers.isEmpty) {
                    Link(destination: url) {
                        HStack { Text(action.label); Spacer(); Image(systemName: url.scheme == "tel" ? "phone" : "arrow.up.right") }
                            .padding(16).frame(minHeight: 44)
                            .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            if result.status != "needs_clarification", !result.sources.isEmpty || !providers.isEmpty {
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
        return providers.filter { seen.insert($0.source_url).inserted }
    }
}
