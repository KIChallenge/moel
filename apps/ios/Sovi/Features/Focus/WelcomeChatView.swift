import SwiftUI
import MapKit

struct WelcomeChatView: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var device
    @Environment(LiveChatController.self) private var chat
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var delivery = ChatDelivery()
    @State private var text = ""
    @State private var error: String?
    @State private var showsProfile = false
    @State private var showsTerms = false
    @State private var showsBirthDate = false
    @State private var viewedCardPhoto: ConversationTurn?
    @State private var editedCardFields: [PersonField: String] = [:]
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var requestingPermission = false
    @State private var addressSearch = WelcomeAddressSearch()
    @State private var addressTask: Task<Void, Never>?
    @State private var viewportHeight = 0
    @FocusState private var focused: Bool

    private var progress: WelcomeProgress? { store.state.welcome }
    private var field: PersonField? { progress?.field }
    private var person: FormPerson? {
        store.state.formPeople?.first { $0.id == progress?.personID }
    }
    private var cardFields: Set<PersonField> {
        guard let progress, let person else { return [] }
        return Set(progress.remainingECardFields(for: person))
    }
    private var cardReviewID: UUID? {
        guard let scan = progress?.eCardScan, scan.nextSide == nil else { return nil }
        return scan.id
    }
    private var cardAnswers: [PersonField: String] {
        editedCardFields.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.value.isEmpty }
    }
    private var busy: Bool { requestingPermission || addressSearch.resolving }
    private var timeline: ChatTimeline { ChatTimeline(turns: (progress?.displayHistory ?? []).map(ChatTurnKey.init)) }
    private var writingID: String? { delivery.writingID(timeline) }
    private var questionVisible: Bool {
        guard delivery.expanding == nil, let last = progress?.history.last else { return false }
        return delivery.visible.contains(last.id.uuidString)
    }
    private var usesTextInput: Bool { progress?.eCardScan == nil && field != nil && field != .birthDate && progress?.completed != true }
    private var inputError: String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if progress?.isAddressStep == true {
            do { _ = try WelcomeAddress(manual: text); return nil }
            catch { return error.localizedDescription }
        }
        return field?.validate(text)
    }
    private var canSend: Bool { questionVisible && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && inputError == nil && !busy }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            conversation
            if questionVisible, let id = cardReviewID {
                Button(WelcomeReply.confirmCard.text) {
                    do { try eCardAction(.confirm(id, cardAnswers)) } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(SheetPrimaryButtonStyle())
                .disabled(cardAnswers.isEmpty || cardAnswers.contains { $0.key.validate($0.value) != nil })
                .accessibilityIdentifier("welcome.ecard.confirm")
                .padding(.horizontal, 16).padding(.vertical, 6)
            }
            if usesTextInput {
                // Keep the keyboard mounted between name questions as the new bubble arrives.
                composer.opacity(questionVisible ? 1 : 0).allowsHitTesting(questionVisible).accessibilityHidden(!questionVisible)
            }
            if questionVisible && progress?.eCardScan == nil && field != nil && progress?.completed != true {
                Button { answer(nil) } label: {
                    Text("Überspringen").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.disabled(busy).accessibilityIdentifier("welcome.skip").accessibilityValue(field?.title ?? "")
            }
        }
        .background(SoviTheme.background).foregroundStyle(SoviTheme.ink)
        .interactiveDismissDisabled(progress?.completed != true)
        .onAppear {
            delivery.restore(timeline.turns)
            do { try store.perform(.startWelcome) } catch { self.error = error.localizedDescription }
        }
        .task(id: timeline) { await delivery.present(timeline, reduceMotion: reduceMotion) }
        .onChange(of: cardReviewID, initial: true) { _, id in
            if id != nil, let scan = progress?.eCardScan {
                editedCardFields = scan.recognized.filter { cardFields.contains($0.key) }
            } else { editedCardFields = [:] }
        }
        .onChange(of: text) { _, value in
            error = nil
            if progress?.isAddressStep == true { addressTask?.cancel(); addressSearch.update(value) }
        }
        .onDisappear { device.stopAudio(); addressTask?.cancel(); addressSearch.cancel() }
        .sheet(isPresented: $showsProfile) {
            if let id = progress?.personID, let person = store.state.formPeople?.first(where: { $0.id == id }) { FormPersonEditor(person: person) }
        }
        .sheet(isPresented: $showsTerms) { WelcomeTermsSheet() }
        .sheet(isPresented: $showsBirthDate) { birthDateSheet }
        .sheet(item: $viewedCardPhoto) { turn in
            if let photo = turn.eCardPhoto { WelcomeCardPhotoSheet(photo: photo) }
        }
    }

    private var header: some View {
        HStack {
            SoviMascot(size: 46).accessibilityHidden(true)
            Text(textSize.isAccessibilitySize ? "Sovi" : String(localized: "Willkommen bei Sovi")).font(.headline)
            Spacer()
            Button {
                if progress?.completed != true { answer(nil, finish: true) }
                else { dismiss() }
            } label: {
                if textSize.isAccessibilitySize { Image(systemName: "xmark").frame(width: 44, height: 44) }
                else { Text(LocalizedStringKey(progress?.completed == true ? "Schließen" : "Später")) }
            }.frame(minHeight: 44).disabled(busy).accessibilityIdentifier("welcome.later")
                .accessibilityLabel(Text(LocalizedStringKey(progress?.completed == true ? "Schließen" : "Später")))
        }.padding(16)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach((progress?.displayHistory ?? []).filter { delivery.displays($0.id.uuidString, writingID: writingID) }) { turn in
                        VStack(alignment: .leading, spacing: 8) {
                            if let photo = turn.eCardPhoto {
                                WelcomeECardPhotoBubble(photo: photo) { viewedCardPhoto = turn }
                            } else {
                                SoviChatBubble(text: turn.text, isUser: turn.role == "user", isWriting: !delivery.visible.contains(turn.id.uuidString),
                                               read: turn.role == "assistant" ? { device.speak(turn.text, enabled: true) } : nil)
                            }
                            if turn.id == progress?.termsMessageID, delivery.visible.contains(turn.id.uuidString), delivery.expanding != turn.id.uuidString {
                                Button { showsTerms = true } label: {
                                    Label("Nutzungsbedingungen", systemImage: "doc.text").frame(minHeight: 44)
                                }.accessibilityIdentifier("welcome.terms").accessibilityAddTraits(.isLink)
                            }
                        }.id(turn.id).transition(.chatMessage)
                    }
                    if questionVisible {
                        controls
                        if progress?.isAddressStep == true { addressSuggestions }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.subheadline).accessibilityIdentifier("welcome.error") }
                }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(progress?.eCardScan == nil ? .interactively : .immediately)
            .accessibilityIdentifier("welcome.scroll")
            .onGeometryChange(for: Int.self, of: { Int($0.size.height.rounded()) }) { viewportHeight = $0 }
            .task(id: WelcomeScrollTarget(messageID: progress?.history.last(where: { delivery.visible.contains($0.id.uuidString) })?.id, writingID: writingID ?? delivery.expanding, height: progress?.eCardScan == nil ? viewportHeight : 0, suggestions: addressSearch.results.count)) {
                await Task.yield()
                guard !Task.isCancelled, let history = progress?.history, let latest = history.last else { return }
                if let writing = writingID ?? delivery.expanding, let id = UUID(uuidString: writing) {
                    proxy.scrollTo(id, anchor: .bottom); return
                }
                let anchor = history.suffix(2).first { $0.eCardPhoto != nil } ?? latest
                proxy.scrollTo(anchor.id, anchor: .top)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        if let scan = progress?.eCardScan {
            WelcomeECardScan(draft: scan, reviewFields: $editedCardFields, perform: eCardAction).id(scan.id)
        } else {
            questionControls
        }
    }

    private func eCardAction(_ action: WelcomeECardAction) throws {
        let previousStep = progress?.step
        do { try store.perform(.welcomeECard(action)) }
        catch { store.errorMessage = nil; throw error }
        if progress?.step != previousStep { didAnswer() }
        error = nil
    }

    @ViewBuilder private var questionControls: some View {
        if let field, cardFields.contains(field) {
            Button {
                focused = false
                do { try eCardAction(.start) } catch { self.error = error.localizedDescription }
            } label: {
                Label("e-card scannen", systemImage: "camera")
                    .font(.headline).padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .soviGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier("welcome.scanECard")
        }
        if progress?.completed == true {
            Button("Angaben prüfen") { showsProfile = true }.buttonStyle(SheetPrimaryButtonStyle())
            Button("Los geht’s") { dismiss() }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("welcome.done")
        } else if progress?.isGreetingStep == true {
            Button("Hi") { answer(String(localized: "Hi")) }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("welcome.hi")
        } else if progress?.isTermsStep == true {
            Button("Akzeptieren") { answer(String(localized: "Akzeptieren")) }
                .buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("welcome.accept")
        } else if field == .birthDate {
            Button { focused = false; showsBirthDate = true } label: {
                if textSize.isAccessibilitySize { Text("Geburtsdatum auswählen") }
                else { Label("Geburtsdatum auswählen", systemImage: "calendar") }
            }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("welcome.birthDate")
        } else if progress?.isLocationStep == true {
            Button(WelcomeReply.useLocation.text) { requestLocation() }.buttonStyle(SheetPrimaryButtonStyle()).disabled(busy).accessibilityIdentifier("welcome.location")
            Button(WelcomeReply.enterPlace.text) {
                do {
                    try chat.setLocationSharing(false)
                    answer(WelcomeReply.enterPlace.text)
                } catch { self.error = error.localizedDescription }
            }.frame(minHeight: 44).disabled(busy).accessibilityIdentifier("welcome.skipLocation")
        } else if progress?.isNotificationStep == true {
            Button(WelcomeReply.remindMe.text) { requestNotifications() }.buttonStyle(SheetPrimaryButtonStyle()).disabled(busy).accessibilityIdentifier("welcome.notifications")
            Button(WelcomeReply.noReminders.text) {
                do {
                    try store.perform(.setPreferences(notifications: false, spokenReplies: nil, straightPath: nil))
                    Task { await device.cancelAllNotifications() }
                    answer(WelcomeReply.noReminders.text)
                } catch { self.error = error.localizedDescription }
            }.frame(minHeight: 44).disabled(busy).accessibilityIdentifier("welcome.skipNotifications")
        } else if field == .insurer {
            ForEach(["ÖGK", "SVS", "BVAEB", "KFA"], id: \.self) { value in
                Button(value) { answer(value) }.buttonStyle(SheetPrimaryButtonStyle())
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = inputError, [.phone, .email, .insuranceNumber].contains(field) {
                Text(hint).font(.caption).foregroundStyle(SoviTheme.secondary).accessibilityIdentifier("welcome.validation")
            }
            HStack(alignment: .center, spacing: 8) {
                inputField.padding(12).background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityLabel(field?.title ?? String(localized: "Deine Antwort"))
                .accessibilityIdentifier("welcome.composer")
                // Keep the keyboard in place between the first- and last-name questions.
                .id(keyboardType)
                if field == .insuranceNumber {
                    Text("\(text.count)/10").font(.caption.monospacedDigit()).foregroundStyle(SoviTheme.secondary).accessibilityLabel("\(text.count) von 10 Ziffern")
                }
                Button { if canSend { answer(text) } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44)
                }.disabled(!canSend).accessibilityLabel("Nachricht senden").accessibilityIdentifier("welcome.send")
            }
        }.padding(.horizontal, 16).padding(.top, 8)
    }

    @ViewBuilder private var inputField: some View {
        if field == .insuranceNumber {
            WelcomeInsuranceInput(text: inputBinding(step: progress?.step))
                .frame(minHeight: 32)
        } else {
            TextField(placeholder, text: inputBinding(step: progress?.step))
                .focused($focused).autocorrectionDisabled().submitLabel(.send)
                .keyboardType(keyboardType).textContentType(contentType)
                .textInputAutocapitalization([.email, .phone].contains(field) ? .never : .words)
                .onSubmit { if canSend { answer(text) } }
        }
    }

    private func inputBinding(step: Int?) -> Binding<String> {
        Binding(get: { text }, set: { value in
            // A disappearing keyboard must not put the previous answer into the next field.
            guard progress?.step == step, questionVisible else { return }
            text = value
        })
    }

    @ViewBuilder private var addressSuggestions: some View {
        VStack(alignment: .leading, spacing: 4) {
            if addressSearch.resolving { ProgressView().accessibilityLabel("Adresse wird gesucht") }
            ForEach(Array(addressSearch.results.prefix(textSize.isAccessibilitySize ? 1 : 2).enumerated()), id: \.offset) { index, result in
                Button { chooseAddress(result) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text(result.subtitle).font(.caption).foregroundStyle(SoviTheme.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left").font(.caption)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("welcome.address.\(index)")
            }
            if addressSearch.unavailable {
                Text("Gib Straße, Hausnummer, PLZ und Ort ein.")
                    .font(.caption).foregroundStyle(SoviTheme.secondary)
            }
        }
    }

    private var placeholder: String {
        if progress?.isAddressStep == true { return String(localized: "Straße Hausnummer, PLZ Ort") }
        if field == .insuranceNumber { return String(localized: "10 Ziffern") }
        return field?.title ?? String(localized: "Deine Antwort")
    }
    private var keyboardType: UIKeyboardType {
        switch field {
        case .email: .emailAddress
        case .phone: .phonePad
        case .insuranceNumber, .postcode: .numberPad
        default: .default
        }
    }
    private var contentType: UITextContentType? {
        switch field {
        case .firstName: .givenName
        case .lastName: .familyName
        case .phone: .telephoneNumber
        case .email: .emailAddress
        case .street: .fullStreetAddress
        default: nil
        }
    }

    private var birthDateSheet: some View {
        SheetPage(title: "Geburtsdatum", closeIdentifier: "welcome.date.close", startsCompact: true) {
            DatePicker("Geburtsdatum", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden().accessibilityIdentifier("welcome.date.picker")
            Button("Übernehmen") {
                answer(WelcomeProgress.birthDateFormatter.string(from: birthDate)); showsBirthDate = false
            }.buttonStyle(SheetPrimaryButtonStyle()).accessibilityIdentifier("welcome.date.confirm")
        }.environment(\.calendar, Calendar(identifier: .gregorian)).environment(\.timeZone, TimeZone.current)
    }

    private func answer(_ value: String?, finish: Bool = false, permissionUnavailable: Bool = false) {
        guard finish || questionVisible else { return }
        do {
            try store.perform(.answerWelcome(value, finish: finish, permissionUnavailable: permissionUnavailable))
            didAnswer()
            if finish { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
    private func didAnswer() {
        text = ""; error = nil
        focused = focused && usesTextInput && field != .insurer
        addressSearch.cancel()
        device.stopAudio()
    }
    private func chooseAddress(_ completion: MKLocalSearchCompletion) {
        focused = false
        addressTask?.cancel()
        addressTask = Task { @MainActor in
            do {
                let address = try await addressSearch.resolve(completion)
                guard !Task.isCancelled, progress?.isAddressStep == true else { return }
                try store.perform(.answerWelcomeAddress(address))
                didAnswer()
            } catch {
                guard !Task.isCancelled else { return }
                self.error = String(localized: "Bitte ergänze Straße, Hausnummer, PLZ und Ort.")
            }
        }
    }
    private func requestLocation() {
        requestingPermission = true
        Task { @MainActor in
            do {
                let allowed = try await chat.enableLocationFromWelcome()
                answer(WelcomeReply.useLocation.text, permissionUnavailable: !allowed)
            } catch { self.error = error.localizedDescription }
            requestingPermission = false
        }
    }
    private func requestNotifications() {
        requestingPermission = true
        Task { @MainActor in
            let allowed = await device.requestNotifications()
            if !allowed { device.errorMessage = nil }
            do {
                try store.perform(.setPreferences(notifications: allowed, spokenReplies: nil, straightPath: nil))
                answer(WelcomeReply.remindMe.text, permissionUnavailable: !allowed)
                await device.reconcileNotifications(state: store.state)
            } catch { self.error = error.localizedDescription }
            requestingPermission = false
        }
    }
}

private struct WelcomeScrollTarget: Equatable {
    var messageID: UUID?
    var writingID: String?
    var height: Int
    var suggestions: Int
}

/// Rejects extra characters before UIKit displays them, including pasted text.
private struct WelcomeInsuranceInput: UIViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.placeholder = String(localized: "10 Ziffern")
        field.accessibilityLabel = String(localized: "Sozialversicherungsnummer")
        field.accessibilityIdentifier = "welcome.composer"
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 180, height: max(32, (uiView.font?.lineHeight ?? 24) + 8))
    }
    @MainActor final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: WelcomeInsuranceInput
        init(_ parent: WelcomeInsuranceInput) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = field.text ?? ""
            guard let range = Range(range, in: current) else { return false }
            let proposed = current.replacingCharacters(in: range, with: string)
            let digits = String(proposed.filter { $0.isASCII && $0.isNumber }.prefix(10))
            guard proposed == digits else {
                field.text = digits; parent.text = digits
                return false
            }
            return true
        }
    }
}

@MainActor @Observable
private final class WelcomeAddressSearch: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    var resolving = false
    var unavailable = false
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var search: MKLocalSearch?
    @ObservationIgnored private var generation = UUID()
    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 47.6, longitude: 14.1), latitudinalMeters: 600000, longitudinalMeters: 600000)
    }
    func update(_ text: String) {
        search?.cancel(); search = nil; resolving = false; generation = UUID()
        results = []; unavailable = false
        completer.queryFragment = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if completer.queryFragment.isEmpty { completer.cancel() }
    }
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor [weak self] in
            guard let self, !self.completer.queryFragment.isEmpty else { return }
            self.results = Array(self.completer.results.prefix(3)); self.unavailable = false
        }
    }
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.completer.queryFragment.isEmpty else { return }
            self.results = []; self.unavailable = true
        }
    }
    func resolve(_ completion: MKLocalSearchCompletion) async throws -> WelcomeAddress {
        resolving = true
        let requestID = UUID(); generation = requestID
        let operation = MKLocalSearch(request: MKLocalSearch.Request(completion: completion)); search = operation
        defer { if generation == requestID { resolving = false; search = nil } }
        let response = try await operation.start()
        try Task.checkCancellation()
        guard generation == requestID, let place = response.mapItems.first?.placemark else { throw CancellationError() }
        let address = WelcomeAddress(street: place.thoroughfare ?? "", house: place.subThoroughfare ?? "", postcode: place.postalCode ?? "", city: place.locality ?? place.subAdministrativeArea ?? "", country: place.country ?? "")
        try address.validate()
        return address
    }
    func cancel() {
        generation = UUID(); search?.cancel(); search = nil; completer.cancel(); completer.queryFragment = ""
        results = []; resolving = false
    }
}

struct WelcomeTermsSheet: View {
    var body: some View {
        SheetPage(title: "Nutzungsbedingungen", closeIdentifier: "welcome.terms.close", startsCompact: true) {
            Text("Sovi hilft dir, Anlaufstellen zu finden und Formulare vorzubereiten. Medizinische Fragen besprichst du mit Fachpersonal.")
            Text("Profil, e-card-Fotos und Dokumente bleiben auf deinem Gerät. Unter „Deine Daten“ kannst du sie löschen.")
            Text("Chatnachrichten und von dir geteilte Einträge verarbeitet OpenAI über Sovi. Deine Adresssuche geht an Apple. Standort und Mitteilungen sind freiwillig.")
        }.accessibilityIdentifier("welcome.terms.document")
    }
}
