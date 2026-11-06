import SwiftUI

struct PendingReportTurn {
    let user: ConversationTurn
    let replyID = UUID()
}

private struct FocusTranscriptRow: Identifiable {
    enum Content { case local(ConversationTurn), cloud(Int, ChatMessage), current(String), writing }
    let key: ChatTurnKey
    let date: Date
    let content: Content
    var id: String { key.id }
}

struct SoviFocusView: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var device
    @Environment(LiveChatController.self) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.scenePhase) private var scenePhase
    @Binding var contextID: UUID?
    let response: CompanionResponse
    let reportTurn: PendingReportTurn?
    let restoredTurnCount: Int
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
    let shareBackground: () -> Void
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
    @State private var delivery = ChatDelivery()
    @State private var welcomePhoto: ConversationTurn?
    @State private var showsWelcomeTerms = false
    @FocusState private var keyboardOpen: Bool

    private var online: Bool { chat.enabled && contextID == nil && !localCaseResponse }
    private var showStarters: Bool { online ? chat.displayMessages.isEmpty : store.state.conversation.isEmpty }
    private func cloudID(_ index: Int) -> String { "cloud-\(chat.transcriptID)-\(index)" }
    private var currentID: String {
        online ? "hello-\(chat.transcriptID)" : "current-\(contextID?.uuidString ?? "")-\(response.text)"
    }
    private var guidedTurns: [ConversationTurn] {
        let main = store.state.conversation
        return (store.state.demoScenarios ?? [:]).values.flatMap(\.history).filter { turn in
            !main.contains { $0.role == turn.role && $0.text == turn.text && abs($0.date.timeIntervalSince(turn.date)) < 2 }
        }
    }

    private var rows: [FocusTranscriptRow] {
        var rows = (store.state.conversation + guidedTurns).map { FocusTranscriptRow(key: ChatTurnKey($0), date: $0.date, content: .local($0)) }
        let cloud = online ? chat.displayMessages : chat.messages
        rows += cloud.enumerated().map { index, message in
            FocusTranscriptRow(key: ChatTurnKey(cloudID(index), isUser: message.role == "user"),
                               date: chat.dates.indices.contains(index) ? chat.dates[index] : .distantFuture, content: .cloud(index, message))
        }
        rows.sort { $0.date < $1.date }
        if let reportTurn { rows.append(.init(key: ChatTurnKey(reportTurn.replyID.uuidString, isUser: false), date: .distantFuture, content: .writing)) }
        else if online && chat.busy {
            rows.append(.init(key: ChatTurnKey(cloudID(cloud.count), isUser: false), date: .distantFuture, content: .writing))
        } else if online ? cloud.isEmpty : (store.state.conversation.last?.role != "assistant" || store.state.conversation.last?.text != response.text) {
            let welcome = online ? String(localized: "Wie kann ich dir helfen?") : response.text
            rows.append(.init(key: ChatTurnKey(currentID, isUser: false), date: .distantFuture, content: .current(welcome)))
        }
        return rows
    }
    private var timeline: ChatTimeline {
        let keys = rows.compactMap { row -> ChatTurnKey? in
            if case .writing = row.content { return nil }
            return row.key
        }
        return ChatTimeline(turns: keys, awaitingNetwork: (online && chat.busy) || reportTurn != nil,
                            immediate: online && chat.currentResult?.status == "professional_guidance")
    }
    private var writingID: String? {
        if let reportTurn { return delivery.visible.contains(reportTurn.user.id.uuidString) ? reportTurn.replyID.uuidString : nil }
        if online && chat.busy {
            let nextIndex = chat.displayMessages.count
            return nextIndex > 0 && delivery.visible.contains(cloudID(nextIndex - 1)) ? cloudID(nextIndex) : nil
        }
        return delivery.writingID(timeline)
    }
    private var awaitingReply: Bool { delivery.expanding != nil || delivery.isTyping(timeline) }
    private var replyVisible: Bool {
        guard !awaitingReply else { return false }
        if online { return delivery.visible.contains(chat.messages.isEmpty ? currentID : cloudID(chat.messages.count - 1)) }
        if let last = store.state.conversation.last, last.role == "assistant", last.text == response.text {
            return delivery.visible.contains(last.id.uuidString)
        }
        return delivery.visible.contains(currentID)
    }
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
                    // Keep a stable row for each message as answers and the keyboard resize.
                    VStack(alignment: .leading, spacing: 16) {
                        welcomeHistory
                        conversation
                        if online && chat.busy {
                            Button("Abbrechen") { chat.cancel() }.buttonStyle(ChatActionButtonStyle(tone: .quiet))
                        }
                        ForEach(replyVisible ? localEntryIDs : [], id: \.self) { id in
                            CompanionEntryCard(nodeID: id, primary: id == localEntryIDs.first, act: actFromChat)
                        }
                        if online { onlineState }
                        else if replyVisible, let action = standaloneAction {
                            Button { persistComposer(); keyboardOpen = false; act(action) } label: {
                                ChatActionLabel(title: Text(action.title(in: language)), systemImage: "arrow.up.right")
                            }.buttonStyle(ChatActionButtonStyle()).accessibilityIdentifier("focus.action")
                        }
                        if replyVisible && !online {
                            if !localEntryIDs.isEmpty {
                                Button("Was steht als Nächstes an?") { persistComposer(); keyboardOpen = false; act(.showProgress) }
                                    .buttonStyle(ChatActionButtonStyle(tone: .blue)).accessibilityIdentifier("focus.progress")
                            }
                            ForEach(response.caseChoices) { item in
                                Button(item.title(in: language)) { openScenario(item) }.buttonStyle(ChatActionButtonStyle())
                            }
                        }
                        if showStarters && replyVisible { starters }
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
                .task(id: "\(latestReplyKey):\(latestScrollID):\(delivery.visible.count):\(viewportHeight):\(scrollRequest)") {
                    await Task.yield()
                    guard !Task.isCancelled, followsReplies else { return }
                    reader.scrollTo(latestScrollID, anchor: awaitingReply ? .bottom : .top)
                }
                .overlay(alignment: .bottom) {
                    if !followsReplies && !latestIsVisible {
                        Button {
                            followsReplies = true
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo(latestScrollID, anchor: awaitingReply ? .bottom : .top) }
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
        .onAppear {
            let local = store.state.conversation.prefix(restoredTurnCount).map(ChatTurnKey.init)
            let cloud = chat.messages.enumerated().map { ChatTurnKey(cloudID($0.offset), isUser: $0.element.role == "user") }
            delivery.restore(local + cloud + guidedTurns.map(ChatTurnKey.init))
            openedEpoch = store.state.fixtureEpoch; text = store.state.composerDraft
        }
        .task(id: timeline) {
            await delivery.present(timeline, reduceMotion: reduceMotion) { id in
                guard !online, scenePhase == .active, let last = store.state.conversation.last, last.id.uuidString == id else { return }
                device.speak(last.displayText, enabled: store.state.spokenReplies)
            }
        }
        .onChange(of: text) { _, _ in
            composerSaveTask?.cancel()
            composerSaveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                persistComposer()
            }
        }
        .onDisappear { composerSaveTask?.cancel(); persistComposer(); device.stopAudio() }
        .sheet(isPresented: $showsWelcomeTerms) { WelcomeTermsSheet() }
        .sheet(item: $welcomePhoto) { turn in
            if let photo = turn.eCardPhoto { WelcomeCardPhotoSheet(photo: photo) }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { composerSaveTask?.cancel(); persistComposer() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { persistComposer(); keyboardOpen = false; close() } label: {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                    .soviGlass(in: Circle(), interactive: true)
            }.frame(width: 44, height: 44).accessibilityLabel("Zurück").accessibilityIdentifier("focus.close")
            if !textSize.isAccessibilitySize { SoviMascot(size: 34).accessibilityHidden(true) }
            Text("Sovi").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    Button("Hintergrund teilen", systemImage: "text.badge.plus") {
                        persistComposer(); keyboardOpen = false; shareBackground()
                    }

                }
                if device.isSpeaking { Button("Vorlesen stoppen", systemImage: "stop.circle") { device.stopAudio() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 22)).frame(width: 44, height: 44)
                    .soviGlass(in: Circle(), interactive: true)
            }.frame(width: 44, height: 44).accessibilityLabel("Mehr").accessibilityIdentifier("focus.more")

        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 8)
    }

    // The welcome transcript stays local, including its photos. The API gets only cloud chat turns.
    @ViewBuilder private var welcomeHistory: some View {
        if let welcome = store.state.welcome {
            ForEach(welcome.displayHistory) { turn in
                if let photo = turn.eCardPhoto {
                    WelcomeECardPhotoBubble(photo: photo) { welcomePhoto = turn }
                } else {
                    SoviChatBubble(text: turn.text, isUser: turn.role == "user",
                                   read: turn.role == "assistant" ? { device.speak(turn.text, enabled: true) } : nil)
                }
                if turn.id == welcome.termsMessageID {
                    Button("Nutzungsbedingungen") { showsWelcomeTerms = true }.frame(minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder private var conversation: some View {
        ForEach(rows) { row in
            if delivery.displays(row.id, writingID: writingID) {
                switch row.content {
                case .local(let turn):
                    storedBubble(turn, current: !online && turn.role == "assistant" && turn.id == store.state.conversation.last?.id && turn.text == response.text)
                case .cloud(let index, let message):
                    bubble(message.content, user: message.role == "user", id: row.id, language: chat.replies[index]?.language ?? language.rawValue,
                           identifier: online && message.role == "assistant" && index == chat.messages.count - 1 ? "focus.response" : "")
                    if let reply = chat.replies[index], delivery.visible.contains(row.id), delivery.expanding != row.id {
                        let current = online && index == chat.messages.count - 1 && chat.currentResult != nil
                        LiveChatResultView(result: reply, active: current, looking: chat.lookingUp.contains(index),
                            mapNotice: chat.lookupNotices[index], busy: chat.busy, send: sendMessage, openAnswer: { keyboardOpen = true })
                    }
                case .current(let content): bubble(content, user: false, id: row.id, identifier: "focus.response")
                case .writing: bubble("", user: false, id: row.id)
                }
            }
        }
    }

    private func storedBubble(_ turn: ConversationTurn, current: Bool = false, showSource: Bool = true) -> some View {
        bubble(turn.displayText, user: turn.role == "user", id: turn.id.uuidString, identifier: current ? "focus.response" : "",
               attachment: turn.attachmentDocumentID.flatMap { store.document(id: $0) }, eventIDs: turn.attachmentEventIDs ?? [],
               sourceID: current || !showSource ? nil : turn.replyDocumentID)
    }

    private func bubble(_ content: String, user: Bool, id: String, language: String? = nil, identifier: String = "",
                        attachment: SourceDocument? = nil, eventIDs: [UUID] = [], sourceID: UUID? = nil) -> some View {
        let actionsVisible = writingID != id && delivery.expanding != id
        return VStack(alignment: .leading, spacing: 8) {
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
                SoviChatBubble(text: content, isUser: user, isWriting: !actionsVisible && !delivery.visible.contains(id), language: language ?? self.language.rawValue,
                               read: user ? nil : { device.speak(content, enabled: true) }, identifier: identifier)
            }
            if actionsVisible, let sourceID, let document = store.document(id: sourceID) {
                Button { persistComposer(); keyboardOpen = false; act(.reviewDocument(sourceID)) } label: {
                    Label(document.displayTitle, systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline).frame(minHeight: 44)
                }
                .accessibilityHint("Originaltext öffnen")
            }
            if actionsVisible && eventIDs.count > 3 {
                DisclosureGroup("Ereignisse im Pfad") { eventLinks(eventIDs) }
            } else if actionsVisible && !eventIDs.isEmpty {
                eventLinks(eventIDs)
            }
            if actionsVisible, identifier == "focus.response", !user, let nodeID = attendanceQuestionID {
                AttendanceQuickReplies(nodeID: nodeID, language: self.language, act: actFromChat)
            }
        }
            .id(id)
            .transition(.chatMessage)
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
        if let error = chat.error {
            VStack(alignment: .leading, spacing: 8) {
                Text(error).font(.subheadline).accessibilityIdentifier("chat.error")
                if let message = chat.failedMessage {
                    Button("Erneut senden") { sendMessage(message) }
                        .buttonStyle(ChatActionButtonStyle()).disabled(chat.busy).accessibilityIdentifier("chat.retry")
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 18))
        }
        if replyVisible, let notice = chat.locationNotice { Text(notice).font(.caption) }

    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 12) {
            if online {
                prompt("Arzttermin finden", message: String(localized: "Ich möchte einen Arzttermin."))
                prompt("Hilfe für Angehörige", message: String(localized: "Meine Mutter braucht Hilfe im Alltag."))
                if store.state.welcome?.termsAcceptedAt == nil {
                    Text("Chatnachrichten werden mit OpenAI verarbeitet.").font(.caption).foregroundStyle(SoviTheme.secondary)
                }
            } else {
                DisclosureGroup {
                    VStack(spacing: 8) {
                        ForEach(DemoScenario.allCases) { item in
                            Button { openScenario(item) } label: {
                                ChatActionLabel(title: Text(item.title(in: language)), systemImage: "arrow.up.right")
                            }.buttonStyle(ChatActionButtonStyle())
                                .accessibilityIdentifier("focus.scenario.\(item.rawValue)")
                        }
                    }.padding(.top, 8)
                } label: {
                    Text("Gemeinsam starten").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                Button { persistComposer(); keyboardOpen = false; forms() } label: {
                    ChatActionLabel(title: Text("Profile und Formulare"), systemImage: "doc.text")
                }.buttonStyle(ChatActionButtonStyle(tone: .purple)).accessibilityIdentifier("focus.forms")
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        prompt("Offene Aufgaben", message: "Was ist noch offen?")
                        prompt("Dokument ansehen", message: "Ich habe einen Entlassungsbrief.")
                        prompt("Termin hinzufügen", message: "Ich möchte einen Termin eintragen.")
                    }
                }.scrollIndicators(.hidden)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            Divider()
            if importingDocument {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(language.text("Dokument wird gelesen …")).font(.subheadline)
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
                } label: { Image(systemName: "paperclip").font(.system(size: 22, weight: .semibold)).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .disabled(importingDocument).accessibilityLabel("Dokument hinzufügen").accessibilityIdentifier("focus.attach")
                TextField("Schreib Sovi …", text: $text, axis: .vertical)
                    .lineLimit(1...(textSize.isAccessibilitySize ? 2 : 4)).focused($keyboardOpen).submitLabel(.send).onSubmit(submit)
                    .padding(12)
                    .background(SoviTheme.bubble, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(SoviTheme.border, lineWidth: 1).allowsHitTesting(false))
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { keyboardOpen = true })
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
                    .disabled(awaitingReply || chat.busy || importingDocument || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Nachricht senden").accessibilityIdentifier("focus.send")
            }.padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .background(SoviTheme.background)
        .contentShape(Rectangle())
    }

    private func submit() {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !awaitingReply, !chat.busy, !importingDocument, !message.isEmpty else { return }
        composerSaveTask?.cancel(); text = ""; keyboardOpen = false; device.stopAudio(); sendMessage(message)
    }
    private func prompt(_ title: LocalizedStringKey, message: String) -> some View {
        Button { keyboardOpen = false; sendMessage(message) } label: {
            ChatActionLabel(title: Text(title), systemImage: "arrow.turn.down.right")
        }.buttonStyle(ChatActionButtonStyle(tone: .blue)).disabled(chat.busy)
    }
    private var latestScrollID: String {
        if let incoming = writingID ?? delivery.expanding { return incoming }
        return timeline.turns.last(where: { delivery.visible.contains($0.id) })?.id ?? currentID
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
        guard !awaitingReply else { return }
        persistComposer(); keyboardOpen = false; followsReplies = true; scrollRequest += 1; act(action)
    }
    private func openScenario(_ item: DemoScenario) { persistComposer(); keyboardOpen = false; scenario(item) }
    private func persistComposer() {
        guard openedEpoch == store.state.fixtureEpoch, text != store.state.composerDraft else { return }
        do { try store.perform(.saveComposer(text)) } catch { store.errorMessage = error.localizedDescription }
    }
}

private struct ChatPathButton: View {
    let node: PathNode
    var showsCaption = true
    var identifier: String
    let action: () -> Void
    @Environment(SoviStore.self) private var store

    var body: some View {
        PathNodeButton(node: node, statusText: "", actionTitle: String(localized: "Öffnen"),
                       progress: node.progress(in: store.state, now: store.now), buttonIdentifier: identifier,
                       entryProgress: [node.haloProgress(in: store.state, now: store.now)], showsCaption: showsCaption,
                       action: action)
    }
}

private struct AttendanceQuickReplies: View {
    let nodeID: UUID
    let language: ChatLanguage
    let act: (CompanionAction) -> Void

    @Environment(SoviStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let node = store.node(id: nodeID) {
                ChatPathButton(node: node, showsCaption: false, identifier: "focus.timeline.\(nodeID)") { act(.preview(nodeID)) }
            }
            answers
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
            ChatActionLabel(title: Text(action.title(in: language)), systemImage: symbol)
        }
        .buttonStyle(ChatActionButtonStyle(tone: answer == .attended ? .green : answer == .notAttended ? .coral : .quiet))
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
                ChatPathButton(node: node, identifier: primary ? "focus.action" : "focus.entry.open.\(nodeID)") { act(.preview(node.id)) }
                if let id = node.appointmentID, let record = store.state.appointments.first(where: { $0.id == id }) {
                    if record.status == .requestDraft { Text(record.status.displayTitle).font(.caption.weight(.semibold)) }
                    if record.status == .cancelled { Text(record.status.displayTitle).font(.caption.bold()) }
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
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(SoviTheme.bubble, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(SoviTheme.border, lineWidth: 1).allowsHitTesting(false) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("focus.entry.\(nodeID)")
        }
    }
    private func option(_ title: String, selected: Bool, symbol: String, identifier: String, positive: Bool = false, negative: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ChatActionLabel(title: Text(title), systemImage: selected ? symbol + ".fill" : "circle")
        }.buttonStyle(ChatActionButtonStyle(tone: selected && positive ? .green : selected && negative ? .coral : .quiet))
            .accessibilityValue(selected ? String(localized: "Ausgewählt") : String(localized: "Nicht ausgewählt"))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("focus.entry.\(identifier).\(nodeID)")
    }
}
