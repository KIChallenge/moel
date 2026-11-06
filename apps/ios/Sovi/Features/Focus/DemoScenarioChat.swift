import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct DemoScenarioChat: View {
    let scenario: DemoScenario
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var device
    @Environment(LiveChatController.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var composerFocused: Bool
    @State private var error: String?
    @State private var showsForms = false
    @State private var showsDocuments = false
    @State private var locating = false
    @State private var showsNearby = false
    @State private var importsLetter = false
    @State private var importTask: Task<Void, Never>?
    private var language: ChatLanguage { progress?.replyLanguage ?? ChatLanguage(rawValue: chat.responseLanguage) ?? .app }
    private var progress: DemoScenarioProgress? { store.state.demoScenarios?[scenario.rawValue] }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Schließen").accessibilityIdentifier("scenario.close")
                SoviMascot(size: 44).accessibilityHidden(true)
                Text(scenario.title(in: progress?.replyLanguage ?? .app)).font(.headline)
                Spacer()
            }.padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(progress?.history ?? []) { turn in
                            SoviChatBubble(text: turn.displayText, isUser: turn.role == "user", read: turn.role == "assistant" ? { device.speak(turn.displayText, enabled: true) } : nil)
                                .id(turn.id)
                        }
                        if let progress {
                            if progress.finished {
                                preparation(progress)
                                if !(scenario == .care && progress.preparation?.nextQuestion(for: progress) != nil) {
                                Text("Deine nächsten Schritte").font(.headline)
                                ForEach(Array(progress.steps.enumerated()), id: \.offset) { index, title in
                                    let node = store.node(id: progress.taskID(index))
                                    HStack(alignment: .top) {
                                        Image(systemName: node?.taskStatus == .completed ? "checkmark.circle.fill" : "circle")
                                        Text(title)
                                        Spacer()
                                        if let node {
                                            Button(node.taskStatus == .completed ? "Wieder öffnen" : "Erledigen") {
                                                do { try store.perform(.setTask(node.id, node.taskStatus == .completed ? .open : .completed)) } catch { self.error = error.localizedDescription }
                                            }.frame(minHeight: 44)
                                        }
                                    }.padding(12).background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 16))
                                }
                                if !progress.saved {
                                    Button("Schritte auf meinem Pfad speichern") {
                                        do { try store.perform(.saveScenarioSteps(scenario)) } catch { self.error = error.localizedDescription }
                                    }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("scenario.save")
                                        .disabled(!canSave(progress))
                                } else { Label("Auf deinem Pfad gespeichert", systemImage: "checkmark.circle").accessibilityIdentifier("scenario.saved") }
                                if progress.suggestedForm != nil && ![.care, .hospital].contains(scenario) {
                                    Button("Passenden Formularentwurf öffnen") { showsForms = true }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("scenario.forms")
                                }
                                if nearbyQuery != nil {
                                    Button("Anlaufstellen in meiner Nähe") { showsNearby = true }.frame(minHeight: 44)
                                }
                                ForEach(progress.sources, id: \.1) { source in
                                    if let url = URL(string: source.1) { Link(source.0, destination: url).frame(minHeight: 44) }
                                }
                                Text("Quellenstand: 05.11.2026. Termine, Förderungen und Kosten sind nicht bestätigt.").font(.caption).foregroundStyle(SoviTheme.secondary)
                                }
                            } else {
                                if scenario == .care && progress.answers.count == 1 && chat.shareLocation {
                                    Button("Für sie an meinem aktuellen Standort suchen") {
                                        locating = true
                                        Task { @MainActor in
                                            if let place = await chat.refreshLocalServiceArea() { answer(place) }
                                            else { error = progress.replyLanguage.text("Kein aktueller Standort verfügbar. Du kannst einen Ort im Chat nennen.") }
                                            locating = false
                                        }
                                    }.frame(minHeight: 44).disabled(locating)
                                }
                                ForEach(Array(progress.choices.enumerated()), id: \.offset) { index, choice in
                                    Button(choice) { answer(choice) }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("scenario.choice.\(index)")
                                }
                                if scenario == .hospital && progress.answers.isEmpty {
                                    Button("Brief importieren") { importsLetter = true }.frame(minHeight: 44).accessibilityIdentifier("case.import")
                                    Button("Eigenes Dokument ansehen") { showsDocuments = true }.frame(minHeight: 44)
                                }
                                preparation(progress)
                            }
                        }
                        if importTask != nil { ProgressView() }
                        if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }.scrollDismissesKeyboard(.interactively)
                    .task(id: progress?.history.last?.id) {
                        // Wait for the new bubble to enter layout; show its beginning,
                        // rather than skipping over it to the end of a long checklist.
                        await Task.yield()
                        guard !Task.isCancelled, let id = progress?.history.last?.id else { return }
                        proxy.scrollTo(id, anchor: .top)
                    }
            }
            if progress?.finished != true || progress.map({ $0.preparation?.nextQuestion(for: $0) != nil }) == true {
                Divider()
                HStack {
                    TextField("Schreib Sovi …", text: $text, axis: .vertical).lineLimit(1...3).focused($composerFocused).padding(12)
                        .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("scenario.composer")
                    Button { answer(text) } label: { Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Nachricht senden").accessibilityIdentifier("scenario.send")
                }.padding(12)
            }
        }.background(SoviTheme.background).foregroundStyle(SoviTheme.ink)
            .environment(\.locale, Locale(identifier: language.rawValue))
            .environment(\.layoutDirection, progress?.replyLanguage == .ar ? .rightToLeft : .leftToRight)
            .task { do { try store.perform(.startScenario(scenario, language: ChatLanguage(rawValue: chat.responseLanguage))) } catch { self.error = error.localizedDescription } }
            .onDisappear { device.stopAudio(); importTask?.cancel() }
            .sheet(isPresented: $showsForms) { FormLibrarySheet(suggestedFormID: progress?.suggestedForm, requiresPersonSelection: scenario == .care, caseScenario: scenario).environment(\.locale, Locale(identifier: language.rawValue)) }
            .sheet(isPresented: $showsDocuments) { DocumentReviewSheet(onChooseForCase: { id in
                do { try store.perform(.useCaseDocument(id)); showsDocuments = false }
                catch { self.error = error.localizedDescription }
            }) }
            .sheet(isPresented: $showsNearby) { if let query = nearbyQuery { NearbyServiceSheet(query: query, language: language) } }
            .fileImporter(isPresented: $importsLetter, allowedContentTypes: [.pdf, .plainText, .image]) { result in
                do { useLetter(try result.get()) } catch { self.error = error.localizedDescription }
            }
    }
    @ViewBuilder private func preparation(_ progress: DemoScenarioProgress) -> some View {
        if [.care, .hospital].contains(scenario), progress.finished || progress.preparation?.sourceDocumentID != nil {
            CasePreparationView(progress: progress, openForms: { showsForms = true }, openDocuments: { showsDocuments = true })
        }
    }
    private func answer(_ text: String) {
        composerFocused = false
        if scenario == .hospital, progress?.answers.isEmpty == true, text == progress?.choices.first {
            do { useLetter(try CaseDocumentImport.sampleURL()) } catch { self.error = error.localizedDescription }
            return
        }
        do {
            guard let progress else { return }
            if let question = progress.preparation?.nextQuestion(for: progress) {
                guard let id = question.answerID(text) else {
                    throw SoviError.invalidInput(progress.replyLanguage.text("Bitte wähle eine der Möglichkeiten."))
                }
                try store.perform(.answerCaseQuestion(question.key, id))
            } else if scenario == .hospital && progress.answers.isEmpty {
                let document = try store.importText(text, title: progress.replyLanguage.text("Auszug aus meinem Brief"))
                try store.perform(.useCaseDocument(document.id))
            } else {
                try store.perform(.answerScenario(scenario, text))
            }
            self.text = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func useLetter(_ url: URL) {
        guard importTask == nil else { return }
        let epoch = store.state.fixtureEpoch
        importTask = Task { @MainActor in
            defer { importTask = nil }
            let read = Task.detached(priority: .userInitiated) { try CaseDocumentImport.read(url) }
            do {
                let input = try await withTaskCancellationHandler { try await read.value } onCancel: { read.cancel() }
                try Task.checkCancellation()
                guard store.state.fixtureEpoch == epoch else { throw SoviError.staleProposal }
                let document = try store.importText(input.text, title: url.lastPathComponent, pdfData: input.pdf, pageSpans: input.pageSpans)
                try store.perform(.useCaseDocument(document.id))
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
    private func canSave(_ progress: DemoScenarioProgress) -> Bool {
        if scenario == .care { return progress.preparation?.nextQuestion(for: progress) == nil }
        if scenario == .hospital { return progress.preparation?.recommendations.contains(where: \.reviewed) == true }
        return true
    }
    private var nearbyQuery: String? {
        guard let progress, progress.finished else { return nil }
        if scenario == .health && progress.answers.first == "prevention" { return "Allgemeinmedizin" }
        if scenario == .child && progress.answers.last == "prevention" { return "Kinderarzt" }
        if scenario == .hospital && progress.answers.first?.lowercased().contains("rehab") == true { return "Rehabilitationszentrum" }
        return nil
    }
}

private struct NearbyServiceSheet: View {
    let query: String
    let language: ChatLanguage
    @Environment(LiveChatController.self) private var chat
    @State private var place = ""
    @State private var items: [MKMapItem] = []
    @State private var busy = false
    @State private var notice: String?
    @State private var search: MKLocalSearch?
    @State private var searchTask: Task<Void, Never>?
    var body: some View {
        SheetPage(title: "Anlaufstellen") {
            Text("Kontakttreffer aus Apple Karten. Leistungen, Eignung, Termine und Versicherungsverträge bitte direkt bestätigen.").font(.caption)
            TextField("Anderer Ort oder Postleitzahl", text: $place).textFieldStyle(.roundedBorder)
            Button(place.isEmpty ? "An meinem Standort suchen" : "An diesem Ort suchen") { find() }.buttonStyle(SheetPrimaryButtonStyle()).disabled(busy)
            if busy { ProgressView() }
            if let notice { Text(notice).font(.subheadline) }
            if !items.isEmpty {
                Map {
                    ForEach(items.indices, id: \.self) { index in
                        Marker(items[index].name ?? query, coordinate: items[index].placemark.coordinate)
                    }
                }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityLabel("Karte mit Anlaufstellen")
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.name ?? query).font(.headline)
                        Text(item.placemark.title ?? "").font(.subheadline)
                        Button("In Karten öffnen") { item.openInMaps() }.frame(minHeight: 44)
                    }
                }
            }
        }.onDisappear { searchTask?.cancel(); search?.cancel() }
    }
    private func find() {
        busy = true; notice = nil; items = []
        searchTask = Task { @MainActor in
            let request = MKLocalSearch.Request()
            let namedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
            if namedPlace.isEmpty {
                guard let gps = await chat.currentServiceLocation() else {
                    notice = language.localized("Kein aktueller Standort verfügbar. Bitte einen Ort eingeben oder den Standort in den Einstellungen erlauben.")
                    busy = false; return
                }
                guard !Task.isCancelled else { return }
                request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: gps.latitude, longitude: gps.longitude), latitudinalMeters: 12000, longitudinalMeters: 12000)
            }
            request.naturalLanguageQuery = query + (namedPlace.isEmpty ? "" : " " + namedPlace)
            let operation = MKLocalSearch(request: request); search = operation
            do {
                let response = try await operation.start()
                guard !Task.isCancelled else { return }
                items = Array(response.mapItems.prefix(3))
                if items.isEmpty { notice = language.localized("Keine Treffer. Versuche einen anderen Ort.") }
            } catch { notice = language.localized("Die Kartensuche ist gerade nicht verfügbar. Bitte später erneut versuchen.") }
            busy = false; search = nil
        }
    }
}
