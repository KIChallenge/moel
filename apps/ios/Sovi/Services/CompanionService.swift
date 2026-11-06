import Foundation

struct CompanionResponse {
    var text: String
    var evidence: [EvidenceReference] = []
    var action: CompanionAction?
    var caseChoices: [DemoScenario] = []
    var entryIDs: [UUID] = []
    var attendanceQuestionID: UUID?
}

enum CompanionAction {
    case documents, draft, preparation(LifeDraftKind), add(NodeKind), preview(UUID), controls, scenario(DemoScenario)
    case reviewDocument(UUID)
    case matchedForm(String)
    case reportTask(UUID, TaskStatus), reportAttendance(UUID, Attendance), showProgress
    case answerCheckIn(UUID, Attendance?)

    var title: String { title(in: .app) }
    func title(in language: ChatLanguage) -> String {
        switch self {
        case .documents: language.text("Dokumente öffnen")
        case .reviewDocument: language.text("Dokument prüfen")
        case .matchedForm: language.text("Formularentwurf vorbereiten")
        case .draft: language.text("Entwurf öffnen")
        case .preparation(.questionnaire): language.text("Anamnesebogen öffnen")
        case .preparation(.medicationList): language.text("Medikamentenliste öffnen")
        case .add(.appointment): language.text("Termin eintragen")
        case .add(.event): language.text("Ereignis hinzufügen")
        case .add: language.text("Aufgabe hinzufügen")
        case .preview: language.text("Eintrag öffnen")
        case .controls: language.text("Einstellungen")
        case .scenario: language.text("Vorgang fortsetzen")
        case .reportTask(_, let status): status.displayTitle
        case .reportAttendance(_, let attendance): attendance == .unrecorded ? language.text("Noch offen") : attendance.displayTitle
        case .answerCheckIn(_, .attended): language.text("Ja, ich war dort")
        case .answerCheckIn(_, .notAttended): language.text("Nein, ich war nicht dort")
        case .answerCheckIn: language.text("Später antworten")
        case .showProgress: language.text("Was steht als Nächstes an?")
        }
    }
}

protocol CompanionService {
    func respond(to message: String, context: UUID?, state: AppState, now: Date) -> CompanionResponse
}

/// Deterministic, offline intent matching. Never applies commands or interprets medicine.
struct DemoCompanionService: CompanionService {
    var preference = "auto"

