import Foundation

struct BefundReview {
    let explanation: String
    let passages: [EvidenceReference]
    let actions: [BefundAction]
}

struct BefundAction: Identifiable {
    let id: UUID
    let title: String
    let evidence: EvidenceReference
    let date: Date?
    let formID: String?
    let isCareRequest: Bool
    let caseKind: CaseRecommendation.Kind?
}

struct BefundLifeEvent: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let title: String
    let evidence: EvidenceReference
    let modalityEvidence: [EvidenceReference]
}

enum BefundReader {
    // Read the same UTF-16 offsets that PDFKit recorded. A typed "Seite 3" in a
    // text document is never evidence that a passage actually came from page 3.
    private struct Page {
        let text: NSString
        let number: Int?
    }

    private enum Kind: String {
        case rehab, followUp, therapy, care, allowance, transport, fees, treatmentAppointments, medicineList, appointment, paperwork, enquiry
    }

    private struct Candidate {
        let kind: Kind
        let evidence: EvidenceReference
        let fromChecklist: Bool
        let offset: Int
    }

    private static func isReport(_ document: SourceDocument) -> Bool {
        let titleAndOpening = document.title + "\n" + document.text.prefix(350)
        return contains(titleAndOpening, #"befund|arztbrief|entlassungsbrief|discharge|medical report|radiology report|ultrasound report|clinical findings|epikriz|taburcu|تقرير طبي|تقرير الخروج"#)
    }

    private static func sourcePages(_ document: SourceDocument) -> [Page] {
        let original = document.text as NSString
        let pages = (document.pageSpans ?? []).compactMap { span -> Page? in
            guard span.utf16Length > 0, span.utf16Start >= 0,
                  span.utf16Start <= original.length - span.utf16Length else { return nil }
            return Page(text: original.substring(with: NSRange(location: span.utf16Start, length: span.utf16Length)) as NSString, number: span.pageNumber)
        }
        return pages.isEmpty ? [Page(text: original, number: nil)] : pages
    }

    static func review(_ document: SourceDocument, language: String) -> BefundReview? {
        guard isReport(document) else { return nil }
        let source = sourcePages(document)
        let passages = findings(in: source, document: document)
        let actions = actions(in: source, document: document, language: language)
        let explanation = describe(document, passages: passages, actions: actions, language: language)
        return BefundReview(explanation: explanation, passages: passages, actions: actions)
    }

    private enum EncounterField: String, CaseIterable {
        case outpatient = "Ambulant am"
        case examination = "Untersuchungsdatum"
        case admission = "Aufnahmedatum"
        case discharge = "Entlassungsdatum"
    }

    /// These reports label the encounter separately from report issue, signature and PDF export.
    /// Read the encounter fields in the report header, before findings and plans begin.
    static func lifeEvents(in document: SourceDocument, calendar: Calendar, asOf now: Date,
                           language: String) -> [BefundLifeEvent] {
        guard isReport(document) else { return [] }
        let datePattern = #"(?:\d{4}-\d{2}-\d{2}|\d{1,2}[./]\d{1,2}[./]\d{4}|\d{1,2}\.\h+[\p{L}]+\h+\d{4})"#
        let labels = #"Ambulant\h+am|Untersuchungsdatum|Aufnahmedatum|Entlassungsdatum"#
        let fieldPattern = #"^\h*(("# + labels + #")\b\h*:?\h*(?:\r?\n\h*)?("# + datePattern + #"))(?:\h+(?:FZ:\h*\d+|von \d{1,2}:\d{2} Uhr bis \d{1,2}:\d{2} Uhr))?\h*[.]?\h*$"#
        let narrative = #"^\h*(?:\d+[.]\h*)?(?:Anamnese|Indikation|Aufnahmediagnosen|Vorgeschichte|Beurteilung|Empfehl\w*|Empfohlen\w*|Geplant\w*|Therapieplan|Terminplan\w*|Auftrag|Nachsorge|Offene Aufgaben|Nächste (?:Schritte|Termine)|Planung|Procedere)\b|^\h*Befund\h*:?\h*$"#
        let pages = sourcePages(document)
        let modalities = imagingSources(in: pages, document: document)
        var byField: [EncounterField: [Date: BefundLifeEvent]] = [:]
        for page in pages {
            // A standalone "Befund" on line one can itself be the document title.
            let boundary = matches(narrative, page.text).first { match in
                match.range.location != 0 || clean(page.text.substring(with: match.range)).lowercased() != "befund"
            }
            let header = page.text.substring(to: boundary?.range.location ?? page.text.length) as NSString
            for match in matches(fieldPattern, header) {
                let label = clean(header.substring(with: match.range(at: 2)))
                guard let field = EncounterField.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(label) == .orderedSame }),
                      let date = fieldDate(header.substring(with: match.range(at: 3)), calendar: calendar),
                      byField[field]?[date] == nil else { continue }
                let key = "\(document.id)|encounter|\(field.rawValue)|\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))-\(calendar.component(.day, from: date))"
                let evidence = reference(header.substring(with: match.range(at: 1)), page: page.number, document: document)
                let imageSources = field == .outpatient || field == .examination ? modalities : []
                let title = [encounterTitle(field, language: language), modalityTitle(imageSources, language: language)]
                    .compactMap { $0 }.joined(separator: " · ")
                byField[field, default: [:]][date] = BefundLifeEvent(id: LifePathSeed.stableID(key), date: date,
                    title: title, evidence: evidence, modalityEvidence: imageSources.map(\.evidence))
            }
            if boundary != nil { break }
        }
        // A single-encounter header with conflicting values is ambiguous.
        if let admissions = byField[.admission], admissions.count == 1, let admission = admissions.keys.first,
           let discharges = byField[.discharge], discharges.count == 1, let discharge = discharges.keys.first,
           discharge < admission {
            byField.removeValue(forKey: .admission)
            byField.removeValue(forKey: .discharge)
        }
        let today = calendar.startOfDay(for: now)
        return byField.values.compactMap { dates in
            guard dates.count == 1, let event = dates.values.first, event.date <= today else { return nil }
            return event
        }.sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    private enum Modality: CaseIterable {
        case ultrasound, xray

        var reportHeading: String {
            switch self {
            case .ultrasound: #"(?:US[- ]Befund|Ultraschallbefund|Sonographiebefund)"#
            case .xray: #"(?:R(?:ö|o\u0308|oe)ntgen[- ]?befund)"#
            }
        }
    }

