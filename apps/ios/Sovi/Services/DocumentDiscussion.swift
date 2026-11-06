import Foundation

/// Every answer and action in this conversation comes from the selected local document.
enum DocumentDiscussion {
    struct Reply {
        var documentID: UUID?
        var response: CompanionResponse
    }

    struct AttachmentReceipt: Identifiable {
        let attachment: ConversationTurn
        let reply: ConversationTurn
        var id: UUID { attachment.id }
    }

    static func attachments(in state: AppState) -> [AttachmentReceipt] {
        zip(state.conversation, state.conversation.dropFirst()).compactMap { attachment, reply in
            guard attachment.role == "user", let id = attachment.attachmentDocumentID,
                  reply.role == "assistant", reply.attachmentEventIDs != nil,
                  reply.replyDocumentID == nil || reply.replyDocumentID == id else { return nil }
            return AttachmentReceipt(attachment: attachment, reply: reply)
        }
    }

    enum Reading {
        case vaccinations(VaccinationPassReview)
        case report(BefundReview)
        case other
    }

    static func read(_ document: SourceDocument, language: ChatLanguage, calendar: Calendar) -> Reading {
        if document.id == LifePathSeed.stableID("life-path-33-source") || !document.proposals.isEmpty { return .other }
        if let pass = VaccinationImport.review(document, calendar: calendar) { return .vaccinations(pass) }
        if let report = BefundReader.review(document, language: language.rawValue) { return .report(report) }
        return .other
    }

    static func summary(_ document: SourceDocument, language: ChatLanguage, state: AppState, question: String = "") -> CompanionResponse {
        let query = normalize(question)
        let wantsSteps = matches(query, ["schritt", "erledigen", "aufgab", "als nachstes", "to do", "next", "actions", "task", "adım", "yapmal", "خطو", "مهام"])
        let wantsForm = matches(query, ["formular", "antrag", "form", "başvuru", "طلب", "استمارة"])
        let action = CompanionAction.reviewDocument(document.id)
        switch read(document, language: language, calendar: state.pathCalendar) {
        case .report(let report):
            let actionable = report.actions.map { item in
                let marker = BefundReader.isAdopted(item, in: state) ? "✓ " : "• "
                return marker + item.title + (item.evidence.pageNumber.map { " (\(language.text("Seite")) \($0))" } ?? "")
            }
            var lines: [String] = []
            if !wantsSteps && !wantsForm { lines.append(report.explanation) }
            if wantsForm {
                let ids = Set(report.actions.compactMap(\.formID))
                let catalog = (try? PrototypeForm.load()) ?? []
                let titles = catalog.filter { ids.contains($0.id) }.map(\.title)
                lines.append(titles.isEmpty ? language.text("Für diese Schritte ist kein eindeutiger Formularvorschlag verfügbar.") :
                                language.text("Passendes Formular") + ": " + titles.joined(separator: ", "))
            }
            if (wantsSteps || wantsForm) && !actionable.isEmpty {
                lines.append(language.text("Schritte aus dem Befund") + "\n" + actionable.joined(separator: "\n"))
            } else if wantsSteps {
                lines.append(language.text("Ich finde keinen ausdrücklichen organisatorischen Auftrag in diesem Befund."))
            }
            return CompanionResponse(text: String(lines.joined(separator: "\n\n").prefix(16_000)), evidence: report.passages, action: action)
        case .vaccinations(let pass):
            var entries = pass.entries.sorted { $0.date < $1.date }
            let disease = entries.map { diseaseName($0.record.disease) }.first { !$0.isEmpty && query.contains($0) }
                ?? (matches(query, ["flu ", "grippe", "grip aşı", "إنفلونزا"]) ? "influenza" : nil)
            if let disease { entries = entries.filter { diseaseName($0.record.disease) == disease } }
            if matches(query, ["last vaccin", "most recent", "letzte impf", "son aşı", "آخر تطعيم"]) {
                entries = Array(entries.suffix(1))
            }
            let rows = entries.prefix(20).map { item in
                let prefix = VaccinationImport.isRecorded(item, in: state, document: document) ? "✓ " : "• "
                return prefix + [item.record.administrationText, item.record.disease, item.record.product]
                    .filter { !$0.isEmpty }.joined(separator: " · ")
            }
            var lines = [language.text("Dokumentierte Impfungen") + ": \(entries.count)"] + rows
            if pass.entries.isEmpty || pass.unreadableRows > 0 { lines.append(language.text("Bitte unvollständige Zeilen im Original prüfen.")) }
            if !pass.entries.isEmpty { lines.append(language.text("Im Dokument kannst du die Impfungen für deinen Pfad auswählen.")) }
            return CompanionResponse(text: lines.joined(separator: "\n"), action: action)
        case .other:
            return CompanionResponse(text: document.displayTitle + "\n" + language.text("Öffne das Dokument, um den Originaltext zu lesen."), action: action)
        }
    }