    func respond(to message: String, context: UUID?, state: AppState, now: Date) -> CompanionResponse {
        let language = ChatLanguage.resolve(message, preference: preference)
        if let savedCase = Self.savedCaseResponse(to: message, state: state, language: language) { return savedCase }
        let text = ChatLanguage.normalized(message)
        let selected = state.nodes.first { $0.id == context }
        let open = state.uniqueOpenTasks
        if let progress = Self.progressResponse(to: message, context: context, state: state, now: now, language: language),
           progress.attendanceQuestionID != nil || Self.mentionsPastAppointment(text) { return progress }
        if contains(text, ["gespeichert", "daten", "datenschutz", "speicherst", "privacy", "stored data", "saved data", "gizlilik", "kayitli veri", "خصوصية", "بياناتي"]) {
            return CompanionResponse(text: language.localized("Auf diesem Gerät: \(state.nodes.count) Einträge, \(state.documents.count) Dokumente und \(state.conversation.count) Nachrichten."), action: .controls)
        }
        if contains(text, ["entlass", "dokument", "brief", "anhang", "document", "report", "letter", "belge", "rapor", "تقرير", "مستند"]) {
            return CompanionResponse(text: language.localized("Öffne ein Dokument, um die Einträge zu prüfen."), action: .documents)
        }
        if contains(text, ["warum", "quelle", "woher", "beleg", "source", "evidence", "why", "kaynak", "neden", "مصدر", "لماذا"]) {
            guard let selected else {
                return CompanionResponse(text: language.localized("Welchen Eintrag meinst du?"))
            }
            return CompanionResponse(text: selected.evidence.isEmpty
                ? language.localized("Für „\(selected.displayTitle)“ ist keine Quelle hinterlegt.")
                : language.localized("Hier findest du die Quelle zu „\(selected.displayTitle)“."), evidence: selected.evidence, action: .preview(selected.id))
        }
        if contains(text, ["impf", "vaccin", "immunization", "asi kaydi", "تطعيم", "لقاح"]) {
            let records = state.nodes.filter { $0.vaccination != nil }.sorted {
                if $0.date != $1.date { return ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                return $0.title < $1.title
            }
            guard let node = selected?.vaccination == nil ? records.first : selected,
                  let record = node.vaccination else {
                return CompanionResponse(text: language.localized("Keine Impfungen eingetragen."))
            }
            if selected?.id == node.id {
                return CompanionResponse(text: language.localized("\(record.disease): \(record.product), \(record.administrationText). \(record.doseLabel) · Charge \(record.batch)."), evidence: node.evidence, action: .preview(node.id))
            }
            let covid = records.filter { $0.vaccination?.disease == "COVID-19" }.count
            let influenza = records.filter { $0.vaccination?.disease.localizedCaseInsensitiveContains("Influenza") == true }.count
            let formatter = DateFormatter(); formatter.timeZone = state.pathCalendar.timeZone
            formatter.locale = Locale(identifier: language.rawValue); formatter.dateFormat = "d. MMMM yyyy"
            let localDay = record.administrationDay.flatMap { state.pathCalendar.date(from: $0) } ?? node.date
            let latest = localDay.map(formatter.string(from:)) ?? record.administrationText
            return CompanionResponse(text: language.localized("\(records.count) Impfungen: \(covid) COVID-19 und \(influenza) Influenza. Zuletzt am \(latest)."), evidence: node.evidence, action: .preview(node.id))
        }
        if contains(text, ["anamnese", "medikamentenliste"]) || (contains(text, ["formular", "vorsorge"]) && selected?.history?.draftKind != nil) {
            let kind: LifeDraftKind = contains(text, ["medikamentenliste"]) ? .medicationList : selected?.history?.draftKind ?? .questionnaire
            return CompanionResponse(text: language.localized("Öffnen wir den Entwurf."), action: .preparation(kind))
        }
        if contains(text, ["antrag", "kostenerstatt", "formular", "papier", "entwurf"]) {
            return CompanionResponse(text: language.localized("Ich helfe dir beim Entwurf."), action: .draft)
        }
        let creating = contains(text, ["eintragen", "anlegen", "hinzufugen", "organisieren", "vereinbaren", "erstellen", "add", "create", "schedule", "planla", "ekle", "إضافة", "اضف", "انشاء"])
        if contains(text, ["termin", "physio", "therapie", "appointment", "randevu", "موعد"]) && (creating || !contains(text, ["heute", "offen", "ansteht", "steht an"])) {
            return CompanionResponse(text: language.localized("Welchen Termin möchtest du eintragen?"), action: .add(.appointment))
        }
        if contains(text, ["ereignis", "lebensereignis", "kapitel", "event", "etkinlik", "حدث"]) {
            return CompanionResponse(text: language.localized("Was möchtest du festhalten?"), action: .add(.event))
        }
        if creating && contains(text, ["aufgabe", "schritt", "task", "step", "gorev", "مهمة"]) && !contains(text, ["erledigt", "fertig", "abgeschlossen"]) {
            return CompanionResponse(text: language.localized("Welche Aufgabe möchtest du hinzufügen?"), action: .add(.task))
        }
        if contains(text, ["erledigt", "fertig", "abgeschlossen", "geschafft", "completed", "finished", "done", "tamamlandi", "bitti", "انتهيت", "انجزت"]) {
            if let selected, selected.kind == .task {
                return CompanionResponse(text: language.localized("Möchtest du „\(selected.displayTitle)“ als erledigt markieren?"), action: .preview(selected.id))
            }
            if open.count == 1, let first = open.first {
                return CompanionResponse(text: language.localized("Möchtest du „\(first.displayTitle)“ als erledigt markieren?"), action: .preview(first.id))
            }
            return CompanionResponse(text: language.localized("Welche Aufgabe meinst du? Offen: \(open.count)."))
        }
        if contains(text, ["heute", "offen", "ansteht", "ansteht", "zu tun", "steht an", "uberblick", "today", "open tasks", "overview", "bugun", "gorevlerim", "اليوم", "مهامي"]) {
            if let scenario = state.lifeScenario {
                let currentID = state.currentPathDayID
                let today = state.pathDays.first { $0.id == currentID }
                let summary = today?.entries.map { node -> String in
                    if let id = node.appointmentID, let appointment = state.appointments.first(where: { $0.id == id }) {
                        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: scenario.timeZone)
                        formatter.locale = Locale(identifier: language.rawValue); formatter.dateFormat = "HH:mm"
                        return "\(node.displayTitle) \(formatter.string(from: appointment.date))"
                    }
                    return node.kind == .task ? "\(node.displayTitle) · \(node.taskStatus.displayTitle)" : node.displayTitle
                }.joined(separator: "; ") ?? language.localized("Keine Einträge")
                let planned = state.appointments.filter { $0.status != .cancelled && $0.attendance == .unrecorded && $0.date >= scenario.snapshot }.count
                let unrecorded = state.schedules.flatMap(\.occurrences).filter { $0.log == .unrecorded }.count
                var reply = language.localized("Heute: \(summary).\nOffene Aufgaben: \(open.count) · Termine: \(planned)")
                if unrecorded > 0 { reply += "\n" + language.localized("Einnahmen offen: \(unrecorded)") }
                return CompanionResponse(text: reply, action: open.first.map { .preview($0.id) }, entryIDs: Self.progressEntries(state: state, now: now))
            }
            let appointments = state.appointments.filter { $0.status != .cancelled && $0.date >= now }
            let unrecorded = state.schedules.flatMap(\.occurrences).filter { $0.log == .unrecorded }.count
            var reply = language.localized("Offene Aufgaben: \(open.count) · Termine: \(appointments.count)")
            if unrecorded > 0 { reply += "\n" + language.localized("Einnahmen offen: \(unrecorded)") }
            return CompanionResponse(text: reply, action: open.first.map { .preview($0.id) }, entryIDs: Self.progressEntries(state: state, now: now))
        }
        if contains(text, ["medikament", "dosis", "schmerz", "diagnose", "behandlung", "notfall", "dose", "pain", "diagnosis", "medicine", "acil", "agri", "ilac", "دواء", "الم", "تشخيص"]) {
            return CompanionResponse(text: language.localized("Bitte kläre medizinische Fragen mit deiner behandelnden Stelle."))
        }
        return CompanionResponse(text: language.localized("Wobei kann ich dir helfen? Aufgaben, Termine oder Unterlagen?"), caseChoices: DemoScenario.allCases)
    }