    private struct ModalitySource {
        let kind: Modality
        let evidence: EvidenceReference
    }

    /// Use report titles, named procedure sections and coded services. A clinician's
    /// name, an order for future imaging or a filename alone does not establish modality.
    private static func imagingSources(in pages: [Page], document: SourceDocument) -> [ModalitySource] {
        guard let first = pages.first else { return [] }
        let genericImaging = contains(first.text as String, #"\A\s*Befund Bildgebende Diagnostik\h*(?:\R|$)"#)
        return Modality.allCases.compactMap { kind in
            if let heading = matches(#"\A\s*("# + kind.reportHeading + #")\h*(?:\R|$)"#, first.text).first {
                let quote = first.text.substring(with: heading.range(at: 1))
                return ModalitySource(kind: kind, evidence: reference(quote, page: first.number, document: document))
            }
            guard genericImaging else { return nil }
            let pattern: String
            switch kind {
            case .ultrasound:
                // The procedure is the heading of the findings, not a future recommendation.
                pattern = #"^\h*Befund\h*\R\s*(?:/\w+\s+)?((?:Weichteilsonographie|Sonographie)\h+(?:des|der)\h+[^\r\n]{2,120})\h*$"#
            case .xray:
                pattern = #"^\h*Schlagw(?:ö|o\u0308|oe)rter\h*\(Services\)\s+(R(?:ö|o\u0308|oe)ntgen[.][^\s.]+(?:[.][^\s.]+)*)"#
            }
            for page in pages {
                for match in matches(pattern, page.text) {
                    let quote = page.text.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !contains(quote, #"\b(?:kein\w*|nicht|empfohlen|geplant|vorgesehen|Vorbefund|ausstehend)\b"#) else { continue }
                    return ModalitySource(kind: kind, evidence: reference(quote, page: page.number, document: document))
                }
            }
            return nil
        }
    }

    private static func modalityTitle(_ sources: [ModalitySource], language: String) -> String? {
        switch (sources.contains { $0.kind == .ultrasound }, sources.contains { $0.kind == .xray }) {
        case (true, true): return say(language, "Röntgen- und Ultraschallbefund", "X-ray and ultrasound report", "تقرير الأشعة السينية والموجات فوق الصوتية", "Röntgen ve ultrason raporu")
        case (true, false): return say(language, "Ultraschallbefund", "Ultrasound report", "تقرير الموجات فوق الصوتية", "Ultrason raporu")
        case (false, true): return say(language, "Röntgenbefund", "X-ray report", "تقرير الأشعة السينية", "Röntgen raporu")
        case (false, false): return nil
        }
    }

    private static func encounterTitle(_ field: EncounterField, language: String) -> String {
        switch field {
        case .outpatient: return say(language, "Ambulanter Besuch", "Outpatient visit", "زيارة العيادة الخارجية", "Ayakta muayene")
        case .examination: return say(language, "Untersuchung", "Examination", "فحص", "Muayene")
        case .admission: return say(language, "Aufnahme ins Krankenhaus", "Hospital admission", "دخول المستشفى", "Hastaneye yatış")
        case .discharge: return say(language, "Entlassung aus dem Krankenhaus", "Hospital discharge", "خروج من المستشفى", "Hastaneden taburcu")
        }
    }

    private static func fieldDate(_ raw: String, calendar: Calendar, hour: Int = 0) -> Date? {
        let parts = raw.split { $0.isWhitespace || "./-".contains($0) }
        guard parts.count == 3 else { return nil }
        let iso = parts[0].count == 4
        let months = ["januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember"]
        let monthText = parts[1].lowercased()
        let month = Int(parts[1]) ?? months.firstIndex(of: monthText == "jänner" ? "januar" : monthText).map { $0 + 1 }
        guard let day = Int(parts[iso ? 2 : 0]), let year = Int(parts[iso ? 0 : 2]), let month else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: hour)
        return components.isValidDate(in: calendar) ? calendar.date(from: components) : nil
    }

    static func isAdopted(_ action: BefundAction, in state: AppState) -> Bool {
        state.nodes.contains { node in
            node.id == action.id && node.kind == .task && node.evidence.contains {
                $0.documentID == action.evidence.documentID && $0.quote == action.evidence.quote
            }
        }
    }

    static func caseRecommendations(in document: SourceDocument) -> [CaseRecommendation]? {
        guard let review = review(document, language: "de") else { return nil }
        return review.actions.compactMap { action in
            guard let kind = action.caseKind else { return nil }
            return CaseRecommendation(id: action.evidence.id, kind: kind, evidence: action.evidence)
        }
    }

    static func apply(documentID: UUID, selectedIDs: Set<UUID>, language: String, to state: inout AppState, now: Date) throws {
        guard let document = state.documents.first(where: { $0.id == documentID }),
              let review = review(document, language: language),
              selectedIDs.isSubset(of: Set(review.actions.map(\.id))) else { throw SoviError.invalidAction }
        let selected = review.actions.filter { selectedIDs.contains($0.id) }
        guard selected.allSatisfy({ action in
            !state.nodes.contains(where: { $0.id == action.id }) || isAdopted(action, in: state)
        }) else { throw SoviError.invalidAction }
        for action in selected where !isAdopted(action, in: state) {
            state.nodes.append(PathNode(id: action.id, kind: .task, title: action.title,
                                       detail: action.evidence.quote, evidence: [action.evidence],
                                       createdAt: now, date: action.date))
        }
    }

    private static func contains(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func matches(_ pattern: String, _ text: NSString) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) else { return [] }
        return regex.matches(in: text as String, range: NSRange(location: 0, length: text.length))
    }

