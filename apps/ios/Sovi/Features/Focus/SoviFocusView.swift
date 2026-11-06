import SwiftUI

struct SoviFocusView: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var device
    @Environment(LiveChatController.self) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    @Binding var contextID: UUID?
    let response: CompanionResponse
    var language: ChatLanguage = .app
    let close: () -> Void
    let send: (String) -> Void
    let act: (CompanionAction) -> Void
    let attach: () -> Void
    let attachSample: () -> Void
    let importingDocument: Bool
    let cancelImport: () -> Void
    let leaveDocument: () -> Void
    let showEvent: (UUID) -> Void
    let chatSettings: () -> Void
    let forms: () -> Void
    let scenario: (DemoScenario) -> Void
    var localCaseResponse = false
    @State private var text = ""
    @State private var followsReplies = true
    @State private var userIsScrolling = false
    @State private var latestIsVisible = true
    @State private var nearBottom = true
    @State private var viewportHeight = 0
    @State private var scrollRequest = 0
    @State private var openedEpoch: Date?
    @State private var composerSaveTask: Task<Void, Never>?
    @State private var showsAttachments = false
    @FocusState private var keyboardOpen: Bool

    private var online: Bool { chat.enabled && contextID == nil && !localCaseResponse }
    private var showStarters: Bool { online ? chat.displayMessages.isEmpty : store.state.conversation.isEmpty }
    private var currentReply: LiveChatReply? { online ? chat.currentResult : nil }
    private var attendanceQuestionID: UUID? {
        guard !online, let id = response.attendanceQuestionID, contextID == id, store.state.focusContextID == id,
              let latest = store.state.conversation.last, latest.role == "assistant",
              latest.attendanceQuestionID == id, latest.text == response.text,
              let appointmentID = store.node(id: id)?.appointmentID,
              let record = store.state.appointments.first(where: { $0.id == appointmentID }),
              record.needsAttendanceCheck(at: store.now) else { return nil }
        return id
    }
    private var localEntryIDs: [UUID] {
        guard !online else { return [] }
        var ids = response.entryIDs
        if ids.isEmpty, let action = response.action, case .preview(let id) = action { ids = [id] }
        return Array(ids.filter { id in
            id != attendanceQuestionID && store.node(id: id).map { $0.kind == .task || $0.appointmentID != nil } == true
        }.prefix(3))
    }
    private var standaloneAction: CompanionAction? {
        if case .preview(let id) = response.action, localEntryIDs.contains(id) { return nil }
        return response.action
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let id = contextID, let node = store.node(id: id) {
                HStack(spacing: 8) {
                    Text(node.displayTitle).font(.caption.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 0)
                    Button { contextID = nil } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44)
                    }.accessibilityLabel("Kontext entfernen")
                }
                .padding(.leading, 14)
                .soviGlass(in: RoundedRectangle(cornerRadius: 16), tint: SoviTheme.accent.opacity(0.08))
                .padding(.horizontal, 12).padding(.bottom, 8)
                .accessibilityElement(children: .contain).accessibilityIdentifier("focus.context")
            } else if let id = store.state.discussedDocumentID, let document = store.document(id: id), !online {
                HStack(spacing: 8) {
                    Button { act(.reviewDocument(id)) } label: {
                        Label(document.displayTitle, systemImage: "doc.text").lineLimit(2)
                            .font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    Button(action: leaveDocument) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Dokumentkontext schließen").accessibilityIdentifier("focus.document.close")
                }
                .buttonStyle(.plain).padding(.leading, 14)
                .soviGlass(in: RoundedRectangle(cornerRadius: 16), tint: SoviTheme.accent.opacity(0.08))
                .padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    // Bounded transcripts use real row bounds, so a new reply is a
                    // stable scroll target even when buttons or the keyboard resize.
                    VStack(alignment: .leading, spacing: 16) {
                        conversation
                        ForEach(localEntryIDs, id: \.self) { id in
                            CompanionEntryCard(nodeID: id, primary: id == localEntryIDs.first, act: actFromChat)
                        }
                        if online { onlineState; attachmentHistory }
                        else if let action = standaloneAction {
                            Button { persistComposer(); keyboardOpen = false; act(action) } label: {
                                HStack { Text(action.title(in: language)).font(.headline); Spacer(); Image(systemName: "arrow.up.right") }
                                    .padding(16).frame(maxWidth: .infinity, minHeight: 52)
                                    .background(SoviTheme.accent, in: RoundedRectangle(cornerRadius: 18))
                                    .foregroundStyle(SoviTheme.background).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("focus.action")
                        }
                        if !online {
                            if !localEntryIDs.isEmpty {
                                Button("Was steht als Nächstes an?") { persistComposer(); keyboardOpen = false; act(.showProgress) }
                                    .frame(minHeight: 44).accessibilityIdentifier("focus.progress")
                            }
                            ForEach(response.caseChoices) { item in
                                Button(item.title(in: language)) { openScenario(item) }.buttonStyle(SheetPrimaryButtonStyle())
                            }
                        }
                        if showStarters { starters }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("focus.scroll")
                .onGeometryChange(for: Int.self) { Int($0.size.height.rounded()) } action: { viewportHeight = $0 }
                .onScrollPhaseChange { _, phase in
                    userIsScrolling = phase == .interacting || phase == .decelerating
                    if phase == .interacting { followsReplies = latestIsVisible || nearBottom }
                }
                .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height - $0.visibleRect.maxY < 80 } action: { _, atBottom in
                    nearBottom = atBottom
                    if userIsScrolling { followsReplies = atBottom || latestIsVisible }
                }
                .task(id: "\(latestReplyKey):\(viewportHeight):\(scrollRequest)") {
                    await Task.yield()
                    guard !Task.isCancelled, followsReplies else { return }
                    reader.scrollTo(latestScrollID, anchor: .top)
                }
                .overlay(alignment: .bottom) {
                    if !followsReplies && !latestIsVisible {
                        Button {
                            followsReplies = true
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo(latestScrollID, anchor: .top) }
                        } label: { Label("Zur neuesten Nachricht", systemImage: "arrow.down") }
                            .buttonStyle(.borderedProminent).padding(12).accessibilityIdentifier("focus.latestMessage")
                    }
                }
            }
            composer
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(SoviTheme.ink).background(SoviTheme.background)
        .onAppear { openedEpoch = store.state.fixtureEpoch; text = store.state.composerDraft }
        .onChange(of: text) { _, _ in
            composerSaveTask?.cancel()
            composerSaveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                persistComposer()
            }
        }
        .onDisappear { composerSaveTask?.cancel(); persistComposer(); device.stopAudio() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { composerSaveTask?.cancel(); persistComposer() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { persistComposer(); keyboardOpen = false; close() } label: {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                    .soviGlass(in: Circle(), interactive: true)
            }.frame(width: 44, height: 44).accessibilityLabel("Zurück").accessibilityIdentifier("focus.close")
            if !textSize.isAccessibilitySize { SoviMascot(size: 34).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 1) {
                Text("Sovi").font(textSize.isAccessibilitySize ? .caption.weight(.bold) : .headline)
                if !textSize.isAccessibilitySize {
                    Text(online ? String(localized: "Online-Chat") : String(localized: "Auf diesem Gerät"))
                        .font(.caption2).foregroundStyle(SoviTheme.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Sovi · \(online ? String(localized: "Online-Chat") : String(localized: "Auf diesem Gerät"))"))
            Menu {
                Section("Gemeinsam starten") {
                    ForEach(DemoScenario.allCases) { item in Button(item.title(in: language)) { openScenario(item) } }
                }
                Button("Profile und Formulare", systemImage: "doc.text") { persistComposer(); keyboardOpen = false; forms() }
                Button("Dokumente", systemImage: "folder") { persistComposer(); keyboardOpen = false; act(.documents) }
                    .accessibilityIdentifier("focus.documents")
                Button("Beispielbefund anhängen", systemImage: "doc.badge.plus") {
                    persistComposer(); keyboardOpen = false; followsReplies = true; attachSample()
                }
                .disabled(importingDocument).accessibilityIdentifier("focus.attachSample")
                if online {
                    Button("Neues Online-Gespräch", systemImage: "square.and.pencil") {
                        chat.reset(); followsReplies = true; scrollRequest += 1
                    }
                }
                if device.isSpeaking { Button("Vorlesen stoppen", systemImage: "stop.circle") { device.stopAudio() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 22)).frame(width: 44, height: 44)
                    .soviGlass(in: Circle(), interactive: true)
            }.frame(width: 44, height: 44).accessibilityLabel("Mehr").accessibilityIdentifier("focus.more")
            Button { persistComposer(); keyboardOpen = false; chatSettings() } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 22)).frame(width: 44, height: 44)
                    .soviGlass(in: Circle(), interactive: true)
            }.frame(width: 44, height: 44).accessibilityLabel("Chat-Einstellungen").accessibilityIdentifier("chat.settings")
        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder private var conversation: some View {
        if online && !chat.displayMessages.isEmpty {
            ForEach(Array(chat.displayMessages.enumerated()), id: \.offset) { index, message in
                bubble(message.content, user: message.role == "user", id: "cloud-\(index)", language: chat.result?.language,
                       identifier: message.role == "assistant" && index == chat.messages.count - 1 ? "focus.response" : "")
            }
        } else if !online && !store.state.conversation.isEmpty {
            let receiptIDs = Set(DocumentDiscussion.attachments(in: store.state).map { $0.reply.id })
            ForEach(store.state.conversation) { turn in
                storedBubble(turn, current: turn.role == "assistant" && turn.id == store.state.conversation.last?.id && turn.text == response.text,
                             showSource: !receiptIDs.contains(turn.id))
            }
            if store.state.conversation.last?.role != "assistant" || store.state.conversation.last?.text != response.text {
                bubble(response.text, user: false, id: "focus.current", identifier: "focus.response")
            }
        } else {
            bubble(online ? String(localized: "Wie kann ich dir helfen?") : response.text, user: false,
                   id: "focus.current", identifier: "focus.response")
        }
    }

    @ViewBuilder private var attachmentHistory: some View {
        let receipts = DocumentDiscussion.attachments(in: store.state)
        if !receipts.isEmpty {
            Button { showsAttachments.toggle() } label: {
                HStack {
                    Label("Anhänge in diesem Chat", systemImage: "paperclip")
                    Spacer()
                    Image(systemName: showsAttachments ? "chevron.up" : "chevron.down").accessibilityHidden(true)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(LocalizedStringKey(showsAttachments ? "Ausgeklappt" : "Eingeklappt")))
            .accessibilityIdentifier("focus.attachments")
            if showsAttachments {
                ForEach(receipts) { receipt in
                    storedBubble(receipt.attachment)
                    storedBubble(receipt.reply, showSource: false)
                }
            }
        }
    }

    private func storedBubble(_ turn: ConversationTurn, current: Bool = false, showSource: Bool = true) -> some View {
        bubble(turn.displayText, user: turn.role == "user", id: "local-\(turn.id)", identifier: current ? "focus.response" : "",
               attachment: turn.attachmentDocumentID.flatMap { store.document(id: $0) }, eventIDs: turn.attachmentEventIDs ?? [],
               sourceID: current || !showSource ? nil : turn.replyDocumentID)
    }

    private func bubble(_ content: String, user: Bool, id: String, language: String? = nil, identifier: String = "",
                        attachment: SourceDocument? = nil, eventIDs: [UUID] = [], sourceID: UUID? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attachment {
                Button { persistComposer(); keyboardOpen = false; act(.reviewDocument(attachment.id)) } label: {
                    HStack {
                        Label(attachment.displayTitle, systemImage: "paperclip").font(.headline)
                        Image(systemName: "chevron.forward").font(.caption.bold())
                    }
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("focus.attachment." + attachment.id.uuidString)
            } else {
                SoviChatBubble(text: content, isUser: user, language: language,
                               read: user ? nil : { device.speak(content, enabled: true) }, identifier: identifier)
            }
            if let sourceID, let document = store.document(id: sourceID) {
                Button { persistComposer(); keyboardOpen = false; act(.reviewDocument(sourceID)) } label: {
                    Label(document.displayTitle, systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .accessibilityHint("Originaltext öffnen")
            }
            if eventIDs.count > 3 {
                DisclosureGroup("Ereignisse im Pfad") { eventLinks(eventIDs) }
            } else if !eventIDs.isEmpty {
                eventLinks(eventIDs)
            }
            if identifier == "focus.response", !user, let nodeID = attendanceQuestionID {
                AttendanceQuickReplies(nodeID: nodeID, language: self.language, act: actFromChat)
            }
        }
            .id(id)
            .onScrollVisibilityChange(threshold: 0.05) { visible in
                guard id == latestScrollID else { return }
                latestIsVisible = visible
                if userIsScrolling { followsReplies = visible || nearBottom }
            }
    }

    private func eventLinks(_ ids: [UUID]) -> some View {
        ForEach(ids, id: \.self) { id in
            if let node = store.node(id: id) {
                Button { persistComposer(); keyboardOpen = false; showEvent(id) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(node.displayTitle).font(.subheadline.bold())
                            if let date = node.dateOnPath(in: store.state.pathCalendar) {
                                Text(date, format: .dateTime.day().month(.wide).year()).font(.caption)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.forward")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 44)
                    .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Im Pfad öffnen").accessibilityIdentifier("focus.event." + id.uuidString)
            }
        }
    }

    @ViewBuilder private var onlineState: some View {
        if chat.busy {
            HStack(spacing: 12) {
                ProgressView()
                Text("Sovi hört dir zu …").font(.subheadline)
                Spacer(minLength: 0)
                Button("Abbrechen") { chat.cancel() }.frame(minHeight: 44)
            }.accessibilityIdentifier("chat.loading")
        }
        if let error = chat.error {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).font(.subheadline).accessibilityIdentifier("chat.error")
                if let message = chat.failedMessage {
                    Button("Erneut senden") { sendMessage(message) }
                        .buttonStyle(SheetPrimaryButtonStyle()).disabled(chat.busy).accessibilityIdentifier("chat.retry")
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18))
        }
        if let notice = chat.locationNotice { Text(notice).font(.caption) }
        if let result = currentReply {
            LiveChatResultView(result: result, busy: chat.busy, send: sendMessage, openAnswer: { keyboardOpen = true })
        }
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup {
                VStack(spacing: 8) {
                    ForEach(DemoScenario.allCases) { item in
                        Button { openScenario(item) } label: {
                            HStack { Text(item.title(in: language)); Spacer(); Image(systemName: "arrow.up.right") }
                                .padding(14).frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("focus.scenario.\(item.rawValue)")
                    }
                }.padding(.top, 8)
            } label: {
                Text("Gemeinsam starten").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }
            Button { persistComposer(); keyboardOpen = false; forms() } label: {
                HStack { Label("Profile und Formulare", systemImage: "doc.text"); Spacer(); Image(systemName: "chevron.right") }
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("focus.forms")
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if chat.enabled {
                        prompt("Arzttermin finden", message: String(localized: "Ich möchte einen Arzttermin."))
                        prompt("Meine Schulter tut weh", message: String(localized: "Meine Schulter tut weh"))
                    } else {
                        prompt("Offene Aufgaben", message: "Was ist noch offen?")
                        prompt("Dokument ansehen", message: "Ich habe einen Entlassungsbrief.")
                        prompt("Termin hinzufügen", message: "Ich möchte einen Termin eintragen.")
                    }
                }
            }.scrollIndicators(.hidden)
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            Divider()
            if importingDocument {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(language.text("Dokument wird auf diesem Gerät gelesen …")).font(.subheadline)
                    Spacer(minLength: 0)
                    Button("Abbrechen", action: cancelImport).frame(minHeight: 44)
                }
                .padding(.horizontal, 12).accessibilityIdentifier("focus.importingDocument")
            }
            if device.isListening { Text("Aufnahme läuft …").font(.caption).accessibilityIdentifier("focus.listening") }
            HStack(alignment: .bottom, spacing: 6) {
                Button {
                    persistComposer()
                    keyboardOpen = false
                    followsReplies = true
                    attach()
                } label: { Image(systemName: "paperclip").frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .disabled(importingDocument).accessibilityLabel("Dokument hinzufügen").accessibilityIdentifier("focus.attach")
                TextField("Schreib Sovi …", text: $text, axis: .vertical)
                    .lineLimit(1...(textSize.isAccessibilitySize ? 2 : 4)).focused($keyboardOpen).submitLabel(.send).onSubmit(submit)
                    .padding(12).soviGlass(in: RoundedRectangle(cornerRadius: 18), tint: SoviTheme.accent.opacity(0.08))
                    .accessibilityIdentifier("focus.composer")
                Button {
                    keyboardOpen = false
                    let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await device.toggleRecording { transcript in text = prefix.isEmpty ? transcript : prefix + "\n" + transcript } }
                } label: { Image(systemName: device.isListening ? "stop.circle.fill" : "mic").font(.system(size: 22)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel(device.isListening ? "Aufnahme stoppen" : "Spracheingabe starten").accessibilityIdentifier("focus.microphone")
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(SoviTheme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .disabled(chat.busy || importingDocument || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Nachricht senden").accessibilityIdentifier("focus.send")
            }.padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .background(SoviTheme.background)
        .contentShape(Rectangle())
    }

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chat.busy, !importingDocument, !message.isEmpty else { return }
        composerSaveTask?.cancel(); text = ""; keyboardOpen = false; device.stopAudio(); sendMessage(message)
    }
    private func prompt(_ title: LocalizedStringKey, message: String) -> some View {
        Button { keyboardOpen = false; sendMessage(message) } label: {
            Text(title).font(.subheadline.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 12)
                .background(SoviTheme.softGreen, in: Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain).disabled(chat.busy)
    }
    private var latestScrollID: String {
        if online { return chat.displayMessages.isEmpty ? "focus.current" : "cloud-\(chat.displayMessages.count - 1)" }
        if let last = store.state.conversation.last, last.role == "assistant", last.text == response.text { return "local-\(last.id)" }
        return "focus.current"
    }
    private var latestReplyKey: String {
        online ? "cloud:\(chat.displayMessages.count):\(chat.displayMessages.last?.content ?? ""):\(chat.error ?? "")"
            : "local:\(store.state.conversation.last?.id.uuidString ?? ""):\(response.text)"
    }
    private func sendMessage(_ message: String) {
        guard !chat.busy else { return }
        followsReplies = true; scrollRequest += 1; send(message)
    }
    private func actFromChat(_ action: CompanionAction) {
        persistComposer(); keyboardOpen = false; followsReplies = true; scrollRequest += 1; act(action)
    }
    private func openScenario(_ item: DemoScenario) { persistComposer(); keyboardOpen = false; scenario(item) }
    private func persistComposer() {
        guard openedEpoch == store.state.fixtureEpoch, text != store.state.composerDraft else { return }
        do { try store.perform(.saveComposer(text)) } catch { store.errorMessage = error.localizedDescription }
    }
}

private struct AttendanceQuickReplies: View {
    let nodeID: UUID
    let language: ChatLanguage
    let act: (CompanionAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { answers }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 4) { answers }
            }
            reply(nil, symbol: "clock", suffix: "later")
        }
        .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
    }

    @ViewBuilder private var answers: some View {
        reply(.attended, symbol: "checkmark", suffix: "attended")
        reply(.notAttended, symbol: "xmark", suffix: "notAttended")
    }

    private func reply(_ answer: Attendance?, symbol: String, suffix: String) -> some View {
        let action = CompanionAction.answerCheckIn(nodeID, answer)
        return Button { act(action) } label: {
            Label(action.title(in: language), systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(minHeight: 44, alignment: .leading)
                .foregroundStyle(answer == nil ? SoviTheme.secondary : SoviTheme.accent)
                .background(answer == nil ? Color.clear : SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 14))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("focus.checkIn.\(suffix).\(nodeID)")
    }
}

private struct CompanionEntryCard: View {
    let nodeID: UUID
    let primary: Bool
    var act: (CompanionAction) -> Void
    @Environment(SoviStore.self) private var store

    var body: some View {
        if let node = store.node(id: nodeID) {
            VStack(alignment: .leading, spacing: 12) {
                Label(node.displayTitle, systemImage: node.appointmentID == nil ? "checklist" : "calendar")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                if let id = node.appointmentID, let record = store.state.appointments.first(where: { $0.id == id }) {
                    Text(record.date, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.subheadline).foregroundStyle(SoviTheme.secondary)
                    if record.status == .requestDraft { Text(record.status.displayTitle).font(.caption.weight(.semibold)) }
                    Text(record.status == .cancelled ? record.status.displayTitle : record.attendance.displayTitle)
                        .font(.caption.weight(.semibold)).foregroundStyle(node.progress(in: store.state, now: store.now) == .missed ? .red : SoviTheme.secondary)
                    if record.status == .confirmed && record.date < store.now {
                        option(String(localized: "Teilgenommen"), selected: record.attendance == .attended, symbol: "checkmark.circle", identifier: "attended", positive: true) {
                            act(.reportAttendance(record.id, .attended))
                        }
                        option(String(localized: "Nicht teilgenommen"), selected: record.attendance == .notAttended, symbol: "xmark.circle", identifier: "notAttended", negative: node.progress(in: store.state, now: store.now) == .missed) {
                            act(.reportAttendance(record.id, .notAttended))
                        }
                        option(String(localized: "Noch offen"), selected: record.attendance == .unrecorded, symbol: "circle", identifier: "unrecorded") {
                            act(.reportAttendance(record.id, .unrecorded))
                        }
                    } else if record.status == .confirmed {
                        Text("Die Teilnahme kannst du nach dem Termin eintragen.").font(.caption).foregroundStyle(SoviTheme.secondary)
                    }
                } else if node.kind == .task {
                    Text(node.taskStatus.displayTitle).font(.caption.weight(.semibold))
                        .foregroundStyle(node.progress(in: store.state, now: store.now) == .missed ? .red : SoviTheme.secondary)
                    option(String(localized: "Erledigt"), selected: node.taskStatus == .completed, symbol: "checkmark.circle", identifier: "done", positive: true) {
                        act(.reportTask(node.id, .completed))
                    }
                    option(String(localized: "Nicht erledigt"), selected: node.taskStatus == .notDone, symbol: "xmark.circle", identifier: "notDone", negative: node.progress(in: store.state, now: store.now) == .missed) {
                        act(.reportTask(node.id, .notDone))
                    }
                    option(String(localized: "Noch offen"), selected: node.taskStatus == .open, symbol: "circle", identifier: "open") {
                        act(.reportTask(node.id, .open))
                    }
                }
                Button { act(.preview(node.id)) } label: { Label("Eintrag öffnen", systemImage: "arrow.up.right").frame(minHeight: 44) }
                    .accessibilityIdentifier(primary ? "focus.action" : "focus.entry.open.\(nodeID)")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(SoviTheme.bubble, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(SoviTheme.border, lineWidth: 1).allowsHitTesting(false) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("focus.entry.\(nodeID)")
        }
    }
    private func option(_ title: String, selected: Bool, symbol: String, identifier: String, positive: Bool = false, negative: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? symbol + ".fill" : "circle").font(.title3)
                Text(title).font(.subheadline.weight(selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected && positive ? SoviTheme.accent : selected && negative ? .red : SoviTheme.ink)
            .padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(selected ? positive ? SoviTheme.softGreen : negative ? Color.red.opacity(0.08) : Color.gray.opacity(0.12) : SoviTheme.background, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityValue(selected ? String(localized: "Ausgewählt") : String(localized: "Nicht ausgewählt"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("focus.entry.\(identifier).\(nodeID)")
    }
}