    static func entryResponse(for node: PathNode, state: AppState, now: Date, language: ChatLanguage = .app) -> CompanionResponse {
        let text: String
        if node.kind == .task && node.taskStatus != .completed && node.taskStatus != .cancelled && node.taskStatus != .notDone {
            text = language.localized("Hast du „\(node.displayTitle)“ schon erledigt?")
        }
        else if let id = node.appointmentID, let record = state.appointments.first(where: { $0.id == id }) {
            if record.needsAttendanceCheck(at: now) {
                return CompanionResponse(text: record.attendanceQuestion(calendar: state.pathCalendar, language: language, locale: Locale(identifier: language.rawValue)),
                                         evidence: node.evidence, action: .preview(node.id), entryIDs: [node.id], attendanceQuestionID: node.id)
            }
            text = language.localized("Hier ist dein Termin.")
        }
        else { text = language.localized("Was möchtest du zu „\(node.displayTitle)“ wissen?") }
        return CompanionResponse(text: text, evidence: node.evidence, action: .preview(node.id),
                                 entryIDs: node.kind == .task || node.appointmentID != nil ? [node.id] : [])
    }

    /// Free text only records an outcome when the entire message answers the pending question.
    static func checkInAnswer(to message: String, nodeID: UUID) -> CompanionAction? {
        guard !message.contains("?") && !message.contains("؟") else { return nil }
        func words(_ text: String) -> String {
            ChatLanguage.normalized(text).components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let input = words(message)
        let answers: [(Attendance?, [String])] = [
            (.attended, ["ja", "ich war da", "ich war dort", "teilgenommen", "yes", "i went", "i attended", "i was there", "attended",
                         "evet", "gittim", "katıldım", "نعم", "حضرت", "ذهبت"]),
            (.notAttended, ["nein", "ich war nicht da", "ich war nicht dort", "nicht teilgenommen", "verpasst", "no", "i missed it", "i didn't go", "did not attend", "i did not attend",
                            "hayır", "gitmedim", "katılmadım", "لا", "لم احضر", "لم اذهب"]),
            (nil, ["später", "weiß ich nicht", "noch nicht sicher", "later", "not sure", "i'm not sure", "not now",
                   "sonra", "emin değilim", "لاحقا", "لست متأكدا"])
        ]
        for (attendance, variants) in answers {
            let action = CompanionAction.answerCheckIn(nodeID, attendance)
            if variants.contains(where: { words($0) == input }) { return action }
            if [ChatLanguage.de, .en, .tr, .ar].contains(where: { words(action.title(in: $0)) == input }) { return action }
        }
        return nil
    }

    /// Stored-entry progress stays local; booking requests still go to intake.
    static func progressResponse(to message: String, context: UUID?, state: AppState, now: Date, language: ChatLanguage = .app) -> CompanionResponse? {
        let text = ChatLanguage.normalized(message).replacingOccurrences(of: "’", with: "'")
        let medical = ["schmerz", "weh", "hurt", "pain", "shoulder", "symptom", "diagnos", "fieber", "fever", "befund", "entlassungsbrief", "mutter", "mother"].contains(where: text.contains)
        let booking = ["neuen termin", "termin vereinbaren", "termin buchen", "termin verschieben", "new appointment", "book an appointment", "reschedule", "make an appointment", "yeni randevu", "موعد جديد"].contains(where: text.contains)
        guard !booking else { return nil }
        if !medical && mentionsPastAppointment(text) {
            let selected = state.nodes.first { node in
                node.id == context && state.appointments.contains { $0.id == node.appointmentID && $0.date < now }
            }
            if let node = selected ?? state.pastAppointmentToCheckIn(now: now) {
                return entryResponse(for: node, state: state, now: now, language: language)
            }
            return CompanionResponse(text: language.text("Ich finde keinen vergangenen Termin mit offener Teilnahme."))
        }
        let statusWords = ["erledigt", "fertig", "teilgenommen", "verpasst", "noch nicht", "offen", "done", "completed", "finished", "attend", "attended", "missed", "not yet", "open", "status", "tamam", "bitti", "acik", "تم", "انتهيت"]
        if let node = state.nodes.first(where: { $0.id == context }), node.kind == .task || node.appointmentID != nil {
            let labels = ["erledigt", "nicht erledigt", "offen", "noch offen", "teilgenommen", "nicht teilgenommen", "completed", "not done", "open", "still open", "attended", "did not attend"]
            let suffix = node.displayTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT")).replacingOccurrences(of: "’", with: "'")
            let savedAnswer = labels.contains { text == $0 + ": " + suffix }
            let statusQuestion = statusWords.contains { text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b", options: .regularExpression) != nil }
            if savedAnswer || !medical && statusQuestion { return entryResponse(for: node, state: state, now: now, language: language) }
        }
        guard !medical else { return nil }
        let overview = ["was steht heute", "was steht morgen", "was steht an", "was steht als nachstes", "was ist noch offen", "was ist offen", "wie geht es weiter", "meine termine", "meine aufgaben", "nachster termin", "my appointments", "my tasks", "what's next", "what is next", "whats next", "what is planned", "what do i have today", "what do i have scheduled", "what is still open", "upcoming appointments", "aufgabe erledigt", "sirada ne var", "gorevlerim", "randevularim", "ما الخطوة التالية", "مواعيدي", "مهامي"]
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard overview.contains(where: text.contains) || ["heute", "today", "tasks", "appointments", "termine", "aufgaben", "was ist los", "what's going on", "what is going on"].contains(plain) else { return nil }
        let upcoming = ["als nachstes", "nachster termin", "was steht an", "was steht morgen", "wie geht es weiter", "next", "upcoming", "planned", "scheduled", "sirada", "الخطوة التالية"].contains(where: text.contains)
        let today = ["heute", "today", "bugun", "اليوم"].contains(where: text.contains)
        let tasks = ["aufgab", "task", "gorev", "مهام"].contains(where: text.contains)
        if !upcoming && !today && !tasks, let node = state.pastAppointmentToCheckIn(now: now) {
            return entryResponse(for: node, state: state, now: now, language: language)
        }
        let ids = progressEntries(state: state, now: now, upcomingOnly: upcoming)
        return CompanionResponse(text: ids.isEmpty ? language.text("Du hast gerade keine offenen Termine oder Aufgaben.") : language.text("Hier sind deine Termine und Aufgaben. Was hast du schon erledigt?"),
                                 action: ids.isEmpty ? .add(.appointment) : nil, entryIDs: ids)
    }

    private static func mentionsPastAppointment(_ text: String) -> Bool {
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let subjects = ["mein letzter termin", "mein vergangener termin", "my last appointment", "my past appointment", "son randevum", "موعدي السابق"]
        let reports = ["meinen termin verpasst", "meinen termin wahrgenommen", "beim termin gewesen", "war beim termin", "war ich bei meinem letzten termin",
                       "i missed my appointment", "i attended my appointment", "i went to my appointment", "did i go to my last appointment",
                       "randevumu kacirdim", "randevuma gittim", "فاتني موعدي", "حضرت موعدي"]
        return subjects.contains(plain) || reports.contains(where: text.contains)
    }

    private static func progressEntries(state: AppState, now: Date, upcomingOnly: Bool = false) -> [UUID] {
        let current = Set(state.pathDays.first { $0.id == state.currentPathDayID }?.entries.map(\.id) ?? [])
        return state.nodes.filter { node in
            if node.kind == .task {
                if upcomingOnly, let date = node.date, date < state.pathCalendar.startOfDay(for: now) { return false }
                return node.history?.linkedTaskID == nil && node.taskStatus != .completed && node.taskStatus != .cancelled
            }
            if let id = node.appointmentID, let record = state.appointments.first(where: { $0.id == id }) {
                return record.status != .cancelled && record.attendance == .unrecorded &&
                    (record.date >= now || !upcomingOnly && record.needsAttendanceCheck(at: now))
            }
            return false
        }.sorted {
            if current.contains($0.id) != current.contains($1.id) { return current.contains($0.id) }
            let a = abs(($0.date ?? now).timeIntervalSince(now)), b = abs(($1.date ?? now).timeIntervalSince(now))
            if a != b { return a < b }
            return $0.id.uuidString < $1.id.uuidString
        }.prefix(3).map(\.id)
    }

    static func savedCaseResponse(to message: String, state: AppState, language requestedLanguage: ChatLanguage? = nil) -> CompanionResponse? {
        let text = ChatLanguage.normalized(message)
        let language = requestedLanguage ?? ChatLanguage.resolve(message)
        if let other = DemoScenario.matching(message), ![DemoScenario.care, .hospital].contains(other) { return nil }
        let isProgress = ["fehlt", "fehlen", "fortsetzen", "missing", "continue", "progress", "status", "antragsstand", "eksik", "devam", "durum", "ينقص", "متابعة", "حالة طلبي"].contains(where: text.contains)
            || text.range(of: #"\bstand\b"#, options: .regularExpression) != nil
            || (text.contains("weiter") && ["antrag", "vorgang", "mutter", "reha"].contains(where: text.contains))
        guard isProgress else { return nil }
        let choices = [DemoScenario.care, .hospital].filter { state.demoScenarios?[$0.rawValue] != nil }
        let care = ["mutter", "pflegegeld", "mother", "mum", "mom", "annem", "bakim", "والدتي", "امي", "الرعاية"].contains(where: text.contains)
        let hospital = ["reha", "nachsorge", "spital", "entlass", "hospital", "discharge", "taburcu", "rehabilitasyon", "التاهيل", "المستشفى"].contains(where: text.contains)
        let selected = care && !hospital ? DemoScenario.care : hospital && !care ? .hospital : choices.count == 1 ? choices.first : nil
        guard let selected, state.demoScenarios?[selected.rawValue] != nil else {
            guard !choices.isEmpty else { return nil }
            return CompanionResponse(text: language.text("Welchen Vorgang möchtest du fortsetzen?"), caseChoices: choices)
        }
        let missing = state.missingCaseItems(selected, language: language)
        let next = missing.first ?? language.text("Vorbereitung prüfen und den offiziellen Weg zur Einreichung öffnen.")
        return CompanionResponse(text: language.localized("\(selected.title(in: language)): \(missing.count) Vorbereitungspunkte offen. Als Nächstes: \(next)"), action: .scenario(selected))
    }

    private func contains(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }
}
