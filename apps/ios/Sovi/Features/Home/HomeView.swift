import SwiftUI
import UniformTypeIdentifiers

private enum ActiveSheet: Identifiable, Equatable {
    case node(UUID), documents, editor(NodeKind), draft, preparation(LifeDraftKind), controls, chatBackground, forms
    case scenario(DemoScenario, restoredTurnCount: Int)
    case matchedForm(String, ChatLanguage)
    case reviewDocument(UUID)
    var id: String {
        switch self {
        case .node(let id): "node-\(id)"
        case .documents: "documents"
        case .reviewDocument(let id): "document-" + id.uuidString
        case .editor(let kind): "editor-\(kind.rawValue)"
        case .draft: "draft"
        case .preparation(let kind): "preparation-\(kind.rawValue)"
        case .controls: "controls"
        case .chatBackground: "chat-background"
        case .forms: "forms"
        case .matchedForm(let id, let language): "form-" + language.rawValue + id
        case .scenario(let scenario, _): "scenario-" + scenario.rawValue
        }
    }
}

struct HomeView: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var device
    @Environment(LiveChatController.self) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isFocused = false
    @State private var restoredFocusTurns = 0
    @State private var contextID: UUID?
    @State private var activeSheet: ActiveSheet?
    @State private var showsAttachmentPicker = false
    @State private var attachmentTask: Task<Void, Never>?
    @State private var requestedPathEntryID: UUID?
    @State private var pendingFocus: UUID?
    @State private var lastMessage: String?
    @State private var showsWelcome = false
    @State private var showsLocalCaseResponse = false
    @State private var conversationLanguage: ChatLanguage = .app
    @State private var response = CompanionResponse(text: String(localized: "Wie kann ich dir helfen?"))
    private var service: any CompanionService { DemoCompanionService(preference: chat.responseLanguage) }

    var body: some View {
        ZStack {
            SoviTheme.background.ignoresSafeArea()
            RouteView(requestedEntryID: $requestedPathEntryID, isFocused: isFocused, openDetails: { activeSheet = .node($0) }, askSovi: { openFocus($0) },
                      openSovi: { openFocus($0.contextID, invitation: $0.text) }, openControls: { activeSheet = .controls })
                .id(store.state.fixtureEpoch)
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .opacity(isFocused ? 0.10 : 1)
                .allowsHitTesting(!isFocused)
                .accessibilityHidden(isFocused || showsWelcome)
            if isFocused {
                SoviFocusView(contextID: $contextID, response: response, restoredTurnCount: restoredFocusTurns, language: conversationLanguage,
                              close: closeFocus, send: send, act: handleAction,
                              attach: { showsAttachmentPicker = true }, attachSample: attachExample,
                              importingDocument: attachmentTask != nil, cancelImport: { attachmentTask?.cancel() },
                              leaveDocument: leaveDocument, showEvent: { id in closeFocus(); requestedPathEntryID = id },
                              shareBackground: { activeSheet = .chatBackground },
                              forms: { activeSheet = .forms }, scenario: openScenario, localCaseResponse: showsLocalCaseResponse)
                    .transition(.identity)
                    .zIndex(1)
            }
        }
        .fileImporter(isPresented: $showsAttachmentPicker, allowedContentTypes: [.pdf, .plainText, .image],
                      allowsMultipleSelection: false) { result in
            do {
                if let url = try result.get().first { importAttachment(url) }
            } catch let error as CocoaError where error.code == .userCancelled { return }
            catch { store.errorMessage = error.localizedDescription }
        }
        .sheet(item: $activeSheet, onDismiss: {
            if let id = pendingFocus {
                pendingFocus = nil
                openFocus(id)
            }
        }) { sheet in
            Group {
                switch sheet {
                case .node(let id):
                    NodePreviewSheet(nodeID: id) { nodeID in
                        pendingFocus = nodeID
                        activeSheet = nil
                    }
                case .documents: documentSheet(nil)
                case .reviewDocument(let id): documentSheet(id)
                case .editor(let kind): NodeEditorSheet(kind: kind)
                case .draft: AdministrativeDraftSheet()
                case .preparation(let kind): LifePreparationSheet(kind: kind)
                case .controls: LocalControlsSheet()
                case .chatBackground: ChatBackgroundSheet()
                case .forms: FormLibrarySheet()
                case .matchedForm(let id, let language):
                    FormLibrarySheet(suggestedFormID: id, requiresPersonSelection: true)
                        .environment(\.locale, Locale(identifier: language.rawValue))
                case .scenario(let scenario, let count): DemoScenarioChat(scenario: scenario, restoredTurnCount: count)
                }
            }
            .environment(store)
            .environment(device)
            .environment(chat)
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsWelcome) { WelcomeChatView().environment(store).environment(device).environment(chat) }
        .alert("Hinweis", isPresented: Binding(get: {
            activeSheet == nil && (store.errorMessage != nil || device.errorMessage != nil)
        }, set: { if !$0 { store.errorMessage = nil; device.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil; device.errorMessage = nil }
        } message: { Text(store.errorMessage ?? device.errorMessage ?? "") }
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if store.state.welcome?.completed != true && (!arguments.contains("--uitesting") || arguments.contains("--welcome")) { showsWelcome = true }
            await device.refreshNotificationStatus(); await device.reconcileNotifications(state: store.state)
        }
        .onChange(of: store.state) { old, new in
            if old.fixtureEpoch != new.fixtureEpoch {
                attachmentTask?.cancel()
                requestedPathEntryID = nil
                chat.setBackground([]); chat.reset()
                device.stopAudio()
                device.cleanupExports()
                isFocused = false
                activeSheet = nil
                contextID = nil
                response = CompanionResponse(text: String(localized: "Dein Weg ist leer."))
                showsLocalCaseResponse = false
            }
            if isFocused, old.appointments != new.appointments, let id = response.attendanceQuestionID, let node = store.node(id: id) {
                let entry = DemoCompanionService.entryResponse(for: node, state: new, now: store.now, language: conversationLanguage)
                if entry.attendanceQuestionID != nil && entry.text != response.text { beginCheckIn(entry) }
                else { response = entry }
            } else if isFocused, let lastMessage, old.nodes != new.nodes || old.schedules != new.schedules || old.appointments != new.appointments
                || (showsLocalCaseResponse && (old.demoScenarios != new.demoScenarios || old.formPeople != new.formPeople || old.formDrafts != new.formDrafts)) {
                let refreshed = service.respond(to: lastMessage, context: contextID, state: new, now: store.now)
                if refreshed.attendanceQuestionID == nil { response = refreshed }
            }
            if old.schedules != new.schedules || old.appointments != new.appointments || old.uniqueOpenTasks != new.uniqueOpenTasks || old.notificationsEnabled != new.notificationsEnabled {
                Task { await device.reconcileNotifications(state: new) }
            }
        }
        .onChange(of: device.notificationNodeID, initial: true) { _, id in
            if let id, store.node(id: id) != nil {
                activeSheet = .node(id)
                device.notificationNodeID = nil
            }
        }
        .onChange(of: contextID) { _, id in
            if store.state.focusContextID != id {
                do { try store.perform(.setFocusContext(id)) } catch { store.errorMessage = error.localizedDescription }
                if id == nil, isFocused, !showsLocalCaseResponse || response.attendanceQuestionID != nil {
                    let overview = conversationLanguage.text("Was steht als Nächstes an?")
                    lastMessage = overview
                    response = DemoCompanionService.progressResponse(to: overview, context: nil, state: store.state, now: store.now, language: conversationLanguage)
                        ?? service.respond(to: overview, context: nil, state: store.state, now: store.now)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { device.stopAudio(); chat.cancel() }
        }
    }

    private func openFocus(_ id: UUID?, invitation: String? = nil) {
        if !isFocused { restoredFocusTurns = store.state.conversation.count }
        conversationLanguage = documentLanguage
        if invitation == nil, id != nil, store.state.discussedDocumentID != nil { try? store.perform(.leaveDocumentDiscussion) }
        if let id, let node = store.node(id: id) {
            let entry = DemoCompanionService.entryResponse(for: node, state: store.state, now: store.now, language: conversationLanguage)
            if entry.attendanceQuestionID != nil {
                beginCheckIn(entry)
                if !isFocused { withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.05)) { isFocused = true } }
                return
            }
            if isFocused {
                showsLocalCaseResponse = true
                lastMessage = nil
                response = entry
                contextID = id
                return
            }
        }
        guard !isFocused else { contextID = id; return }
        let resumesLocal = invitation != nil && !store.state.conversation.isEmpty
            && (store.state.focusContextID != nil || store.state.discussedDocumentID != nil || showsLocalCaseResponse || !chat.enabled || chat.displayMessages.isEmpty)
        let resumesOnline = invitation != nil && !resumesLocal && chat.enabled && (!chat.displayMessages.isEmpty || chat.error != nil)
        showsLocalCaseResponse = resumesLocal && chat.enabled
        let resolved = resumesOnline ? nil : resumesLocal ? store.state.focusContextID : invitation == nil ? (id ?? store.state.focusContextID) : id
        contextID = resolved
        try? store.perform(.setFocusContext(resolved))
        if resumesOnline {
            lastMessage = nil
        } else if resumesLocal, let last = store.state.conversation.last(where: { $0.role == "assistant" }) {
            lastMessage = store.state.conversation.last(where: { $0.role == "user" })?.text
            var restored = lastMessage.map { DemoCompanionService.progressResponse(to: $0, context: resolved, state: store.state, now: store.now)
                ?? service.respond(to: $0, context: resolved, state: store.state, now: store.now) }
                ?? CompanionResponse(text: last.text)
            restored.text = last.text
            if let questionID = last.attendanceQuestionID, let node = store.node(id: questionID) {
                restored = DemoCompanionService.entryResponse(for: node, state: store.state, now: store.now, language: conversationLanguage)
                if restored.attendanceQuestionID != nil { restored.text = last.text }
                lastMessage = nil
            } else if let answerID = store.state.conversation.dropLast().last?.attendanceAnswerID {
                let recorded = store.state.appointments.contains { $0.id == store.node(id: answerID)?.appointmentID && $0.attendance != .unrecorded }
                restored = CompanionResponse(text: last.text, entryIDs: recorded ? [answerID] : [])
                lastMessage = nil
            } else if let id = store.state.discussedDocumentID, store.document(id: id) != nil {
                restored = CompanionResponse(text: last.text, action: .reviewDocument(id))
                lastMessage = nil
            }
            response = restored
        } else if let id = resolved, let node = store.node(id: id) {
            lastMessage = nil
            response = DemoCompanionService.entryResponse(for: node, state: store.state, now: store.now)
            if let invitation { response.text = invitation }
        } else {
            lastMessage = "Was ist noch offen?"
            response = invitation.map { CompanionResponse(text: $0) }
                ?? service.respond(to: "Was ist noch offen?", context: nil, state: store.state, now: store.now)
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.45, bounce: 0.05)) { isFocused = true }
    }

    private func closeFocus() {
        device.stopAudio()
        attachmentTask?.cancel()
        chat.cancel()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.45, bounce: 0.05)) { isFocused = false }
    }

    private var documentLanguage: ChatLanguage {
        let previous = store.state.conversation.last(where: { $0.role == "user" && $0.attachmentDocumentID == nil })?.text ?? ""
        return ChatLanguage.resolve(previous, preference: chat.responseLanguage)
    }

    private func attachExample() {
        guard let url = Bundle.main.url(forResource: "example-imaging-report", withExtension: "txt", subdirectory: "Fixtures") else {
            store.errorMessage = SoviError.missingRecord.localizedDescription
            return
        }
        importAttachment(url)
    }

    private func importAttachment(_ url: URL) {
        guard isFocused, attachmentTask == nil else { return }
        let epoch = store.state.fixtureEpoch
        let language = conversationLanguage
        chat.cancel()
        attachmentTask = Task {
            defer { attachmentTask = nil }
            do {
                let reader = Task.detached(priority: .userInitiated) { try CaseDocumentImport.read(url) }
                let input = try await withTaskCancellationHandler {
                    try await reader.value
                } onCancel: { reader.cancel() }
                try Task.checkCancellation()
                guard isFocused, store.state.fixtureEpoch == epoch else { return }
                let imported = try store.importChatAttachment(input, title: url.lastPathComponent, language: language)
                let privateIDs = Set(imported.eventIDs.map(\.uuidString))
                let background = chat.background.filter { !privateIDs.contains($0.id) }
                if background.count != chat.background.count { chat.setBackground(background) }
                showsLocalCaseResponse = true
                contextID = nil
                lastMessage = nil
                response = CompanionResponse(text: imported.reply, action: .reviewDocument(imported.document.id))
            } catch is CancellationError { return }
            catch { if !Task.isCancelled { store.errorMessage = error.localizedDescription } }
        }
    }

    private func leaveDocument() {
        do {
            try store.perform(.leaveDocumentDiscussion)
            showsLocalCaseResponse = false
            lastMessage = nil
            response = CompanionResponse(text: conversationLanguage.text("Wie kann ich dir helfen?"))
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func documentSheet(_ id: UUID?) -> some View {
        DocumentReviewSheet(initialDocumentID: id, language: documentLanguage, onDiscuss: { document in
            let response = DocumentDiscussion.summary(document, language: documentLanguage, state: store.state)
            recordDocumentReply(.init(documentID: document.id, response: response), question: nil)
        })
    }

    private func recordDocumentReply(_ reply: DocumentDiscussion.Reply, question: String?) {
        do {
            let eventIDs = reply.response.entryIDs.isEmpty ? nil : reply.response.entryIDs
            try store.perform(.discussDocument(documentID: reply.documentID, question: question, reply: reply.response.text, eventIDs: eventIDs))
            chat.cancel()
            showsLocalCaseResponse = true
            contextID = nil
            lastMessage = nil
            response = reply.response
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, attachmentTask == nil else { return }
        if let id = response.attendanceQuestionID, contextID == id, store.state.conversation.last?.attendanceQuestionID == id,
           case .answerCheckIn(_, let attendance) = DemoCompanionService.checkInAnswer(to: message, nodeID: id) {
            answerCheckIn(id, attendance: attendance, answer: message)
            return
        }
        let language = ChatLanguage.resolve(message, preference: chat.responseLanguage)
        conversationLanguage = language
        let documentReply = DocumentDiscussion.reply(to: message, state: store.state, language: language)
        if let id = store.state.discussedDocumentID, contextID == nil, store.document(id: id) != nil {
            if let documentReply, documentReply.documentID == id {
                recordDocumentReply(documentReply, question: message)
                return
            } else {
                // An unrelated question starts ordinary chat. Never forward the
                // document or its local transcript when leaving this context.
                try? store.perform(.leaveDocumentDiscussion)
            }
        }
        if let documentReply {
            recordDocumentReply(documentReply, question: message)
            return
        }
        if let savedCase = DemoCompanionService.savedCaseResponse(to: message, state: store.state, language: language) {
            chat.cancel(); showsLocalCaseResponse = true
            contextID = nil
            do {
                try store.perform(.appendConversation(role: "user", text: message))
                response = savedCase; lastMessage = message
                try store.perform(.appendConversation(role: "assistant", text: savedCase.text))
                try store.perform(.saveComposer(""))
            } catch { store.errorMessage = error.localizedDescription }
            return
        }
        if let progress = DemoCompanionService.progressResponse(to: message, context: contextID, state: store.state, now: store.now, language: language) {
            if progress.attendanceQuestionID != nil {
                beginCheckIn(progress, userMessage: message)
                return
            }
            chat.cancel(); showsLocalCaseResponse = true
            if progress.entryIDs.count != 1 { contextID = nil }
            do {
                try store.perform(.appendConversation(role: "user", text: message))
                response = progress; lastMessage = message
                try store.perform(.appendConversation(role: "assistant", text: progress.text))
                try store.perform(.saveComposer(""))
            } catch { store.errorMessage = error.localizedDescription }
            return
        }
        showsLocalCaseResponse = false
        if let formID = PrototypeForm.requestedID(in: message) {
            chat.cancel()
            showsLocalCaseResponse = true
            let regional = ["fahrtkosten", "senioren-wg", "einrichtungswunsch", "fsw-foerderung"].contains(formID)
            let words = ChatLanguage.normalized(message)
            let explicitRegion = ["wien", "vienna", "viyana", "فيينا", "fsw"].contains(where: words.contains)
            if regional && !explicitRegion {
                do {
                    guard let form = try PrototypeForm.load().first(where: { $0.id == formID }) else { throw SoviError.missingRecord }
                    let reply = language.localized("Für Wien gibt es den Entwurf „\(language.text(form.title))“. Passt Wien zu deinem Antrag?")
                    presentLocalRequest(message, reply: reply, sheet: nil, action: .matchedForm(formID))
                } catch { store.errorMessage = error.localizedDescription }
            } else {
                presentLocalRequest(message, reply: language.text("Wähle die Person für den Entwurf. Ich übernehme ihre gespeicherten Angaben."),
                                    sheet: .matchedForm(formID, language))
            }
            return
        }
        if let scenario = DemoScenario.matching(message) {
            chat.cancel()
            do {
                let restoredCount = store.state.demoScenarios?[scenario.rawValue]?.history.count ?? 0
                try store.perform(.startScenario(scenario, language: language, opening: message))
                let progress = store.state.demoScenarios?[scenario.rawValue]
                let reply = progress?.history.last?.text ?? scenario.title(in: language)
                showsLocalCaseResponse = true
                presentLocalRequest(message, reply: reply, sheet: .scenario(scenario, restoredTurnCount: restoredCount), action: .scenario(scenario))
            } catch { store.errorMessage = error.localizedDescription }
            return
        }
        let normalized = ChatLanguage.normalized(message)
        if ["formular", "forms", "fill a form", "form library", "form doldur", "استمارة", "النماذج"].contains(where: normalized.contains) {
            chat.cancel()
            showsLocalCaseResponse = true
            presentLocalRequest(message, reply: language.text("Wähle eine Person und ein Formular."), sheet: .forms)
            return
        }
        if chat.enabled {
            guard !chat.busy else { return }
            contextID = nil
            try? store.perform(.setFocusContext(nil))
            chat.submit(message)
            try? store.perform(.saveComposer(""))
            return
        }
        do {
            try store.perform(.appendConversation(role: "user", text: message))
            lastMessage = message
            response = service.respond(to: message, context: contextID, state: store.state, now: store.now)
            try store.perform(.appendConversation(role: "assistant", text: response.text))
            try store.perform(.saveComposer(""))
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func openScenario(_ scenario: DemoScenario) {
        do {
            let restoredCount = store.state.demoScenarios?[scenario.rawValue]?.history.count ?? 0
            try store.perform(.startScenario(scenario, language: ChatLanguage(rawValue: chat.responseLanguage) ?? conversationLanguage))
            activeSheet = .scenario(scenario, restoredTurnCount: restoredCount)
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func presentLocalRequest(_ message: String, reply: String, sheet: ActiveSheet?, action: CompanionAction? = nil) {
        do {
            try store.perform(.appendConversation(role: "user", text: message))
            try store.perform(.appendConversation(role: "assistant", text: reply))
            try store.perform(.saveComposer(""))
            response = CompanionResponse(text: reply, action: action)
            contextID = nil
            lastMessage = nil
            activeSheet = sheet
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func handleAction(_ action: CompanionAction) {
        switch action {
        case .documents: activeSheet = .documents
        case .matchedForm(let id): activeSheet = .matchedForm(id, conversationLanguage)
        case .reviewDocument(let id): activeSheet = .reviewDocument(id)
        case .draft: activeSheet = .draft
        case .preparation(let kind): activeSheet = .preparation(kind)
        case .add(let kind): activeSheet = .editor(kind)
        case .preview(let id): activeSheet = .node(id)
        case .controls: activeSheet = .controls
        case .scenario(let scenario): openScenario(scenario)
        case .showProgress:
            let question = conversationLanguage.text("Was steht als Nächstes an?")
            guard let progress = DemoCompanionService.progressResponse(to: question, context: nil, state: store.state, now: store.now, language: conversationLanguage) else { return }
            if progress.attendanceQuestionID != nil { beginCheckIn(progress, userMessage: question); return }
            chat.cancel(); showsLocalCaseResponse = true; lastMessage = question
            contextID = nil
            do {
                try store.perform(.appendConversation(role: "user", text: question))
                try store.perform(.appendConversation(role: "assistant", text: progress.text))
                response = progress
            } catch { store.errorMessage = error.localizedDescription }
        case .reportTask(let id, let status):
            let confirmation = status == .completed ? String(localized: "Als erledigt gespeichert.") : status == .notDone ? String(localized: "Als nicht erledigt gespeichert.") : String(localized: "Wieder offen.")
            recordProgress(nodeID: id, command: .setTask(id, status), answer: action.title, confirmation: confirmation)
        case .reportAttendance(let appointmentID, let attendance):
            guard let node = store.state.nodes.first(where: { $0.appointmentID == appointmentID }) else { return }
            let confirmation = attendance == .attended ? String(localized: "Als teilgenommen gespeichert.") : attendance == .notAttended ? String(localized: "Als nicht teilgenommen gespeichert.") : String(localized: "Die Teilnahme ist wieder offen.")
            recordProgress(nodeID: node.id, command: .recordAttendance(appointmentID, attendance), answer: action.title, confirmation: confirmation)
        case .answerCheckIn(let id, let attendance):
            answerCheckIn(id, attendance: attendance, answer: action.title(in: conversationLanguage))
        }
    }

    private func beginCheckIn(_ question: CompanionResponse, userMessage: String? = nil) {
        guard let nodeID = question.attendanceQuestionID else { return }
        do {
            try store.perform(.beginAttendanceCheckIn(nodeID: nodeID, question: question.text, userMessage: userMessage))
            chat.cancel()
            showsLocalCaseResponse = true
            lastMessage = nil
            contextID = nodeID
            response = question
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func answerCheckIn(_ nodeID: UUID, attendance: Attendance?, answer: String) {
        guard response.attendanceQuestionID == nodeID, contextID == nodeID,
              store.state.conversation.last?.attendanceQuestionID == nodeID else { return }
        let confirmation: String
        switch attendance {
        case .attended: confirmation = conversationLanguage.text("Danke, ich habe deine Teilnahme eingetragen.")
        case .notAttended: confirmation = conversationLanguage.text("Danke, ich habe eingetragen, dass du nicht dort warst.")
        case nil: confirmation = conversationLanguage.text("Okay, ich lasse den Termin offen. Ich frage frühestens morgen wieder.")
        case .unrecorded: return
        }
        do {
            try store.perform(.answerAttendanceCheckIn(nodeID: nodeID, attendance: attendance, answer: answer, confirmation: confirmation))
            lastMessage = nil
            response = CompanionResponse(text: confirmation, entryIDs: attendance == nil ? [] : [nodeID])
            device.stopAudio()
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func recordProgress(nodeID: UUID, command: AppCommand, answer: String, confirmation: String) {
        guard let node = store.node(id: nodeID) else { return }
        do {
            try store.perform(command)
            chat.cancel(); showsLocalCaseResponse = true; lastMessage = nil; contextID = nodeID
            try store.perform(.setFocusContext(nodeID))
            try store.perform(.appendConversation(role: "user", text: "\(answer): \(node.displayTitle)"))
            try store.perform(.appendConversation(role: "assistant", text: confirmation))
            response = CompanionResponse(text: confirmation, entryIDs: response.entryIDs.isEmpty ? [nodeID] : response.entryIDs)
            device.stopAudio()
        } catch { store.errorMessage = error.localizedDescription }
    }
}

private struct RouteSection: Identifiable {
    var id: String
    var title: String
    var stage: String
    var days: [PathDayGroup]
}

struct PathSelectedButtonBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct RouteView: View {
    @Environment(SoviStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var compactSpacing = 112.0
    private let readableSpacing = 220.0
    @Binding var requestedEntryID: UUID?
    var isFocused: Bool
    var openDetails: (UUID) -> Void
    var askSovi: (UUID) -> Void
    var openSovi: (PathCompanionPrompt) -> Void
    var openControls: () -> Void
    @State private var didAnchor = false
    @State private var showsFullHistory = false
    @State private var latestJump = 0
    @State private var selectedDayID: String?
    @State private var selectedEntryID: UUID?
    @AccessibilityFocusState private var focusedDayID: String?

    private var sections: [RouteSection] {
        let days = showsFullHistory ? store.state.pathDays : store.state.compactPathDays
        let known = days.filter { $0.date != nil && !$0.isPlanned }
        var result = Set(known.compactMap(\.year)).sorted().map { year in
            let group = known.filter { $0.year == year }
            return RouteSection(id: "year-\(year)", title: String(year), stage: group.first?.stage ?? "", days: group)
        }
        let planned = days.filter(\.isPlanned)
        if !planned.isEmpty { result.append(RouteSection(id: "planned", title: String(localized: "Ausblick"), stage: "", days: planned)) }
        let undated = days.filter { $0.date == nil && !$0.isPlanned }
        if !undated.isEmpty { result.append(RouteSection(id: "undated", title: String(localized: "Eigene Schritte"), stage: "", days: undated)) }
        return result
    }

    var body: some View {
        let groups = sections
        let days = groups.flatMap(\.days)
        let currentID = store.state.currentPathDayID
        let straight = store.state.straightPath || textSize.isAccessibilitySize
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let referenceDate = store.now
            let prompt = PathCompanionPrompt.make(state: store.state, now: referenceDate, locale: locale)
            VStack(spacing: 0) {
                PathOverviewStrip(appointments: store.state.appointments.filter { $0.status != .cancelled && $0.attendance == .unrecorded && $0.date >= referenceDate }.count,
                                  documents: store.state.documents.count,
                                  vaccinations: store.nodes.filter { $0.vaccination != nil }.count,
                                  tasks: store.state.uniqueOpenTasks.count)
                    .accessibilityHidden(selectedDayID != nil)
                GeometryReader { viewport in
                    ScrollViewReader { reader in
                        VStack(spacing: 0) {
                            navigation(reader, currentID: currentID)
                                .accessibilityHidden(selectedDayID != nil)
                            ScrollView {
                                // Individual rows keep scroll targets and accessibility bounds
                                // aligned with the entries, including in large text.
                                VStack(spacing: 0) {
                                    ForEach(groups) { group in
                                        Text(group.title)
                                            .font(.system(.subheadline, design: .rounded, weight: .heavy))
                                            .foregroundStyle(SoviTheme.secondary)
                                            .padding(.top, 28).padding(.bottom, 20)
                                            .frame(maxWidth: .infinity)
                                            .accessibilityAddTraits(.isHeader)
                                            .accessibilityIdentifier("path.\(group.id)")
                                            .id(group.id)
                                        ForEach(group.days) { day in
                                            PathNodeButton(node: day.displayNode, statusText: statusText(for: day), actionTitle: day.actionBubbleTitle,
                                                           entryCount: day.entryCount, dateIncludesTime: false,
                                                           currentMarker: day.id == currentID ? currentMarker : nil, compact: !straight && day.date != nil,
                                                           progress: day.progress(in: store.state, now: store.now),
                                                           buttonIdentifier: "path.day.\(day.id)", labelTitle: labelTitle(for: day),
                                                           selectionAnchor: selectedDayID == day.id,
                                                           entryProgress: day.entries.map { $0.haloProgress(in: store.state, now: referenceDate) }) {
                                                selectedEntryID = nil
                                                selectedDayID = day.id
                                            }
                                            .accessibilityFocused($focusedDayID, equals: day.id)
                                            .frame(maxWidth: .infinity)
                                            .frame(minHeight: straight ? readableSpacing : compactSpacing)
                                            .offset(x: horizontalOffset(day.id, days: days, currentID: currentID, width: viewport.size.width, straight: straight))
                                            .id(day.id)
                                            if day.id == currentID {
                                                routeCompanion(prompt, width: viewport.size.width, straight: straight)
                                            }
                                        }
                                    }
                                    if store.state.pathDays.count > store.state.compactPathDays.count {
                                        Button { closeCard(); showsFullHistory.toggle() } label: {
                                            Text(LocalizedStringKey(showsFullHistory ? "Kompakter Verlauf" : "Alle Einträge anzeigen"))
                                                .frame(minHeight: 44)
                                        }.accessibilityIdentifier("path.history.toggle")
                                    }
                                    if currentID == nil { routeCompanion(prompt, width: viewport.size.width, straight: straight) }
                                    if days.isEmpty {
                                        Text("Füge mit Sovi deinen ersten Eintrag hinzu.")
                                            .multilineTextAlignment(.center).padding(28)
                                    }
                                }
                                .padding(.bottom, 160)
                                .frame(maxWidth: .infinity)
                                .coordinateSpace(name: "route-content")
                                .background { PathStatusBarScroll(enabled: !isFocused && selectedDayID == nil) { latestJump += 1 } }
                                .overlayPreferenceValue(PathCompanionSlotBounds.self) { anchor in
                                    GeometryReader { geometry in
                                        if let anchor, !isFocused, selectedDayID == nil,
                                           let viewport = geometry.bounds(of: .scrollView(axis: .vertical)),
                                           viewport.height > 0 {
                                            PathCompanionView(prompt: prompt, slot: geometry[anchor], viewport: viewport,
                                                              contentWidth: geometry.size.width) { openSovi(prompt) }
                                        }
                                    }
                                }
                            }
                            .accessibilityIdentifier("path.scroll")
                            .scrollDisabled(selectedDayID != nil)
                            .accessibilityHidden(selectedDayID != nil)
                            .overlayPreferenceValue(PathSelectedButtonBounds.self) { anchor in
                                if let anchor, let day = days.first(where: { $0.id == selectedDayID }) {
                                    GeometryReader { geometry in
                                        PathDayCallout(day: day, selectedEntryID: $selectedEntryID, anchor: geometry[anchor],
                                                       viewport: geometry.size, close: { closeCard(restoreFocus: true) },
                                                       openDetails: { id in closeCard(); openDetails(id) },
                                                       askSovi: { id in closeCard(); askSovi(id) })
                                    }
                                    .id(day.id)
                                }
                            }
                            .onChange(of: latestJump) { _, _ in
                                if let latest = store.state.latestPathDayID { jump(latest, reader: reader) }
                            }
                            .onChange(of: requestedEntryID) { _, id in
                                guard let id, let day = store.state.pathDays.first(where: { $0.entries.contains { $0.id == id } }) else { return }
                                if !days.contains(where: { $0.id == day.id }) {
                                    showsFullHistory = true
                                } else {
                                    showRequestedEntry(id, on: day, reader: reader)
                                }
                            }
                            .onChange(of: showsFullHistory) { _, _ in
                                Task { @MainActor in
                                    await Task.yield()
                                    if let id = requestedEntryID,
                                       let day = store.state.pathDays.first(where: { $0.entries.contains { $0.id == id } }) {
                                        showRequestedEntry(id, on: day, reader: reader)
                                    } else if let latest = store.state.latestPathDayID { jump(latest, reader: reader) }
                                }
                            }
                            .opacity(didAnchor ? 1 : 0)
                            .task {
                                guard !didAnchor else { return }
                                await Task.yield()
                                if let currentID { reader.scrollTo(currentID, anchor: straight ? .center : .top) }
                                didAnchor = true
                            }
                        }
                    }
                }
            }
            .foregroundStyle(SoviTheme.ink)
            .onChange(of: days) { _, updated in
                guard let selectedDayID else { return }
                guard let day = updated.first(where: { $0.id == selectedDayID }) else { closeCard(); return }
                if let selectedEntryID, !day.entries.contains(where: { $0.id == selectedEntryID }) { self.selectedEntryID = nil }
            }
        }
    }

    private func closeCard(restoreFocus: Bool = false) {
        let dayID = selectedDayID
        selectedDayID = nil
        selectedEntryID = nil
        if restoreFocus { focusedDayID = dayID }
    }

    private var currentMarker: String {
        store.state.lifeScenario == nil ? String(localized: "Hier") : String(localized: "Heute")
    }

    private func showRequestedEntry(_ id: UUID, on day: PathDayGroup, reader: ScrollViewProxy) {
        reader.scrollTo(day.id, anchor: .center)
        selectedDayID = day.id
        selectedEntryID = day.entryCount > 1 ? id : nil
        requestedEntryID = nil
    }

    private func navigation(_ reader: ScrollViewProxy, currentID: String?) -> some View {
        Group {
            if textSize.isAccessibilitySize {
                navigationButtons(reader, currentID: currentID).labelStyle(.iconOnly)
                    .font(.system(size: 24, weight: .bold))
            } else { navigationButtons(reader, currentID: currentID) }
        }
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .padding(.horizontal, 20).frame(minHeight: 44)
    }

    private func navigationButtons(_ reader: ScrollViewProxy, currentID: String?) -> some View {
        HStack {
            if let currentID {
                Button { jump(currentID, reader: reader) } label: {
                    Label("Heute", systemImage: "location.fill").padding(.horizontal, 14).frame(minWidth: 44, minHeight: 44)
                        .soviGlass(in: Capsule(), interactive: true)
                }
                    .accessibilityIdentifier("path.today")
            }
            Spacer(minLength: 12)
            Button { closeCard(); openControls() } label: {
                Image(systemName: "gearshape")
                    .frame(width: 44, height: 44)
                    .soviGlass(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Einstellungen")
            .accessibilityIdentifier("path.controls")
        }
        .buttonStyle(.plain)
    }

    private func jump(_ id: String, reader: ScrollViewProxy) {
        closeCard()
        let centersCurrentDay = id == store.state.currentPathDayID && (store.state.straightPath || textSize.isAccessibilitySize)
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            reader.scrollTo(id, anchor: centersCurrentDay ? .center : .top)
        }
    }

    private func horizontalOffset(_ id: String, days: [PathDayGroup], currentID: String?, width: CGFloat, straight: Bool) -> CGFloat {
        guard !straight else { return 0 }
        let ratios: [CGFloat] = [0, -0.11, -0.17, -0.11, 0, 0.11, 0.17, 0.11]
        let index = days.firstIndex { $0.id == id } ?? 0
        let current = days.firstIndex { $0.id == currentID } ?? 0
        return width * ratios[((index - current) % ratios.count + ratios.count) % ratios.count]
    }

    private func routeCompanion(_ prompt: PathCompanionPrompt, width: CGFloat, straight: Bool) -> some View {
        PathCompanionSlot(prompt: prompt, width: straight ? min(360, width - 48) : min(168, width * 0.44))
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: straight ? .center : .trailing)
            .padding(.horizontal, 24)
    }

    private func statusText(for day: PathDayGroup) -> String {
        if day.entries.count > 1 { return String(localized: "\(day.entries.count) Einträge") }
        guard let node = day.entries.first else { return "" }
        if let vaccination = node.vaccination { return vaccination.doseLabel }
        if let id = node.appointmentID, let appointment = store.state.appointments.first(where: { $0.id == id }) {
            if appointment.status == .cancelled { return appointment.status.displayTitle }
            return appointment.attendance == .unrecorded ? "" : appointment.attendance.displayTitle
        }
        if node.kind == .task { return node.taskStatus.displayTitle }
        if node.history != nil { return node.informationRead ? String(localized: "Gelesen") : "" }
        return NSLocalizedString(node.routeStatus, comment: "Path status")
    }

    private func labelTitle(for day: PathDayGroup) -> String? {
        guard day.entryCount > 1, day.title == "Mein Tag" || day.title == String(localized: "Mein Tag") else { return nil }
        let titles = day.entries.map(\.displayTitle).reduce(into: [String]()) { result, title in
            if !result.contains(title) { result.append(title) }
        }
        return titles.prefix(textSize.isAccessibilitySize ? 1 : 2).joined(separator: " · ")
    }
}

/// A path card stays attached to the tapped disk without moving the surrounding days.
private struct PathDayCallout: View {
    let day: PathDayGroup
    @Binding var selectedEntryID: UUID?
    let anchor: CGRect
    let viewport: CGSize
    let close: () -> Void
    let openDetails: (UUID) -> Void
    let askSovi: (UUID) -> Void
    @Environment(SoviStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let inset: CGFloat = 12
        let pointerHeight: CGFloat = 10
        let belowTip = anchor.maxY + 2
        let aboveTip = anchor.minY - 2
        let below = viewport.height - inset - belowTip - pointerHeight
        let above = aboveTip - pointerHeight - inset
        let placedBelow = below >= contentHeight && contentHeight > 0 || below >= above
        let maxWidth = max(1, viewport.width - 2 * inset)
        let width = textSize.isAccessibilitySize ? maxWidth : min(maxWidth, min(352, max(250, viewport.width * 0.78)))
        let x = min(max(anchor.midX, inset + width / 2), viewport.width - inset - width / 2)
        let available = max(1, placedBelow ? below : above)
        let height = min(contentHeight, available)
        let tip = placedBelow ? belowTip : aboveTip
        let direction: CGFloat = placedBelow ? 1 : -1
        let fill = PathSymbolPalette(topic: day.displayNode.routeTopic, progress: day.progress(in: store.state, now: store.now), scheme: scheme).surface
        let outline = RoundedRectangle(cornerRadius: 18, style: .continuous)
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)

            ScrollViewReader { reader in
                ScrollView {
                    PathDayCard(day: day, selectedEntryID: $selectedEntryID, close: close, openDetails: openDetails, onFocus: askSovi)
                        .frame(width: width)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded(.up) } action: { contentHeight = $0 }
                        .id("path.card.top")
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("path.card.scroll")
                .onChange(of: selectedEntryID) { _, _ in reader.scrollTo("path.card.top", anchor: .top) }
            }
            .frame(width: width, height: height)
            .background(fill, in: outline)
            .clipShape(outline)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, close)
            .position(x: x, y: tip + direction * (pointerHeight + height / 2))

            Path { path in
                path.move(to: CGPoint(x: 0, y: pointerHeight))
                path.addLine(to: CGPoint(x: 9, y: 1))
                path.addQuadCurve(to: CGPoint(x: 13, y: 1), control: CGPoint(x: 11, y: -1))
                path.addLine(to: CGPoint(x: 22, y: pointerHeight))
                path.closeSubpath()
            }
            .fill(fill)
            .frame(width: 22, height: pointerHeight)
            .rotationEffect(.degrees(placedBelow ? 0 : 180))
            .position(x: anchor.midX, y: tip + direction * (pointerHeight / 2 + 0.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(width: viewport.width, height: viewport.height)
    }
}

extension PathNode {
    var routeStatus: String {
        switch kind {
        case .event: "Lebensereignis"
        case .information: informationRead ? "Gelesen" : "Information"
        case .appointment: "Termin"
        case .medication: "Medikamentenplan"
        case .task:
            switch taskStatus {
            case .open: "Offen"
            case .inProgress: "In Bearbeitung"
            case .waiting: "Wartet"
            case .completed: "Erledigt"
            case .cancelled: "Abgebrochen"
            case .notDone: "Nicht erledigt"
            }
        }
    }
}
