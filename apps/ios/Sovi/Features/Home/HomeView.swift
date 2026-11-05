import SwiftUI

private enum ActiveSheet: Identifiable, Equatable {
    case node(UUID), day(String), documents, editor(NodeKind), draft, preparation(LifeDraftKind), controls, chatSettings, forms, scenario(DemoScenario)
    var id: String {
        switch self {
        case .node(let id): "node-\(id)"
        case .day(let id): "path-\(id)"
        case .documents: "documents"
        case .editor(let kind): "editor-\(kind.rawValue)"
        case .draft: "draft"
        case .preparation(let kind): "preparation-\(kind.rawValue)"
        case .controls: "controls"
        case .chatSettings: "chat-settings"
        case .forms: "forms"
        case .scenario(let scenario): "scenario-" + scenario.rawValue
        }
    }
}

struct HomeView: View {
    @Environment(SoviStore.self) private var store
    @Environment(DeviceServices.self) private var device
    @Environment(LiveChatController.self) private var chat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var companionGeometry
    @State private var isFocused = false
    @State private var contextID: UUID?
    @State private var activeSheet: ActiveSheet?
    @State private var pendingFocus: UUID?
    @State private var lastMessage: String?
    @State private var showsWelcome = false
    @State private var showsLocalCaseResponse = false
    @State private var response = CompanionResponse(text: String(localized: "Wie kann ich dir helfen?"))
    private let service: any CompanionService = DemoCompanionService()

    var body: some View {
        ZStack {
            SoviTheme.background.ignoresSafeArea()
            RouteView(isFocused: isFocused, namespace: companionGeometry, openDay: {
                activeSheet = .day($0)
            }, openSovi: { openFocus($0.contextID, invitation: $0.text) }, openControls: { activeSheet = .controls })
                .id(store.state.fixtureEpoch)
                .opacity(isFocused ? 0.10 : 1)
                .allowsHitTesting(!isFocused)
                .accessibilityHidden(isFocused)
            if isFocused {
                SoviFocusView(contextID: $contextID, response: response, namespace: companionGeometry,
                              close: closeFocus, send: send, act: handleAction,
                              attach: { activeSheet = .documents }, chatSettings: { activeSheet = .chatSettings },
                              forms: { activeSheet = .forms }, scenario: { activeSheet = .scenario($0) }, localCaseResponse: showsLocalCaseResponse)
                    .transition(.opacity)
                    .zIndex(1)
            }
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
                case .day(let id):
                    PathDaySheet(dayID: id) { nodeID in
                        pendingFocus = nodeID
                        activeSheet = nil
                    }
                case .documents: DocumentReviewSheet()
                case .editor(let kind): NodeEditorSheet(kind: kind)
                case .draft: AdministrativeDraftSheet()
                case .preparation(let kind): LifePreparationSheet(kind: kind)
                case .controls: LocalControlsSheet()
                case .chatSettings: LiveChatSettingsSheet()
                case .forms: FormLibrarySheet()
                case .scenario(let scenario): DemoScenarioChat(scenario: scenario)
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
                chat.setBackground([]); chat.reset()
                device.stopAudio()
                device.cleanupExports()
                isFocused = false
                activeSheet = nil
                contextID = nil
                response = CompanionResponse(text: String(localized: "Dein Weg ist leer."))
                showsLocalCaseResponse = false
            }
            if isFocused, let lastMessage, old.nodes != new.nodes || old.schedules != new.schedules || old.appointments != new.appointments
                || (showsLocalCaseResponse && (old.demoScenarios != new.demoScenarios || old.formPeople != new.formPeople || old.formDrafts != new.formDrafts)) {
                response = service.respond(to: lastMessage, context: contextID, state: new, now: store.now)
            }
            if old.schedules != new.schedules || old.appointments != new.appointments || old.notificationsEnabled != new.notificationsEnabled {
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
                if id == nil, isFocused {
                    lastMessage = "Was ist noch offen?"
                    response = service.respond(to: "Was ist noch offen?", context: nil, state: store.state, now: store.now)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { device.stopAudio(); chat.cancel() }
        }
    }

    private func openFocus(_ id: UUID?, invitation: String? = nil) {
        guard !isFocused else { contextID = id; return }
        showsLocalCaseResponse = false
        let resolved = invitation == nil ? (id ?? store.state.focusContextID) : id
        contextID = resolved
        try? store.perform(.setFocusContext(resolved))
        if let id = resolved, let node = store.node(id: id) {
            lastMessage = nil
            response = CompanionResponse(text: invitation ?? String(localized: "Was möchtest du zu „\(node.displayTitle)“ wissen?"), evidence: node.evidence, action: .preview(id))
        } else {
            lastMessage = "Was ist noch offen?"
            response = invitation.map { CompanionResponse(text: $0) }
                ?? service.respond(to: "Was ist noch offen?", context: nil, state: store.state, now: store.now)
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.45, bounce: 0.05)) { isFocused = true }
    }

