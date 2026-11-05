import SwiftUI

struct PathDaySheet: View {
    let dayID: String
    let onFocus: (UUID) -> Void
    @Environment(SoviStore.self) private var store
    @State private var selectedEntry: PathNode?

    private var day: PathDayGroup? { store.state.pathDays.first { $0.id == dayID } }

    var body: some View {
        if let day, day.entries.count == 1, let entry = day.entries.first {
            NodePreviewSheet(nodeID: entry.id, onFocus: onFocus)
        } else {
            SheetPage(title: day?.title ?? String(localized: "Mein Tag")) {
                if let day {
                    if let date = day.date {
                        Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                            .font(.title2.bold())
                    }
                    Text("\(day.entryCount) Einträge")
                        .font(.subheadline).foregroundStyle(SoviTheme.secondary)
                    ForEach(day.entries) { entry in
                        Button { selectedEntry = entry } label: {
                            HStack(alignment: .top, spacing: 16) {
                                PathNodeSymbol(topic: entry.routeTopic, size: 25)
                                    .frame(width: 42, height: 46)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.displayTitle).font(.headline)
                                    if entry.vaccination != nil {
                                        Text("Impfung").font(.caption)
                                    } else if let record = entry.history {
                                        Text(LocalizedStringKey(record.category.rawValue)).font(.caption)
                                        if record.linkedTaskID != nil {
                                            Label("Verknüpfte Aufgabe", systemImage: "link").font(.caption)
                                        }
                                    }
                                    Text(status(for: entry)).font(.caption).foregroundStyle(SoviTheme.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote)
                            }
                            .foregroundStyle(SoviTheme.ink)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("day.entry.\(entry.id.uuidString)")
                        Divider()
                    }
                } else {
                    Text("Keine Einträge")
                }
            }
            .sheet(item: $selectedEntry) { entry in
                NodePreviewSheet(nodeID: entry.id, onFocus: onFocus)
            }
        }
    }

    private func status(for node: PathNode) -> String {
        if let vaccination = node.vaccination { return vaccination.doseLabel }
        if node.kind == .task { return node.taskStatus.displayTitle }
        if let id = node.appointmentID, let record = store.state.appointments.first(where: { $0.id == id }) {
            return record.attendance.displayTitle
        }
        return node.history?.displayStatus ?? node.routeStatus
    }
}

struct LifeRecordContext: View {
    let node: PathNode
    @Environment(SoviStore.self) private var store
    @State private var relatedEntry: PathNode?
    var onFocus: (UUID) -> Void

    var body: some View {
        Group {
            if let record = node.history {
                let related = relatedNodes(record)
                if node.title == "Kostenerstattung" {
                    SheetSection(title: "Unterlagen") {
                        ForEach(related.filter { [LifePathSeed.stableID("P210-3"), LifePathSeed.stableID("P215-2"), LifePathSeed.stableID("P216-1")].contains($0.id) }) { other in
                            Button { relatedEntry = other } label: {
                                Label(other.displayTitle, systemImage: "doc.text.magnifyingglass").frame(minHeight: 44)
                            }
                        }
                    }
                }
                if !related.isEmpty {
                    DisclosureGroup("Verknüpfte Einträge") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(related) { other in
                                Button { relatedEntry = other } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(other.displayTitle).font(.subheadline.weight(.medium))
                                        if let date = other.date {
                                            Text(date, format: .dateTime.day().month(.wide).year()).font(.caption)
                                        }
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                            }
                        }.padding(.top, 8)
                    }
                }
            }
        }
        .sheet(item: $relatedEntry) { entry in NodePreviewSheet(nodeID: entry.id, onFocus: onFocus) }
    }

    private func relatedNodes(_ record: LifeRecord) -> [PathNode] {
        guard !record.episodeIDs.isEmpty else { return [] }
        return store.nodes.filter { candidate in
            candidate.id != node.id && candidate.history?.episodeIDs.contains(where: record.episodeIDs.contains) == true
        }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }
}

struct LifePreparationSheet: View {
    let kind: LifeDraftKind
    @Environment(SoviStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var openedEpoch: Date?
    @State private var error: String?

    var body: some View {
        SheetPage(title: kind == .questionnaire ? "Anamnesebogen" : "Medikamentenliste") {
            Text("Notizen").font(.headline)
            TextEditor(text: $text).frame(minHeight: 240).padding(10)
                .background(SoviTheme.background, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("preparation.editor")
            Button("Speichern") {
                do { try save(); dismiss() } catch { self.error = error.localizedDescription }
            }.buttonStyle(SheetPrimaryButtonStyle())
        }
        .onAppear { openedEpoch = store.state.fixtureEpoch; text = store.state.lifeDrafts?[kind.rawValue] ?? "" }
        .onDisappear {
            guard openedEpoch == store.state.fixtureEpoch, text != (store.state.lifeDrafts?[kind.rawValue] ?? "") else { return }
            do { try save() } catch { store.errorMessage = error.localizedDescription }
        }
        .sheetError($error)
    }

    private func save() throws {
        guard openedEpoch == store.state.fixtureEpoch else { return }
        try store.perform(.saveLifeDraft(kind, text))
    }
}