    private static func reference(_ quote: String, page: Int?, document: SourceDocument) -> EvidenceReference {
        EvidenceReference(id: LifePathSeed.stableID(document.id.uuidString + (page.map(String.init) ?? "") + quote),
                          documentID: document.id, documentTitle: document.title,
                          locator: page.map { String(localized: "Seite \($0)") } ?? String(localized: "Originaltext"),
                          quote: quote, pageNumber: page)
    }

    // Select the author's summary ahead of the detailed findings; retain several
    // quotations for reports that describe different body regions on the same page.
    private static func findings(in pages: [Page], document: SourceDocument) -> [EvidenceReference] {
        let groups = [
            #"zusammenfassende beurteilung|zusammenfassung\s*/\s*ergebnis|beurteilung|ergebnis|conclusion|impression|sonuç|النتيجة"#,
            #"befund bei entlassung|befund|findings|ultraschall|bulgular|النتائج"#,
            #"empfehlungen|recommendations"#
        ]
        let stop = #"^(?:\d+[.]\s+\S|Allgemeine Daten|Offene Aufgaben|Next steps|Nächste Schritte|Leistung(?:\s|$)|Bei Fragen|Mit freundlichem Gruß|Dokumentinformation|Unterzeichnet von|PDF-Erstellung|Zusätzliche Informationen|Empfehlungen|Medikation|Recommendation[s:]|Seite\s+\d+)"#
        for headers in groups {
            var result: [EvidenceReference] = []
            for page in pages {
                let pattern = #"^[ \t]*(?:\d+[.]\s*)?(?:"# + headers + #")[ \t]*:?[ \t]*(?:\n|$)"#
                for heading in matches(pattern, page.text) {
                    let offset = NSMaxRange(heading.range)
                    let tail = page.text.substring(from: offset)
                    var paragraph: [String] = []
                    func appendParagraph() {
                        let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        paragraph = []
                        guard result.count < 4, joined.count > 5,
                              !contains(joined, #"^(?:/\w+|Indikation\s*:|Befund\s*$|Zusammenfassung\s*/\s*Ergebnis)"#) else { return }
                        // Keep source wording and line breaks; truncate at a word boundary for display.
                        let capped = String(joined.prefix(680))
                        let quote = capped.count == joined.count ? capped : String(capped.prefix(upTo: capped.lastIndex(where: \.isWhitespace) ?? capped.endIndex))
                        if !quote.isEmpty, !result.contains(where: { $0.quote == quote }) {
                            result.append(reference(quote, page: page.number, document: document))
                        }
                    }
                    for line in tail.components(separatedBy: "\n").prefix(60) {
                        if contains(line.trimmingCharacters(in: .whitespaces), stop) { break }
                        if line.trimmingCharacters(in: .whitespaces).isEmpty {
                            appendParagraph()
                        } else {
                            paragraph.append(line)
                        }
                        if result.count == 4 { break }
                    }
                    appendParagraph()
                }
            }
            if !result.isEmpty { return result }
        }
        // Some letters write "Befund: …" on the same line rather than using a section.
        for page in pages {
            let matches = matches(#"^(?:Befund|Beurteilung|Ergebnis|Findings|Impression|Conclusion|Bulgular|Sonuç|النتيجة)[ \t]*:[ \t]*(\S[^\n]{3,500})"#, page.text)
            if !matches.isEmpty {
                return matches.prefix(4).map { reference(page.text.substring(with: $0.range(at: 1)), page: page.number, document: document) }
            }
        }
        // Short letters sometimes have no section headings. Quote explicit
        // observations and exclude surrounding patient/contact headers.
        let observation = #"zeigt(?:en)? sich|zeigte|ergab|kein(?:e|en|er)?\s+(?:akute|hinweis|nachweis)|nicht ausgeschlossen|unverändert|we observed|no evidence|not identified|demonstrated|bulgu saptan|يمكن استبعاد"#
        var prose: [EvidenceReference] = []
        for page in pages {
            var paragraph: [String] = []
            func collect() {
                let block = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                paragraph = []
                guard prose.count < 3, !block.isEmpty, block.count <= 700, contains(block, observation),
                      !contains(block, #"SVNR|versicherungsnummer|geburtsdatum|geb[.]|patient:\s|telefon|@|Kontaktperson"#) else { return }
                prose.append(reference(block, page: page.number, document: document))
            }
            for line in (page.text as String).components(separatedBy: "\n") {
                if line.trimmingCharacters(in: .whitespaces).isEmpty || contains(line, stop) {
                    collect()
                } else {
                    paragraph.append(line)
                    if contains(line, #"[.!?]\s*$"#) { collect() }
                }
            }
            collect()
        }
        return prose
    }

    private static func actions(in pages: [Page], document: SourceDocument, language: String) -> [BefundAction] {
        var candidates: [Candidate] = []
        var inChecklist = false
        for page in pages {
            // The supplied discharge PDF flows its two-column task table over a
            // page break. The text layer interleaves task labels and row owners.
            let boundaries = matches(#"^[ \t]*(?:\d+[.]\s*)?(Offene Aufgaben[^\n]*|Nächste Schritte[ \t]*:?|Next steps[ \t]*:?|Zusammenfassende Beurteilung|Allgemeine Daten|Dokumentinformation)[ \t]*$"#, page.text)
            let tableRanges = rangesForChecklist(page: page, headings: boundaries, initial: inChecklist)
            if let last = boundaries.last {
                inChecklist = isChecklistHeading(page.text.substring(with: last.range(at: 1)))
            }
            let histories = historyRanges(page)
            for rule in rules {
                let prefix = #"(?:^|(?<=[.!?])[ \t]+)[ \t•*–\-]*"#
                let pattern = prefix + "(" + rule.1 + ")(?=[\\s.,;:]|$)"
                for match in matches(pattern, page.text) {
                    let range = match.range(at: 1)
                    if histories.contains(where: { NSLocationInRange(range.location, $0) }) { continue }
                    let inTable = tableRanges.contains { NSLocationInRange(range.location, $0) }
                    let after = page.text.substring(from: NSMaxRange(range))
                    // Keep modifiers such as a stated date, but never absorb the
                    // second column (responsible person) from a PDF table.
                    var fullRange = range
                    if let when = matches(#"\A(?:[ \t]+(?:am|bis(?: zum)?|on|by|für den)[ \t]+(?:\d{1,2}[./]\d{1,2}[./]\d{4}|\d{4}-\d{2}-\d{2}))"#, after as NSString).first {
                        fullRange.length += when.range.length
                    }
                    // Preserve alternatives/ranges verbatim and leave their day
                    // open for review, instead of choosing the first printed date.
                    let dateRemainder = page.text.substring(from: NSMaxRange(fullRange)) as NSString
                    if let alternative = matches(#"\A[ \t]+(?:oder|or|bis|to)[ \t]+(?:(?:am|on|zum)[ \t]+)?(?:\d{1,2}[./]\d{1,2}[./]\d{4}|\d{4}-\d{2}-\d{2})"#, dateRemainder).first {
                        fullRange.length += alternative.range.length
                    }
                    if NSMaxRange(fullRange) < page.text.length, page.text.character(at: NSMaxRange(fullRange)) == 46 {
                        fullRange.length += 1
                    }
                    let quote = page.text.substring(with: fullRange)
                    let remainder = page.text.substring(from: NSMaxRange(fullRange)).prefix(100).trimmingCharacters(in: .whitespaces)
                    let before = page.text.substring(with: NSRange(location: max(0, range.location - 80), length: min(80, range.location)))
                    if remainder.hasPrefix("?") || contains(quote, #"\b(kein\w*|nicht|entfällt|no longer|not|never|cancelled|canceled)\b"#) ||
                       contains(remainder, #"^[,;]?\s*(?:nicht\b|entfällt\b|(?:nur\s+)?(?:wenn|sofern|falls|if)\b|abgesagt\b|not\b|cancelled\b)"#) ||
                       contains(before, #"(?:keine?|nicht|no|not|previously|früher|damals|abgesagt)\s*$"#) { continue }
                    // Narrative prose must contain a directive. In a labelled task
                    // table the action itself can be an infinitive.
                    if !inTable && !isDirective(quote) { continue }
                    candidates.append(Candidate(kind: rule.0, evidence: reference(quote, page: page.number, document: document), fromChecklist: inTable, offset: range.location))
                }
            }
            let requests = additionalRequests(page: page, document: document, checklist: tableRanges, histories: histories)
            for request in requests {
                let overlap = candidates.firstIndex {
                    $0.evidence.pageNumber == request.evidence.pageNumber &&
                        (request.evidence.quote.contains($0.evidence.quote) || $0.evidence.quote.contains(request.evidence.quote))
                }
                if let overlap {
                    // Keep the entire request, including dates and conditions.
                    let known = candidates[overlap]
                    if request.evidence.quote.count > known.evidence.quote.count {
                        candidates[overlap] = Candidate(kind: known.kind, evidence: request.evidence, fromChecklist: known.fromChecklist, offset: min(request.offset, known.offset))
                    }
                } else {
                    candidates.append(request)
                }
            }
        }
        // Use the report author's explicit task list when it repeats earlier
        // recommendations. Two different dated requests remain separate.
        let listedKinds = Set(candidates.filter(\.fromChecklist).map(\.kind))
        var seen: Set<String> = []
        var caseKinds: Set<CaseRecommendation.Kind> = []
        let ordered = candidates.sorted {
            if $0.evidence.pageNumber != $1.evidence.pageNumber {
                return ($0.evidence.pageNumber ?? 0) < ($1.evidence.pageNumber ?? 0)
            }
            return $0.offset < $1.offset
        }
        return ordered.compactMap { item in
            if !item.fromChecklist && listedKinds.contains(item.kind) { return nil }
            let key = item.kind.rawValue + "|" + clean(item.evidence.quote).lowercased()
            guard seen.insert(key).inserted else { return nil }
            let mappedKind: CaseRecommendation.Kind? = switch item.kind {
            case .rehab: .rehabilitation
            case .therapy: .physiotherapy
            case .followUp: .followUp
            default: nil
            }
            let caseKind = mappedKind.flatMap { caseKinds.insert($0).inserted ? $0 : nil }
            // Guided cases and freely imported reports share a single actionable
            // node when they describe the same source recommendation.
            let stableKey = caseKind.map { "case-hospital-" + document.id.uuidString + $0.rawValue }
                ?? (document.id.uuidString + "|" + key)
            return BefundAction(id: LifePathSeed.stableID(stableKey), title: name(item.kind, language),
                                evidence: item.evidence, date: explicitDate(in: item.evidence.quote),
                                formID: item.kind == .rehab ? "kur-reha" : nil,
                                isCareRequest: item.kind == .care || item.kind == .allowance, caseKind: caseKind)
        }
    }

    // Free-text directions and action lists often contain the name of a practice,
    // a deadline or an enclosure between the verb and its object. Keep the whole
    // clause verbatim. Only organizational verbs and objects are eligible.
    private static func additionalRequests(page: Page, document: SourceDocument, checklist: [NSRange], histories: [NSRange]) -> [Candidate] {
        let starts = matches(#"(?:^|(?<=[.!?])[ \t]+)[ \t•*–\-]*(?=(Bitte\b|Please\b|Kindly\b|Lütfen\b|يرجى|Vereinbaren Sie\b|Kontaktieren Sie\b|Arrange\b|Schedule\b|Book\b|Bring\b|Reichen Sie\b|Empfehlung:\s*|Nächster (?:Kontroll)?[Tt]ermin\s*:|Wiedervorstellung\s+(?:am|bei|in)|Follow[- ]up\s+(?:on|with)|Nachkontrolle\s+(?:bei|am)|Kontrolle\s+(?:bei|am)))"#, page.text)
        return starts.compactMap { start in
            let offset = NSMaxRange(start.range)
            if histories.contains(where: { NSLocationInRange(offset, $0) }) { return nil }
            let tail = page.text.substring(with: NSRange(location: offset, length: min(700, page.text.length - offset))) as NSString
            let ends = matches(#"(?:[!?]|\.(?=\s|$))(?=\s*(?:$|[A-ZÄÖÜ•]))|\n[ \t]*\n|\n[ \t]*[•] "#, tail)
            let end = ends.first.map { NSMaxRange($0.range) } ?? tail.length
            // Overlong paragraphs and ambiguous reading order stay in the original.
            guard end < 500 else { return nil }
            let quote = tail.substring(to: end).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !contains(quote, #"\b(?:kein\w*|nicht|abgesagt|entfällt|no longer|never|not|cancelled|canceled|iptal)\b|لا\s+(?:تحجز|تراجع)"#),
                  !contains(quote, #"\b(?:einnehmen|dosieren|dosage|increase your dose|Dosis erhöhen|Therapie abbrechen)\b"#),
                  let kind = organizationalKind(quote) else { return nil }
            return Candidate(kind: kind, evidence: reference(quote, page: page.number, document: document),
                             fromChecklist: checklist.contains { NSLocationInRange(offset, $0) }, offset: offset)
        }
    }

    private static func organizationalKind(_ quote: String) -> Kind? {
        let scheduling = contains(quote, #"vereinbar|anfrag|organisier|abstimmen|book|schedule|arrange|randevu|موعد|Nächster (?:Kontroll)?termin|^Wiedervorstellung|^(?:Nachkontrolle|Kontrolle)\s+(?:am|bei)|^follow[- ]up\s+(?:on|with)"#)
        if contains(quote, #"reha\w*|rehabilitation|rehabilitasyon|التأهيل"#) &&
            contains(quote, #"antrag|application|başvuru|طلب"#) { return .rehab }
        if contains(quote, #"pflegegeld|care allowance|bakım ödeneği|بدل الرعاية"#) &&
            contains(quote, #"antrag|prüf|klär|apply|check|eligib|başvur|طلب"#) { return .allowance }
        if contains(quote, #"einreich|bring|mitnehm|beilegen|vorleg|submit|attach|getirin|أحضر"#) &&
            contains(quote, #"formular|unterlagen|überweisung|befund|dokument|referral|report|document|form|belge|تقرير|وثيقة"#) { return .paperwork }
        if scheduling && contains(quote, #"physiotherap|physio|fizyo|العلاج الطبيعي"#) { return .therapy }
        if scheduling && contains(quote, #"wiedervorstellung|kontroll|follow[- ]?up|kontrol|متابعة"#) { return .followUp }
        if scheduling && contains(quote, #"termin|appointment|randevu|موعد"#) { return .appointment }
        if contains(quote, #"kontaktier|nachfrag|contact|call|anruf|iletişim|اتصل"#) &&
            contains(quote, #"praxis|arzt|ambulanz|ordination|versicherung|beratung|clinic|practice|office|insurer|klinik|عيادة"#) { return .enquiry }
        return nil
    }

    private static func historyRanges(_ page: Page) -> [NSRange] {
        let pattern = #"^[ \t]*(?:\d+[.]\s*)?(Anamnese|Vorgeschichte|Frühere Empfehlungen|Past history|History|Historischer Verlauf|Befund|Entlassung|Empfehlung\w*|Offene Aufgaben[^\n]*|Nächste Schritte|Next steps|Recommendations|Plan|Procedere)[ \t]*:?[ \t]*$"#
        let headings = matches(pattern, page.text)
        var result: [NSRange] = []
        for (index, heading) in headings.enumerated() {
            let text = page.text.substring(with: heading.range(at: 1))
            if contains(text, #"anamnese|vorgeschichte|frühere|history|historisch"#) {
                let start = NSMaxRange(heading.range)
                let end = index + 1 < headings.count ? headings[index + 1].range.location : page.text.length
                result.append(NSRange(location: start, length: end - start))
            }
        }
        return result
    }

    private static func isChecklistHeading(_ value: String) -> Bool {
        contains(value, #"^(?:Offene Aufgaben|Nächste Schritte|Next steps)"#)
    }

    private static func rangesForChecklist(page: Page, headings: [NSTextCheckingResult], initial: Bool) -> [NSRange] {
        var start: Int? = initial ? 0 : nil
        var ranges: [NSRange] = []
        for heading in headings {
            if let start { ranges.append(NSRange(location: start, length: heading.range.location - start)) }
            start = isChecklistHeading(page.text.substring(with: heading.range(at: 1))) ? NSMaxRange(heading.range) : nil
        }
        if let start { ranges.append(NSRange(location: start, length: page.text.length - start)) }
        return ranges
    }

    private static func isDirective(_ quote: String) -> Bool {
        contains(quote, #"\b(?:empfohlen|vereinbaren|vereinbart werden|prüfen|vorbereiten|organisieren|koordinieren|abstimmen|klären|recommended|arrange[d]?|prepare|schedule|book|vereinbart am|Termin am)\b"#)
    }

    // Only organizational acts with their object. Terms in an indication,
    // diagnosis, medicine list, or history cannot imply an order or due date.
    private static let rules: [(Kind, String)] = [
        (.rehab, #"(?:Eine\s+(?:ambulante|stationäre)\s+Rehabilitation\s+wird\s+empfohlen|Wir\s+empfehlen\s+eine\s+(?:ambulante|stationäre)\s+Rehabilitation|(?:Outpatient|Inpatient)\s+rehabilitation\s+is\s+recommended|(?:Rehabilitationsantrag|Reha[- ]Antrag)\s+vorbereiten|Prepare\s+(?:the\s+)?rehabilitation\s+application)"#),
        (.followUp, #"(?:Termin\s+zur\s+(?:hausärztlichen|ärztlichen|fachärztlichen)\s+(?:Nach)?[Kk]ontrolle\s+vereinbaren|(?:Eine\s+)?(?:ärztliche\s+)?Nachkontrolle\s+(?:soll\s+vereinbart\s+werden|wird\s+empfohlen|vereinbaren)|(?:Bitte\s+)?(?:einen\s+)?(?:Kontrolltermin|Nachkontrolltermin)\s+vereinbaren|A\s+medical\s+follow[- ]up\s+appointment\s+should\s+be\s+arranged|(?:Please\s+)?(?:Arrange|Book|Schedule)\s+(?:a\s+)?follow[- ]up(?:\s+appointment)?)"#),
        (.therapy, #"(?:Eine\s+)?Physiotherapie\s+(?:wird\s+empfohlen|organisieren)|Physiotherapy\s+is\s+recommended"#),
        (.allowance, #"(?:Pflegegeldanspruch|Anspruch\s+auf\s+Pflegegeld)\s+prüfen"#),
        (.care, #"(?:Mobile\s+Hauskrankenpflege|Mobile\s+Pflege)\s+organisieren"#),
        (.transport, #"Fahrtmöglichkeiten\s+zu\s+Behandlungsterminen\s+klären"#),
        (.fees, #"Rezeptgebührenbefreiung\s+prüfen"#),
        (.treatmentAppointments, #"(?:Weitere\s+)?Bestrahlungstermine\s+koordinieren"#),
        (.medicineList, #"(?:Aktuellen\s+)?Medikationsplan\s+(?:mit\s+der\s+Hausärztin\s+)?abstimmen"#),
        (.appointment, #"(?:Bitte\s+)?(?:einen\s+)?Termin\s+(?:bei\s+[^.;\n]{2,70}\s+)?vereinbaren|(?:Please\s+)?(?:Arrange|Schedule|Book)\s+(?:an?\s+)?appointment(?:\s+with\s+[^.;\n]{2,60})?"#)
    ]

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func explicitDate(in quote: String) -> Date? {
        let input = quote as NSString
        let dates = matches(#"\b(?:\d{1,2}[./]\d{1,2}[./]\d{4}|\d{4}-\d{2}-\d{2})\b"#, input)
        guard dates.count == 1 else { return nil }
        let found = matches(#"(?:\b(?:am|bis(?: zum)?|on|by|für den)\s+|(?:termin|appointment)\s*:\s*)(\d{1,2}[./]\d{1,2}[./]\d{4}|\d{4}-\d{2}-\d{2})\b"#, input)
        guard found.count == 1 else { return nil }
        let value = input.substring(with: found[0].range(at: 1))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return fieldDate(value, calendar: calendar, hour: 12)
    }

    private static func say(_ code: String, _ de: String, _ en: String, _ ar: String, _ tr: String) -> String {
        switch code.lowercased().prefix(2) {
        case "en": return en
        case "ar": return ar
        case "tr": return tr
        default: return de
        }
    }

    private static func name(_ kind: Kind, _ code: String) -> String {
        switch kind {
        case .rehab: return say(code, "Reha-Antrag mit der Praxis vorbereiten", "Prepare the rehabilitation application with the practice", "تحضير طلب إعادة التأهيل مع العيادة", "Rehabilitasyon başvurusunu klinikle hazırlayın")
        case .followUp: return say(code, "Kontrolltermin vereinbaren", "Arrange the follow-up appointment", "ترتيب موعد المتابعة", "Kontrol randevusu ayarlayın")
        case .therapy: return say(code, "Physiotherapie organisieren", "Arrange physiotherapy", "تنظيم العلاج الطبيعي", "Fizyoterapiyi organize edin")
        case .care: return say(code, "Mobile Pflege organisieren", "Arrange home nursing", "تنظيم الرعاية التمريضية المنزلية", "Evde bakım hizmeti ayarlayın")
        case .allowance: return say(code, "Pflegegeldanspruch klären", "Check care allowance eligibility", "الاستفسار عن استحقاق بدل الرعاية", "Bakım ödeneği koşullarını araştırın")
        case .transport: return say(code, "Fahrten zur Behandlung klären", "Check transport options for treatment", "الاستفسار عن النقل إلى مواعيد العلاج", "Tedaviye ulaşım seçeneklerini araştırın")
        case .fees: return say(code, "Rezeptgebührenbefreiung prüfen", "Check prescription fee exemption", "الاستفسار عن الإعفاء من رسوم الوصفات", "Reçete ücretinden muafiyet koşullarını araştırın")
        case .treatmentAppointments: return say(code, "Bestrahlungstermine abstimmen", "Coordinate radiotherapy appointments", "تنسيق مواعيد العلاج الإشعاعي", "Radyoterapi randevularını koordine edin")
        case .medicineList: return say(code, "Medikationsplan mit der Praxis abstimmen", "Review the medication list with the practice", "مراجعة قائمة الأدوية مع العيادة", "İlaç listesini klinikle gözden geçirin")
        case .paperwork: return say(code, "Genannte Unterlagen vorbereiten", "Prepare the documents named in the report", "تحضير المستندات المذكورة في التقرير", "Raporda belirtilen belgeleri hazırlayın")
        case .enquiry: return say(code, "Genannte Stelle kontaktieren", "Contact the service named in the report", "التواصل مع الجهة المذكورة في التقرير", "Raporda belirtilen birimle iletişime geçin")
        case .appointment: return say(code, "Termin vereinbaren", "Arrange an appointment", "ترتيب موعد", "Randevu ayarlayın")
        }
    }

    private static func describe(_ document: SourceDocument, passages: [EvidenceReference], actions: [BefundAction], language: String) -> String {
        let source = document.title + "\n" + document.text.prefix(350)
        let intro: String
        if contains(source, #"entlass|discharge|epikriz|taburcu|الخروج"#) {
            intro = say(language, "Der Brief fasst den Krankenhausaufenthalt und die weitere Betreuung zusammen.", "The letter summarizes the hospital stay and the care planned after discharge.", "تلخص الرسالة الإقامة في المستشفى والرعاية المخطط لها بعد الخروج.", "Mektup hastanede kalış sürecini ve taburculuk sonrası planlanan bakımı özetliyor.")
        } else {
            intro = say(language, "Dieser Befund hält fest, was bei der Untersuchung beschrieben wurde.", "This report records what the examination team observed.", "يسجل التقرير ما وصفه الفريق أثناء الفحص.", "Bu rapor, ekibin muayene sırasında kaydettiği bulguları içeriyor.")
        }
        let excerpt = passages.map { clean($0.quote) }.joined(separator: "\n")
        var parts = [intro]
        if !excerpt.isEmpty {
            parts.append(say(language, "Im Original steht:", "The report says:", "ورد في التقرير:", "Raporda şöyle yazıyor:") + "\n„" + excerpt + "“")
            // Explain how the clinician qualified a statement. Keep the full
            // passage alongside the explanation, including negation and side.
            let qualifiers: [(String, String)] = [
                (#"\b(?:v\.\s*a\.|verdacht auf|suspected)\s+"#, say(language, "Der Ausdruck „Verdacht auf“ (V. a.) bezeichnet eine Vermutung der Verfasser.", "A suspicion (Verdacht auf or V. a.) is a possibility the authors mention.", "تدل عبارة Verdacht auf أو V. a. على احتمال يذكره كاتبو التقرير.", "Verdacht auf veya V. a. ifadesi, raporu yazanların bir olasılıktan söz ettiğini gösterir.")),
                (#"\b(?:nicht (?:sicher |vollständig )?aus(?:ge)?schließ(?:bar|en)|nicht (?:sicher )?ausgeschlossen|cannot (?:be excluded|rule out)|cannot be ruled out)\b"#, say(language, "„Nicht ausgeschlossen“ bedeutet, dass die Frage laut Bericht offen bleibt.", "When the authors say something cannot be ruled out, they leave that question open.", "عندما يقول التقرير إنه لا يمكن الاستبعاد، فالمسألة تبقى مفتوحة.", "Raporda dışlanamadığı belirtilen bir durum için soru açık kalmış demektir.")),
                (#"\b(?:kein (?:sicherer )?(?:hinweis|nachweis) (?:auf|für|von)|no evidence of)\b"#, say(language, "Mit „kein Hinweis“ oder „kein Nachweis“ beschreiben die Verfasser, was sie in dieser Untersuchung nicht festgestellt haben.", "No evidence of describes what the authors did not find in this examination.", "تشير عبارة «لا دليل على» إلى ما لم يجده الكُتّاب في هذا الفحص.", "Bulgu saptanmadı ifadesi, ekibin bu incelemede neyi görmediğini anlatır."))
            ]
            parts.append(contentsOf: qualifiers.filter { contains(excerpt, $0.0) }.prefix(2).map(\.1))
            let terms: [(String, String)] = [
                (#"\blipom\w*\b"#, say(language, "Lipom bezeichnet einen Knoten aus Fettgewebe.", "Lipom means a lump made of fatty tissue.", "يعني Lipom كتلة من نسيج دهني.", "Lipom, yağ dokusundan oluşan bir kitle demektir.")),
                (#"fraktur|fracture"#, say(language, "Fraktur bedeutet Knochenbruch.", "Fraktur means a broken bone.", "تعني Fraktur كسراً في العظم.", "Fraktur, kemik kırığı demektir.")),
                (#"hämatom|hematoma"#, say(language, "Hämatom bedeutet Bluterguss.", "Hämatom means a collection of blood, also called a bruise.", "تعني Hämatom تجمعاً دموياً أو كدمة.", "Hämatom, bir bölgede kan toplanması anlamına gelir.")),
                (#"sonograph|ultraschall"#, say(language, "Sonographie bedeutet Ultraschalluntersuchung.", "Sonographie means an ultrasound examination.", "تعني Sonographie الفحص بالموجات فوق الصوتية.", "Sonographie, ultrason muayenesi anlamına gelir.")),
                (#"subkutan"#, say(language, "Subkutan bedeutet unter der Haut.", "Subkutan means beneath the skin.", "تعني subkutan تحت الجلد.", "Subkutan, deri altında demektir.")),
                (#"\bBWS\b|\bLWS\b"#, say(language, "BWS und LWS stehen für Brust- und Lendenwirbelsäule.", "BWS and LWS refer to the middle and lower spine.", "يشير BWS وLWS إلى الفقرات الصدرية والقطنية.", "BWS ve LWS, omurganın sırt ve bel bölgelerini belirtir.")),
                (#"Subluxation"#, say(language, "Subluxation heißt, dass ein Gelenk teilweise aus seiner normalen Position verschoben ist.", "Subluxation is the term for a joint partly slipping out of place.", "يعني مصطلح Subluxation تحرك المفصل جزئياً عن موضعه.", "Subluxation, eklemin yerinden kısmen kayması anlamına gelir.")),
                (#"Kompression"#, say(language, "Kompression bedeutet Druck auf eine Struktur.", "Kompression means pressure on a structure.", "تعني Kompression الضغط على بنية في الجسم.", "Kompression, bir yapıya baskı uygulanması anlamına gelir.")),
                (#"ambulant"#, say(language, "Ambulant heißt, dass die Betreuung ohne stationäre Aufnahme erfolgt.", "Ambulant means outpatient care.", "تعني ambulant رعاية دون إقامة في المستشفى.", "Ambulant, hastaneye yatmadan ayakta bakım demektir."))
            ]
            parts.append(contentsOf: terms.filter { contains(excerpt, $0.0) }.prefix(3).map(\.1))
        }
        if passages.isEmpty && actions.isEmpty {
            parts.append(say(language, "Ich konnte keinen klar gekennzeichneten Ergebnisabschnitt finden. Öffne das Original für den vollständigen Wortlaut.", "I could not identify a clearly marked findings section. Open the original for the complete wording.", "لم أجد قسماً واضحاً للنتائج. افتح المستند الأصلي لقراءة النص كاملاً.", "Belirgin bir bulgular bölümü bulamadım. Tam metin için asıl belgeyi açın."))
        }
        if actions.isEmpty {
            parts.append(say(language, "Ich finde keinen ausdrücklich genannten organisatorischen Auftrag. Die genaue Bedeutung kann dir die behandelnde Praxis erläutern.", "I found no explicit organizational instruction. Your treating practice can explain what the findings mean for you.", "لم أجد طلباً تنظيمياً صريحاً. يمكن للعيادة المعالجة شرح معنى النتائج بالنسبة إليك.", "Açıkça belirtilmiş bir idari adım bulamadım. Bulguların sizin için anlamını tedavi ekibiniz açıklayabilir."))
        } else {
            parts.append(say(language, "Diese Schritte nennt der Bericht:", "The report names these next steps:", "يذكر التقرير الخطوات التالية:", "Rapor şu adımları belirtiyor:") + "\n" + actions.map { "• " + $0.title }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }
}
