import SwiftUI

struct PathDayCard: View {
    let day: PathDayGroup
    @Binding var selectedEntryID: UUID?
    let close: () -> Void
    let openDetails: (UUID) -> Void
    let onFocus: (UUID) -> Void

    @Environment(SoviStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var editingAppointment: AppointmentRecord?
    @AccessibilityFocusState private var headingIsFocused: Bool

    private var entry: PathNode? {
        day.entryCount == 1 ? day.entries.first : day.entries.first { $0.id == selectedEntryID }
    }

    private var palette: PathSymbolPalette {
        PathSymbolPalette(topic: day.displayNode.routeTopic, progress: day.progress(in: store.state, now: store.now), scheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                if selectedEntryID != nil, day.entryCount > 1 {
                    Button { selectedEntryID = nil } label: {
                        Image(systemName: "chevron.backward").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Zurück")
                    .accessibilityIdentifier("path.card.back")
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingIsFocused)
                    if let vaccination = entry?.vaccination {
                        Text(vaccination.administrationText).font(.subheadline)
                    } else if let record = appointment(for: entry) {
                        Text(record.date, format: .dateTime.day().month(.wide).year().hour().minute()).font(.subheadline)
                    } else if let date = day.date {
                        Text(date, format: .dateTime.day().month(.wide).year()).font(.subheadline)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: close) {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Schließen")
                .accessibilityIdentifier("path.card.close")
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.ink)

            if let entry {
                summary(for: entry)
                actions(for: entry)
            } else {
                ForEach(day.entries) { item in
                    Button { selectedEntryID = item.id } label: {
                        HStack(spacing: 12) {
                            PathNodeSymbol(topic: item.routeTopic, size: 22, tintColor: palette.ink)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayTitle).font(.system(.body, design: .rounded, weight: .semibold))
                                Text(status(for: item)).font(.caption)
                            }
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.forward").font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PathCardActionStyle(palette: palette))
                    .accessibilityIdentifier("day.entry.\(item.id.uuidString)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(SoviTheme.ink)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("path.card")
        .task(id: entry?.id) {
            await Task.yield()
            if !Task.isCancelled { headingIsFocused = true }
        }
        .sheet(item: $editingAppointment) { AppointmentEditorSheet(appointment: $0) }
    }

    private func appointment(for node: PathNode?) -> AppointmentRecord? {
        guard let id = node?.appointmentID else { return nil }
        return store.state.appointments.first { $0.id == id }
    }

    private var title: String {
        if day.entryCount > 1, let entry { return entry.displayTitle }
        return day.title == "Mein Tag" ? String(localized: "Mein Tag") : day.title
    }

    private func status(for node: PathNode) -> String {
        if let record = node.vaccination { return record.doseLabel }
        if node.kind == .task { return node.taskStatus.displayTitle }
        if let appointment = appointment(for: node) {
            return appointment.status == .confirmed ? appointment.attendance.displayTitle : appointment.status.displayTitle
        }
        if node.informationRead { return String(localized: "Gelesen") }
        return node.history?.displayStatus ?? node.kind.displayTitle
    }

    @ViewBuilder private func summary(for node: PathNode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let vaccination = node.vaccination {
                Text(vaccination.product).font(.body.weight(.semibold))
                if !vaccination.doseLabel.isEmpty { Text(vaccination.doseLabel) }
            } else {
                if day.entryCount == 1, day.title != node.displayTitle {
                    Text(node.displayTitle).font(.body.weight(.semibold))
                }
                if let record = appointment(for: node), !record.displayLocation.isEmpty {
                    Label(record.displayLocation, systemImage: "mappin.and.ellipse")
                }
                if !node.displayDetail.isEmpty {
                    Text(node.displayDetail)
                        .lineLimit(textSize.isAccessibilitySize ? nil : 3)
                }
                Text(status(for: node)).font(.subheadline.weight(.semibold))
            }
        }
        .font(.body)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func actions(for node: PathNode) -> some View {
        if node.kind == .task {
            TaskDraftButtons(node: node)
                .buttonStyle(PathCardActionStyle(palette: palette))
            Button {
                perform(.setTask(node.id, node.taskStatus == .completed ? .open : .completed))
            } label: {
                Label(node.taskStatus == .completed ? "Wieder öffnen" : "Erledigen", systemImage: node.taskStatus == .completed ? "arrow.uturn.backward" : "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PathCardActionStyle(palette: palette))
            .accessibilityIdentifier("preview.complete")
        } else if let appointment = appointment(for: node) {
            Button { editingAppointment = appointment } label: {
                Label("Termin bearbeiten", systemImage: "calendar").frame(maxWidth: .infinity)
            }
            .buttonStyle(PathCardActionStyle(palette: palette))
            .accessibilityIdentifier("preview.appointment.edit")
        } else if node.kind == .information, node.vaccination == nil {
            Button { perform(.markRead(node.id, !node.informationRead)) } label: {
                Label(node.informationRead ? "Lesemarkierung zurücknehmen" : "Als gelesen markieren", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PathCardActionStyle(palette: palette))
            .accessibilityIdentifier("preview.read")
        }

        if node.kind == .task || appointment(for: node) != nil || node.kind == .information && node.vaccination == nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { askSovi(for: node); details(for: node) }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { askSovi(for: node); details(for: node) }
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(palette.ink)
        } else {
            askSovi(for: node).buttonStyle(PathCardActionStyle(palette: palette))
            details(for: node)
                .buttonStyle(.plain)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(palette.ink)
        }
    }

    private func askSovi(for node: PathNode) -> some View {
        Button { onFocus(node.id) } label: {
            Label("Sovi fragen", systemImage: "bubble.left").frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityIdentifier("preview.focus")
    }

    private func details(for node: PathNode) -> some View {
        Button { openDetails(node.id) } label: {
            Label("Details", systemImage: "chevron.forward").frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityIdentifier("path.card.details")
    }

    private func perform(_ command: AppCommand) {
        do { try store.perform(command) } catch { store.errorMessage = error.localizedDescription }
    }
}

private struct PathCardActionStyle: ButtonStyle {
    let palette: PathSymbolPalette

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        configuration.label
            .font(.system(.body, design: .rounded, weight: .bold))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(SoviTheme.bubble, in: shape)
            .overlay(shape.strokeBorder(palette.ink.opacity(0.22), lineWidth: 1))
            .offset(y: configuration.isPressed ? 2 : 0)
            .background(palette.base, in: shape.offset(y: 3))
            .padding(.bottom, 3)
            .contentShape(Rectangle())
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