    private func closeFocus() {
        device.stopAudio()
        chat.cancel()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.45, bounce: 0.05)) { isFocused = false }
    }

    private func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        if let savedCase = DemoCompanionService.savedCaseResponse(to: message, state: store.state) {
            chat.cancel(); showsLocalCaseResponse = true
            do {
                try store.perform(.appendConversation(role: "user", text: message))
                response = savedCase; lastMessage = message
                try store.perform(.appendConversation(role: "assistant", text: savedCase.text))
                try store.perform(.saveComposer(""))
            } catch { store.errorMessage = error.localizedDescription }
            return
        }
        showsLocalCaseResponse = false
        if let scenario = DemoScenario.matching(message) {
            chat.cancel(); activeSheet = .scenario(scenario)
            try? store.perform(.saveComposer(""))
            return
        }
        if message.localizedCaseInsensitiveContains("formular") || message.lowercased().contains("fill a form") {
            activeSheet = .forms
            try? store.perform(.saveComposer(""))
            return
        }
        if chat.enabled {
            guard !chat.busy else { return }
            contextID = nil
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
            device.speak(response.text, enabled: store.state.spokenReplies)
        } catch { store.errorMessage = error.localizedDescription }
    }

    private func handleAction(_ action: CompanionAction) {
        switch action {
        case .documents: activeSheet = .documents
        case .draft: activeSheet = .draft
        case .preparation(let kind): activeSheet = .preparation(kind)
        case .add(let kind): activeSheet = .editor(kind)
        case .preview(let id): activeSheet = .node(id)
        case .controls: activeSheet = .controls
        case .scenario(let scenario): activeSheet = .scenario(scenario)
        }
    }
}

private struct RouteSection: Identifiable {
    var id: String
    var title: String
    var stage: String
    var days: [PathDayGroup]
}

private struct RouteScrollContext: Equatable {
    var edge: VerticalEdge?
    var sectionID: String?
}

