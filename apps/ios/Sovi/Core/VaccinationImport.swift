import Foundation

struct VaccinationCandidate: Identifiable, Equatable {
    var id: UUID {
        LifePathSeed.stableID("vaccination-row|\(evidence.id)|\(record.doseLabel)")
    }
    let date: Date
    var record: VaccinationRecord
    let evidence: EvidenceReference
    var columnEvidence: EvidenceReference?
}

struct VaccinationPassReview {
    let holder: String?
    let entries: [VaccinationCandidate]
    let unreadableRows: Int
}

/// Reads recorded administrations from the labelled rows in an Austrian e-Impfpass.
/// A registration date, a dose heading, or the pass's creation date cannot start a record.
enum VaccinationImport {
    static func review(_ document: SourceDocument, calendar: Calendar, asOf now: Date = .now) -> VaccinationPassReview? {
        let text = document.text as NSString
        let namedPass = document.title.range(of: #"impfpass|vaccination (?:record|pass|certificate)"#, options: [.regularExpression, .caseInsensitive]) != nil
        let hasPassHeading = document.text.prefix(1024).split(whereSeparator: \.isNewline).contains { line in
            line.range(of: #"^(?:(?:elektronischer|internationaler) )?(?:e[- ]?)?impfpass\b|^vaccination (?:record|pass|certificate)\b"#,
                       options: [.regularExpression, .caseInsensitive]) != nil
        }
        guard namedPass || hasPassHeading else { return nil }
        let spans = document.pageSpans ?? bundledPageSpans(document)
        let pages: [(Int?, String)] = spans.isEmpty ? [(nil, document.text)] : spans.compactMap { span in
            guard span.utf16Start >= 0, span.utf16Length >= 0, span.utf16Length <= text.length,
                  span.utf16Start <= text.length - span.utf16Length else { return nil }
            return (span.pageNumber, text.substring(with: NSRange(location: span.utf16Start, length: span.utf16Length)))
        }

        var entries = [VaccinationCandidate]()
        var unreadable = 0
        var holders: [String] = []
        var disease: String?
        for (page, content) in pages {
            let lines = content.components(separatedBy: "\n")
            for line in lines where line.hasPrefix("Person:") || line.hasPrefix("Patient:") {
                if !holders.contains(line) { holders.append(line) }
            }
            var group: [VaccinationCandidate?] = []
            var columnDetails: [(dose: String, location: String, quote: String)] = []
            func finishGroup() {
                // PDFKit extracts the right-hand column after the complete left column.
                // Pair only when every row has a counterpart, including rejected rows.
                if !group.isEmpty && group.count == columnDetails.count {
                    for i in group.indices {
                        let column = columnDetails[i]
                        group[i]?.record.doseLabel = column.dose
                        group[i]?.record.location = column.location
                        if let candidateID = group[i]?.id {
                            group[i]?.columnEvidence = EvidenceReference(id: LifePathSeed.stableID("vaccine-column-\(candidateID)"),
                                documentID: document.id, documentTitle: document.title,
                                locator: column.location, quote: column.quote, pageNumber: page)
                        }
                    }
                }
                entries.append(contentsOf: group.compactMap { $0 })
                unreadable += group.filter { $0 == nil }.count
                group.removeAll()
                columnDetails.removeAll()
            }

            for i in lines.indices {
                let line = lines[i]
                if line.range(of: #"^(?:empfohlene|geplante|fällige|vorgemerkte) Impfungen|^Impfempfehlungen|^planned vaccinations"#,
                              options: [.regularExpression, .caseInsensitive]) != nil {
                    break // Only documented administrations belong on the path.
                }
                if let field = productField(in: line) {
                    if i > 0, let heading = sectionHeading(lines[i - 1]) {
                        finishGroup()
                        disease = heading
                    }
                    let first = String(line[field.lowerBound...])
                    var block = [first]
                    var end = i + 1
                    while end < lines.count, isAdministrationField(lines[end]) || lines[end].trimmingCharacters(in: .whitespaces).isEmpty {
                        block.append(lines[end])
                        end += 1
                    }
                    while block.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { block.removeLast() }
                    let candidate = parseRow(block, disease: disease, document: document, page: page, calendar: calendar, now: now)
                    group.append(candidate)
                } else if let marker = line.range(of: "Impfort:", options: .caseInsensitive) {
                    let dose = line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
                    let place = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
                    let nextLine = i + 1 < lines.count ? lines[i + 1] : ""
                    if nextLine.range(of: #"^\d{4}\s+\p{L}"#, options: .regularExpression) != nil {
                        columnDetails.append((dose, [place, nextLine].joined(separator: ", "), line + "\n" + nextLine))
                    } else {
                        columnDetails.append((dose, place, line))
                    }
                }
            }
            finishGroup()
        }
        // A continuation page may carry the full name in a Patient: line while the
        // cover uses a shortened Person: line. Distinct persons in either position
        // require separate imports. The selected path never changes its profile.
        if ["Person:", "Patient:"].contains(where: { prefix in holders.filter { $0.hasPrefix(prefix) }.count > 1 }) {
            return VaccinationPassReview(holder: holders.joined(separator: "\n"), entries: [], unreadableRows: unreadable + entries.count)
        }
        var seen = Set<UUID>()
        return VaccinationPassReview(holder: holders.first, entries: entries.filter { seen.insert($0.id).inserted }, unreadableRows: unreadable)
    }

    /// The bundled, byte-verified transcription predates stored page ranges. Its
    /// own page labels are trusted only for this bundled source, never pasted text.
    private static func bundledPageSpans(_ document: SourceDocument) -> [DocumentPageSpan] {
        guard document.fixtureID == VaccinationPassSeed.resourceName,
              document.bundledPDFName == VaccinationPassSeed.resourceName else { return [] }
        let text = document.text as NSString
        let separator = text.range(of: "\n\nSeite 2\n")
        guard document.text.hasPrefix("Seite 1\n"), separator.location != NSNotFound else { return [] }
        let start = ("Seite 1\n" as NSString).length
        let next = NSMaxRange(separator)
        return [
            DocumentPageSpan(pageNumber: 1, utf16Start: start, utf16Length: separator.location - start),
            DocumentPageSpan(pageNumber: 2, utf16Start: next, utf16Length: text.length - next)
        ]
    }

    static func apply(documentID: UUID, selectedIDs: Set<UUID>, to state: inout AppState, now: Date) throws {
        guard let document = state.documents.first(where: { $0.id == documentID }),
              let review = review(document, calendar: state.pathCalendar, asOf: now),
              !selectedIDs.isEmpty, selectedIDs.isSubset(of: Set(review.entries.map(\.id))) else {
            throw SoviError.invalidAction
        }
        _ = record(review.entries.filter { selectedIDs.contains($0.id) }, from: document, in: &state, now: now)
    }

    /// Return the actual path IDs, including seeded or reissued records that already exist.
    static func record(_ entries: [VaccinationCandidate], from document: SourceDocument, in state: inout AppState, now: Date) -> [UUID] {
        var ids: [UUID] = []
        for entry in entries {
            if let existing = sameSourceIndex(for: entry, in: state, document: document)
                ?? matchingReissue(entry, in: state, document: document) {
                if !state.nodes[existing].evidence.contains(where: { $0.documentID == document.id && $0.quote == entry.evidence.quote }) {
                    state.nodes[existing].evidence.append(entry.evidence)
                    if let column = entry.columnEvidence { state.nodes[existing].evidence.append(column) }
                }
                state.nodes[existing].vaccination?.importedFromPass = true
                state.nodes[existing].vaccination?.administrationDay = entry.record.administrationDay
                ids.append(state.nodes[existing].id)
                continue
            }
            var record = entry.record
            record.importedFromPass = true
            state.nodes.append(PathNode(id: entry.id, kind: .event, title: record.disease.isEmpty ? record.product : record.disease,
                detail: [record.product, record.doseLabel].filter { !$0.isEmpty }.joined(separator: " · "), chapter: 4,
                evidence: [entry.evidence] + [entry.columnEvidence].compactMap { $0 }, createdAt: now,
                date: entry.date, vaccination: record))
            ids.append(entry.id)
        }
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    /// Seeded entries become visible on the compact path when first accepted by the user.
    static func isRecorded(_ candidate: VaccinationCandidate, in state: AppState, document: SourceDocument) -> Bool {
        guard let index = sameSourceIndex(for: candidate, in: state, document: document) else { return false }
        return state.nodes[index].vaccination?.importedFromPass == true
    }

    private static func sameSourceIndex(for candidate: VaccinationCandidate, in state: AppState, document: SourceDocument) -> Int? {
        state.nodes.firstIndex { node in
            if node.id == candidate.id { return true }
            // The demo already contains rows from its own pass under stable seed IDs.
            return node.evidence.contains { $0.documentID == document.id && $0.quote == candidate.evidence.quote }
                && node.vaccination?.product == candidate.record.product && node.date == candidate.date
                && node.vaccination?.doseLabel == candidate.record.doseLabel
                && node.vaccination.map { diseaseKey($0.disease) == diseaseKey(candidate.record.disease) } == true
        }
    }

    /// A regenerated pass may include older rows again. Preserve both source links
    /// only after review, and only when holder, administration and product agree.
    private static func matchingReissue(_ entry: VaccinationCandidate, in state: AppState, document: SourceDocument) -> Int? {
        guard let holder = holderIdentity(in: document), !entry.record.batch.isEmpty else { return nil }
        let matches = state.nodes.indices.filter { index in
            let node = state.nodes[index]
            guard let prior = node.vaccination, let date = node.date,
                  prior.hasDocumentedTime == entry.record.hasDocumentedTime,
                  normalized(prior.product) == normalized(entry.record.product),
                  normalized(prior.batch) == normalized(entry.record.batch),
                  diseaseKey(prior.disease) == diseaseKey(entry.record.disease),
                  prior.productNumber == entry.record.productNumber,
                  prior.doseLabel == entry.record.doseLabel else { return false }
            if entry.record.hasDocumentedTime {
                guard date == entry.date else { return false }
            } else {
                guard date == entry.date || prior.administrationDay == entry.record.administrationDay,
                      !entry.record.recordedAtText.isEmpty,
                      prior.recordedAtText == entry.record.recordedAtText else { return false }
            }
            return node.evidence.contains { evidence in
                guard let source = state.documents.first(where: { $0.id == evidence.documentID }) else { return false }
                return holderIdentity(in: source) == holder
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    private static func diseaseKey(_ title: String) -> String {
        // Exported headings sometimes add a parenthetical explanation to the disease.
        normalized(String(title.prefix(while: { $0 != "(" })))
    }

    private static func normalized(_ field: String) -> String {
        field.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func holderIdentity(in document: SourceDocument) -> String? {
        let lines = document.text.prefix(2000).split(whereSeparator: \.isNewline).map { normalized(String($0)) }
        guard let person = lines.first(where: { $0.hasPrefix("person:") || $0.hasPrefix("patient:") }),
              person.contains("geb.") || person.contains("geboren am") else { return nil }
        // This key exists only during matching. A different/missing ID or holder
        // line prevents merging. Neither the file name nor the active profile is an identifier.
        let insurance = lines.first(where: { $0.hasPrefix("sozialversicherungsnummer:") }) ?? ""
        return person + "|" + insurance
    }

    private static func productField(in line: String) -> Range<String.Index>? {
        guard let field = line.range(of: #"(?i)(?<![\p{L}])(?:Impfstoff|Vaccine):"#, options: .regularExpression) else { return nil }
        let prefix = line[..<field.lowerBound].trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty || prefix.first?.isNumber == true ? field : nil
    }

    private static func sectionHeading(_ line: String) -> String? {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.lowercased().hasPrefix("krankheit:") || s.lowercased().hasPrefix("disease:") {
            return s.split(separator: ":", maxSplits: 1).last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        }
        guard !s.isEmpty, s.count <= 80, s.first?.isLetter == true, !s.contains(":"),
              !s.contains("Impfpass"), !s.contains("PDF-Erstellung"), !s.hasPrefix("Seite "),
              !["Einträge", "Entries"].contains(s) else { return nil }
        return s
    }

    private static func isAdministrationField(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        return ["ch.-nr.", "charge", "batch", "pzn", "impfsetting", "impfprogramm", "impfdatum",
                "vaccination date", "eingetragen am", "recorded on", "dosis", "dose"]
            .contains(line[..<colon].trimmingCharacters(in: .whitespaces).lowercased())
    }

    private static func parseRow(_ lines: [String], disease: String?, document: SourceDocument, page: Int?,
                                 calendar: Calendar, now: Date) -> VaccinationCandidate? {
        var fields = [String: String]()
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard fields[key] == nil else { return nil } // ambiguous row
            fields[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let product = fields["impfstoff"] ?? fields["vaccine"], !product.isEmpty,
              let dateText = fields["impfdatum"] ?? fields["vaccination date"],
              let (date, timed, civilDay) = administrationDate(dateText, calendar: calendar),
              let dayOnPath = calendar.date(from: civilDay),
              dayOnPath <= calendar.startOfDay(for: now) else { return nil }
        let quote = lines.joined(separator: "\n")
        let batch = fields["ch.-nr."] ?? fields["charge"] ?? fields["batch"] ?? ""
        let id = LifePathSeed.stableID("vaccination-import|\(document.id)|\(disease ?? "")|\(quote)")
        let evidence = EvidenceReference(id: LifePathSeed.stableID("vaccine-proof-\(id)"),
            documentID: document.id, documentTitle: document.title, locator: dateText, quote: quote, pageNumber: page)
        let record = VaccinationRecord(disease: disease ?? "", hasDocumentedTime: timed, administrationText: dateText,
            product: product, batch: batch, productNumber: fields["pzn"] ?? "", doseLabel: fields["dosis"] ?? fields["dose"] ?? "",
            location: "", responsiblePerson: "", facility: "", setting: fields["impfsetting"], program: fields["impfprogramm"],
            recordedAtText: fields["eingetragen am"] ?? fields["recorded on"] ?? "", administrationDay: civilDay)
        return VaccinationCandidate(date: date, record: record, evidence: evidence)
    }

    private static func administrationDate(_ value: String, calendar: Calendar) -> (Date, Bool, DateComponents)? {
        let pattern = #"^(\d{1,2})\.?[. /-]+([\p{L}]{3,12}|\d{1,2})\.?[. /-]+(\d{4})(?:(?:\s+(?:um|at))?\s+(\d{1,2}):(\d{2})(?:\s*Uhr)?(?:\s*\(UTC([+-])(\d{1,2})(?::(\d{2}))?\))?)?$"#
        let ns = value as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func capture(_ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }
        guard let day = capture(1).flatMap(Int.init), let monthText = capture(2), let year = capture(3).flatMap(Int.init) else { return nil }
        let months = ["january": 1, "januar": 1, "jänner": 1, "jan": 1, "jän": 1, "february": 2, "februar": 2, "feb": 2,
            "march": 3, "märz": 3, "mär": 3, "mrz": 3, "mar": 3, "april": 4, "apr": 4, "may": 5, "mai": 5,
            "june": 6, "juni": 6, "jun": 6, "july": 7, "juli": 7, "jul": 7, "august": 8, "aug": 8,
            "september": 9, "sept": 9, "sep": 9, "october": 10, "oktober": 10, "oct": 10, "okt": 10,
            "november": 11, "nov": 11, "december": 12, "dezember": 12, "dec": 12, "dez": 12]
        guard let month = Int(monthText) ?? months[monthText.lowercased()] else { return nil }
        var cal = calendar
        if let sign = capture(6), let hours = capture(7).flatMap(Int.init) {
            let minutes = capture(8).flatMap(Int.init) ?? 0
            guard hours <= 14, minutes < 60,
                  let zone = TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)) else { return nil }
            cal.timeZone = zone
        }
        let components = DateComponents(year: year, month: month, day: day,
            hour: capture(4).flatMap(Int.init) ?? 0, minute: capture(5).flatMap(Int.init) ?? 0)
        guard components.isValidDate(in: cal), let date = cal.date(from: components) else { return nil }
        return (date, capture(4) != nil, DateComponents(year: year, month: month, day: day))
    }
}
