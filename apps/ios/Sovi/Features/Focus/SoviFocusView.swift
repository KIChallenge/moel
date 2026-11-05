import SwiftUI

struct SoviFocusView: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var device
    @Environment(LiveChatController.self) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Binding var contextID: UUID?
    let response: CompanionResponse
    let namespace: Namespace.ID
    let close: () -> Void
    let send: (String) -> Void
    let act: (CompanionAction) -> Void
    let attach: () -> Void
    let chatSettings: () -> Void
    let forms: () -> Void
    let scenario: (DemoScenario) -> Void
    var localCaseResponse = false
    @State private var text = ""
    @State private var followsReplies = true
    @State private var userIsScrolling = false
    @State private var latestIsVisible = true
    @State private var openedEpoch: Date?
    @State private var composerSaveTask: Task<Void, Never>?
    @FocusState private var keyboardOpen: Bool

    private var online: Bool { chat.enabled && contextID == nil && !localCaseResponse }
    private var replyText: String { online ? chat.result?.reply ?? String(localized: "Wie kann ich dir helfen?") : response.text }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let id = contextID, let node = store.node(id: id) {
                            HStack {
                                Text(node.displayTitle).font(.caption.weight(.semibold))
                                Spacer()
                                Button { contextID = nil } label: { Image(systemName: "xmark.circle").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Kontext entfernen")
                            }
                            .accessibilityIdentifier("focus.context")
                        }
                        conversation
                        if online {
                            if chat.busy {
                                HStack { ProgressView("Sovi hört dir zu …"); Spacer(); Button("Abbrechen") { chat.cancel() } }
                                    .frame(minHeight: 44).accessibilityIdentifier("chat.loading")
                            }
                            if let error = chat.error {
                                Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("chat.error")
                                if let message = chat.failedMessage {
                                    Button("Erneut senden") { sendMessage(message) }.disabled(chat.busy).frame(minHeight: 44)
                                }
                            }
                            if let notice = chat.locationNotice { Text(notice).font(.caption) }
                            if let result = chat.result {
                                LiveChatResultView(result: result, busy: chat.busy, send: sendMessage, openAnswer: { keyboardOpen = true })
                            }
                            if !chat.background.isEmpty {
                                DisclosureGroup("Geteilter Hintergrund: \(chat.background.count) ausgewählte Einträge") {
                                    ForEach(chat.background) { entry in
                                        Text(entry.date + " · " + entry.title).font(.caption).padding(.vertical, 4)
                                    }
                                }.font(.caption).accessibilityIdentifier("chat.background")
                            }
                            Button("Neues Online-Gespräch") { chat.reset() }.frame(minHeight: 44).accessibilityIdentifier("chat.reset")
                        } else if let action = response.action {
                            Button { persistComposer(); keyboardOpen = false; act(action) } label: {
                                HStack { Text(action.title).font(.headline); Spacer(); Image(systemName: "arrow.up.right") }
                                    .padding(18).frame(minHeight: 44)
                                    .background(SoviTheme.accent, in: RoundedRectangle(cornerRadius: 20))
                                    .foregroundStyle(SoviTheme.background)
                            }.accessibilityIdentifier("focus.action")
                        }
                        if !online {
                            ForEach(response.caseChoices) { item in
                                Button(item.title) { scenario(item) }.buttonStyle(SheetPrimaryButtonStyle())
                            }
                        }
                        if !online || chat.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                DisclosureGroup("Gemeinsam starten") {
                                    ForEach(DemoScenario.allCases) { item in
                                        Button { persistComposer(); keyboardOpen = false; scenario(item) } label: {
                                            HStack { Text(item.title); Spacer(); Image(systemName: "arrow.up.right") }.padding(14).frame(minHeight: 44)
                                        }.background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 16))
                                            .accessibilityIdentifier("focus.scenario.\(item.rawValue)")
                                    }
                                }
                                Button("Profile und Formulare") { persistComposer(); keyboardOpen = false; forms() }.frame(minHeight: 44).accessibilityIdentifier("focus.forms")
                                if chat.enabled {
                                    prompt("Arzttermin finden", message: String(localized: "Ich möchte einen Arzttermin."))
                                    prompt("Meine Schulter tut weh", message: String(localized: "Meine Schulter tut weh"))
                                    prompt("Unterstützung für meine Mutter", message: String(localized: "Meine Mutter hat Schwierigkeiten, sich zu bewegen."))
                                } else {
                                    prompt("Offene Aufgaben", message: "Was ist noch offen?")
                                    prompt("Dokument ansehen", message: "Ich habe einen Entlassungsbrief.")
                                    prompt("Termin hinzufügen", message: "Ich möchte einen Termin eintragen.")
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("chat-bottom")
                    }
                    .padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("focus.scroll")
                .onScrollPhaseChange { _, phase in
                    userIsScrolling = phase == .interacting || phase == .decelerating
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentSize.height - geometry.visibleRect.maxY < 100
                } action: { _, atBottom in
                    if userIsScrolling { followsReplies = atBottom }
                }
                .task(id: latestReplyKey) {
                    await Task.yield()
                    guard !Task.isCancelled, followsReplies else { return }
                    reader.scrollTo("focus.latest", anchor: .top)
                }
                .task(id: keyboardOpen) {
                    guard keyboardOpen, followsReplies else { return }
                    await Task.yield()
                    reader.scrollTo("focus.latest", anchor: .top)
                }
                .overlay(alignment: .bottom) {
                    if !followsReplies && !latestIsVisible {
                        Button {
                            followsReplies = true
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { reader.scrollTo("focus.latest", anchor: .top) }
                        } label: { Label("Zur neuesten Nachricht", systemImage: "arrow.down") }
                            .buttonStyle(.borderedProminent).padding(12)
                            .accessibilityIdentifier("focus.latestMessage")
                    }
                }
            }
            composer
        }
        .foregroundStyle(SoviTheme.ink).background(SoviTheme.background)
        .onAppear { openedEpoch = store.state.fixtureEpoch; text = store.state.composerDraft }
        .onChange(of: text) { _, _ in
            composerSaveTask?.cancel()
            composerSaveTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                persistComposer()
            }
        }
        .onChange(of: store.state.composerDraft) { _, saved in if saved.isEmpty && !text.isEmpty { text = "" } }
        .onDisappear { composerSaveTask?.cancel(); persistComposer(); device.stopAudio() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { composerSaveTask?.cancel(); persistComposer() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { persistComposer(); keyboardOpen = false; close() } label: {
                Image(systemName: "xmark").font(.title3).frame(width: 44, height: 44)
            }.accessibilityLabel("Zurück").accessibilityIdentifier("focus.close")
            SoviMascot(size: 46, expression: device.isListening ? .listening : .calm)
                .matchedGeometryEffect(id: "sovi", in: namespace, properties: reduceMotion ? [] : .frame)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sovi").font(.headline)
                Text(chat.enabled ? String(localized: "Online-Chat") : String(localized: "Auf diesem Gerät"))
                    .font(.caption).foregroundStyle(SoviTheme.secondary)
            }
            Spacer()
            Button { persistComposer(); keyboardOpen = false; chatSettings() } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
            }.accessibilityLabel("Chat-Einstellungen").accessibilityIdentifier("chat.settings")
            if device.isSpeaking {
                Button { device.stopAudio() } label: { Image(systemName: "stop.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel("Vorlesen stoppen")
            }
        }.padding(.horizontal, 10).padding(.vertical, 8)
    }

    @ViewBuilder private var conversation: some View {
        if online && !chat.displayMessages.isEmpty {
            ForEach(Array(chat.displayMessages.enumerated()), id: \.offset) { index, message in
                if index == chat.displayMessages.count - 1 { latestAnchor }
                SoviChatBubble(text: message.content, isUser: message.role == "user", language: chat.result?.language,
                               read: message.role == "assistant" ? { device.speak(message.content, enabled: true) } : nil,
                               identifier: index == chat.messages.count - 1 ? "focus.response" : "")
            }
        } else if !online && !store.state.conversation.isEmpty {
            ForEach(store.state.conversation) { turn in
                if turn.id == store.state.conversation.last?.id && turn.text == response.text { latestAnchor }
                SoviChatBubble(text: turn.text, isUser: turn.role == "user",
                               read: turn.role == "assistant" ? { device.speak(turn.text, enabled: true) } : nil,
                               identifier: turn.id == store.state.conversation.last?.id ? "focus.response" : "")
            }
            if store.state.conversation.last?.text != response.text {
                latestAnchor
                SoviChatBubble(text: response.text, isUser: false, read: { device.speak(response.text, enabled: true) }, identifier: "focus.response")
            }
        } else {
            latestAnchor
            SoviChatBubble(text: replyText, isUser: false, read: { device.speak(replyText, enabled: true) }, identifier: "focus.response")
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            Divider()
            if device.isListening { Text("Aufnahme läuft …").font(.caption).accessibilityIdentifier("focus.listening") }
            HStack(alignment: .bottom, spacing: 4) {
                Button { persistComposer(); attach() } label: { Image(systemName: "paperclip").frame(width: 44, height: 44) }
                    .accessibilityLabel("Dokument hinzufügen")
                TextField("Schreib Sovi …", text: $text, axis: .vertical)
                    .lineLimit(1...4).focused($keyboardOpen).submitLabel(.send)
                    .padding(12).background(SoviTheme.softGreen.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityIdentifier("focus.composer")
                Button {
                    keyboardOpen = false
                    let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await device.toggleRecording { transcript in text = prefix.isEmpty ? transcript : prefix + "\n" + transcript } }
                } label: { Image(systemName: device.isListening ? "stop.circle.fill" : "mic").frame(width: 44, height: 44) }
                    .accessibilityLabel(device.isListening ? "Aufnahme stoppen" : "Spracheingabe starten").accessibilityIdentifier("focus.microphone")
                Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.title).frame(width: 44, height: 44) }
                    .disabled(chat.busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Nachricht senden").accessibilityIdentifier("focus.send")
            }.padding(.horizontal, 8).padding(.bottom, 10)
        }.background(SoviTheme.background)
    }
    private func submit() {
        let message = text; composerSaveTask?.cancel(); text = ""; device.stopAudio(); keyboardOpen = false; sendMessage(message)
    }
    private func prompt(_ title: LocalizedStringKey, message: String) -> some View {
        Button { composerSaveTask?.cancel(); text = ""; device.stopAudio(); keyboardOpen = false; sendMessage(message) } label: {
            HStack { Text(title); Spacer(); Image(systemName: "arrow.up.right") }
                .font(.subheadline.weight(.medium)).padding(14).frame(minHeight: 44)
                .background(SoviTheme.softGreen, in: RoundedRectangle(cornerRadius: 16))
        }.disabled(chat.busy)
    }
    private var latestReplyKey: String {
        online ? "\(chat.displayMessages.count):\(chat.displayMessages.last?.content ?? "")"
            : "\(store.state.conversation.last?.id.uuidString ?? ""):\(response.text)"
    }
    private var latestAnchor: some View {
        Color.clear.frame(height: 1).id("focus.latest")
            .onScrollVisibilityChange { latestIsVisible = $0 }
    }
    private func sendMessage(_ message: String) {
        followsReplies = true
        send(message)
    }
    private func persistComposer() {
        guard openedEpoch == store.state.fixtureEpoch, text != store.state.composerDraft else { return }
        do { try store.perform(.saveComposer(text)) } catch { store.errorMessage = error.localizedDescription }
    }
}