    static func reply(to message: String, state: AppState, language: ChatLanguage) -> Reply? {
        let query = normalize(message)
        let wantsPass = matches(query, ["impfpass", "vaccination record", "vaccine record", "vaccination pass", "ası kart", "asi kart", "aşı kart", "سجل التطعيم", "دفتر اللقاح"])
        let wantsReport = matches(query, ["befund", "entlassungsbrief", "medical report", "discharge letter", "discharge report", "radiology report", "tıbbi rapor", "taburcu", "تقرير طبي", "تقرير الخروج"])
        let wantsNew = matches(query, ["hochladen", "importier", "hinzufügen", "neuen befund", "upload", "attach", "import", "new report", "yükle", "رفع", "أرفق"])
        let current = state.discussedDocumentID.flatMap { id in state.documents.first { $0.id == id } }
        if let current, let response = eventReply(query: query, document: current, state: state, language: language) {
            return Reply(documentID: current.id, response: response)
        }
        let followUp = current != nil && matches(query, ["dies", "das bedeut", "erklär", "schritt", "formular", "bericht", "original", "aufgabe", "what does", "what about", "this mean", "explain", "what next", "next step", "what should", "action", "which form", "vaccin", "impfung", "letzte dosis", "last dose", "açıkla", "adım", "sonraki", "rapor", "اشرح", "الخطوة", "ماذا يعني"])
        guard wantsPass || wantsReport || followUp else { return nil }

        // A new upload or an ambiguous reference always leads to an explicit source choice.
        let candidates = state.documents.filter { document in
            if document.id == current?.id { return true }
            return document.fixtureID == nil && document.id != LifePathSeed.stableID("life-path-33-source")
        }.filter { document in
            if followUp && !wantsReport && !wantsPass { return document.id == current?.id }
            switch read(document, language: language, calendar: state.pathCalendar) {
            case .vaccinations: return wantsPass
            case .report: return wantsReport
            case .other: return false
            }
        }
        if !wantsNew, let selected = candidates.first(where: { $0.id == current?.id }) ?? (candidates.count == 1 ? candidates.first : nil) {
            return Reply(documentID: selected.id, response: summary(selected, language: language, state: state, question: message))
        }
        return Reply(documentID: nil, response: CompanionResponse(text: language.text("Wähle das Dokument aus, das wir gemeinsam ansehen sollen."), action: .documents))
    }

    private static func eventReply(query: String, document: SourceDocument, state: AppState, language: ChatLanguage) -> CompanionResponse? {
        let eventQuestions = ["ereignis", "im pfad", "lebenspfad", "wann war", "wann fand", "wann wurde", "welches datum",
                              "an welchem tag", "hinzugefugt", "events", "on my path", "did you add", "what date",
                              "which date", "what day", "when was", "when did", "what happened", "olay", "hangi tarih",
                              "ne zaman", "yoluma", "أحداث", "احداث", "مساري", "ما التاريخ", "متى كان", "في أي تاريخ"]
        guard matches(query, eventQuestions),
              let receipt = attachments(in: state).last(where: { $0.attachment.attachmentDocumentID == document.id }) else { return nil }
        let nodes = (receipt.reply.attachmentEventIDs ?? []).compactMap { id in
            state.nodes.first { $0.id == id && $0.evidence.contains { $0.documentID == document.id } }
        }.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        guard !nodes.isEmpty else {
            return CompanionResponse(text: receipt.reply.text, action: .reviewDocument(document.id))
        }
        var format = Date.FormatStyle().day().month(.abbreviated).year()
        format.calendar = state.pathCalendar
        format.timeZone = state.pathCalendar.timeZone
        format.locale = Locale(identifier: language.rawValue)
        let lines = nodes.prefix(3).map { node in
            [node.dateOnPath(in: state.pathCalendar).map { $0.formatted(format) }, node.displayTitle].compactMap { $0 }.joined(separator: " · ")
        }
        return CompanionResponse(text: ([language.text("Ereignisse im Pfad")] + lines).joined(separator: "\n"),
                                 action: .reviewDocument(document.id), entryIDs: nodes.map(\.id))
    }

    private static func diseaseName(_ value: String) -> String {
        normalize(String(value.prefix { $0 != "(" })).trimmingCharacters(in: .whitespaces)
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT")).lowercased()
    }

    private static func matches(_ text: String, _ fragments: [String]) -> Bool {
        fragments.contains { text.contains(normalize($0)) }
    }
}