private struct RouteView: View {
    @Environment(SoviStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var compactSpacing = 112.0
    @ScaledMetric(relativeTo: .body) private var readableSpacing = 220.0
    var isFocused: Bool
    var namespace: Namespace.ID
    var openDay: (String) -> Void
    var openSovi: (PathCompanionPrompt) -> Void
    var openControls: () -> Void
    @State private var didAnchor = false
    @State private var visibleSectionID: String?
    @State private var sectionOffsets: [String: CGFloat] = [:]
    @State private var mascotFrame = CGRect.zero
    @State private var companionEdge: VerticalEdge?

    private var sections: [RouteSection] {
        let days = store.state.pathDays
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
        let currentSection = groups.first { $0.days.contains { $0.id == currentID } }
        let straight = store.state.straightPath || textSize.isAccessibilitySize
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let referenceDate = store.state.lifeScenario?.snapshot ?? store.now
            let prompt = PathCompanionPrompt.make(state: store.state, now: referenceDate, locale: locale)
            VStack(spacing: 0) {
                PathOverviewStrip(appointments: store.state.appointments.filter { $0.status != .cancelled && $0.attendance == .unrecorded && $0.date >= referenceDate }.count,
                                  documents: store.state.documents.count,
                                  vaccinations: store.nodes.filter { $0.vaccination != nil }.count,
                                  tasks: store.state.uniqueOpenTasks.count)
                let section = groups.first { $0.id == visibleSectionID } ?? currentSection ?? groups.first
                PathSectionBanner(caption: section?.stage.isEmpty == false ? section?.title ?? "" : "",
                                  title: section?.stage.isEmpty == false ? section?.stage ?? "" : section?.title ?? String(localized: "Dein Weg"),
                                  openControls: openControls)
                    .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
                GeometryReader { viewport in
                    ScrollViewReader { reader in
                        VStack(spacing: 0) {
                            navigation(reader, groups: groups, currentID: currentID)
                            ScrollView {
                                // Real rows give scrolling and accessibility individual bounds. No
                                // absolutely positioned children sharing a 30,000-point canvas.
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
                                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("route-content")).minY } action: { sectionOffsets[group.id] = $0 }
                                        ForEach(group.days) { day in
                                            VStack(spacing: 16) {
                                                if day.id == currentID {
                                                    PathTodayMarker(title: store.state.lifeScenario == nil ? String(localized: "Hier") : String(localized: "Heute"))
                                                        .padding(.top, 12)
                                                }
                                                PathNodeButton(node: day.displayNode, statusText: statusText(for: day),
                                                               entryCount: day.entryCount, dateIncludesTime: false,
                                                               isCurrent: day.id == currentID, compact: !straight && day.date != nil,
                                                               buttonIdentifier: "path.day.\(day.id)") { openDay(day.id) }
                                            }
                                            .frame(maxWidth: .infinity)
                                            .frame(minHeight: straight ? readableSpacing : compactSpacing)
                                            .offset(x: horizontalOffset(day.id, days: days, currentID: currentID, width: viewport.size.width, straight: straight))
                                            .id(day.id)
                                            if day.id == currentID {
                                                routeCompanion(prompt, width: viewport.size.width, straight: straight)
                                            }
                                        }
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
                            }
                            .accessibilityIdentifier("path.scroll")
                            .onScrollGeometryChange(for: RouteScrollContext.self) { geometry in
                                let rect = geometry.visibleRect
                                let edge: VerticalEdge? = mascotFrame == .zero ? nil
                                    : mascotFrame.maxY <= rect.minY ? .top
                                    : mascotFrame.minY >= rect.maxY ? .bottom : nil
                                let section = groups.last { (sectionOffsets[$0.id] ?? .greatestFiniteMagnitude) <= rect.minY + 32 }?.id ?? groups.first?.id
                                return RouteScrollContext(edge: edge, sectionID: section)
                            } action: { _, context in
                                // Updating only at boundaries avoids rebuilding every record
                                // for each pixel of an ordinary drag.
                                companionEdge = context.edge
                                if didAnchor { visibleSectionID = context.sectionID }
                            }
                            .safeAreaInset(edge: .top, spacing: 0) {
                                if companionEdge == .top {
                                    edgeCompanion(prompt, placement: .top, width: viewport.size.width)
                                        .opacity(isFocused ? 0 : 1).allowsHitTesting(!isFocused).accessibilityHidden(isFocused)
                                }
                            }
                            .safeAreaInset(edge: .bottom, spacing: 0) {
                                if companionEdge == .bottom {
                                    edgeCompanion(prompt, placement: .bottom, width: viewport.size.width)
                                        .opacity(isFocused ? 0 : 1).allowsHitTesting(!isFocused).accessibilityHidden(isFocused)
                                }
                            }
                            .opacity(didAnchor ? 1 : 0)
                            .task {
                                guard !didAnchor else { return }
                                await Task.yield()
                                if let currentID { reader.scrollTo(currentID, anchor: .top) }
                                visibleSectionID = currentSection?.id
                                didAnchor = true
                            }
                        }
                    }
                }
            }
            .foregroundStyle(SoviTheme.ink)
        }
    }

    private func navigation(_ reader: ScrollViewProxy, groups: [RouteSection], currentID: String?) -> some View {
        Group {
            if textSize.isAccessibilitySize {
                navigationButtons(reader, groups: groups, currentID: currentID).labelStyle(.iconOnly)
            } else { navigationButtons(reader, groups: groups, currentID: currentID) }
        }
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .padding(.horizontal, 20).frame(minHeight: 44)
    }

    private func navigationButtons(_ reader: ScrollViewProxy, groups: [RouteSection], currentID: String?) -> some View {
        HStack {
            if let currentID {
                Button { jump(currentID, reader: reader) } label: { Label("Heute", systemImage: "location.fill").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityIdentifier("path.today")
            }
            Spacer(minLength: 12)
            Menu {
                ForEach(groups.filter { $0.stage.isEmpty }) { section in
                    Button(section.title) { jump(section.id, reader: reader) }.accessibilityIdentifier("path.jump.\(section.id)")
                }
                Divider()
                ForEach(groups.filter { !$0.stage.isEmpty }) { section in
                    Button(section.title) { jump(section.id, reader: reader) }.accessibilityIdentifier("path.jump.\(section.id)")
                }
            } label: { Label("Abschnitte", systemImage: "list.bullet").frame(minWidth: 44, minHeight: 44) }
                .accessibilityIdentifier("path.sections")
        }
    }

    private func jump(_ id: String, reader: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { reader.scrollTo(id, anchor: .top) }
    }

    private func horizontalOffset(_ id: String, days: [PathDayGroup], currentID: String?, width: CGFloat, straight: Bool) -> CGFloat {
        guard !straight else { return 0 }
        let ratios: [CGFloat] = [0, -0.11, -0.17, -0.11, 0, 0.11, 0.17, 0.11]
        let index = days.firstIndex { $0.id == id } ?? 0
        let current = days.firstIndex { $0.id == currentID } ?? 0
        return width * ratios[((index - current) % ratios.count + ratios.count) % ratios.count]
    }

    private func routeCompanion(_ prompt: PathCompanionPrompt, width: CGFloat, straight: Bool) -> some View {
        PathCompanionView(prompt: prompt, bubbleWidth: straight ? min(360, width - 48) : min(168, width * 0.44),
                          routeMascotSize: 140, isActive: companionEdge == nil && !isFocused,
                          namespace: namespace) { openSovi(prompt) }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: straight ? .center : .trailing)
            .padding(.horizontal, 24)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("route-content")) } action: { mascotFrame = $0 }
            .opacity(isFocused ? 0 : 1)
            .allowsHitTesting(companionEdge == nil && !isFocused)
            .accessibilityHidden(companionEdge != nil || isFocused)
    }

    private func edgeCompanion(_ prompt: PathCompanionPrompt, placement: PathCompanionPlacement, width: CGFloat) -> some View {
        PathCompanionView(prompt: prompt, placement: placement, bubbleWidth: min(300, width - (textSize.isAccessibilitySize ? 40 : 144)),
                          isActive: !isFocused, namespace: namespace) { openSovi(prompt) }
            .background {
                LinearGradient(colors: placement == .top
                               ? [SoviTheme.background, SoviTheme.background.opacity(0)]
                               : [SoviTheme.background.opacity(0), SoviTheme.background],
                               startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
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
            }
        }
    }
}
