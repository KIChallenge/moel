import CryptoKit
import Foundation

struct LifeContextSource: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var text: String
    var urls: [String]
}

struct LifeScenario: Codable, Equatable, Sendable {
    var version: Int
    var birthDate: Date
    var snapshot: Date
    var timeZone: String
    var age: Int
    var sex: String
    var references: [LifeContextSource]
}

enum LifeRecordCategory: String, Codable, Sendable {
    case lifeEvent = "Lebensereignis", finding = "Befund", measurement = "Messung"
    case event = "Ereignis", administration = "Verwaltung", vaccination = "Impfung"
    case selfReport = "Eigenangabe", contact = "Kontakt", treatment = "Behandlung"
    case prescription = "Verordnung", form = "Formular", examination = "Untersuchung"
    case documentedDiagnosis = "Diagnose im Beleg", medicationEvidence = "Medikationsnachweis"
    case information = "Information", appointmentPlanning = "Terminplanung"
    case task = "Aufgabe", appointment = "Termin"

    var nodeKind: NodeKind {
        switch self {
        case .task: .task
        case .appointment: .appointment
        case .finding, .measurement, .form, .examination, .documentedDiagnosis, .information, .appointmentPlanning, .administration: .information
        default: .event
        }
    }
}

enum LifeDraftKind: String, Codable, Identifiable, Sendable {
    case questionnaire, medicationList
    var id: String { rawValue }
}

/// The source's historical assertion is kept apart from local task/read/attendance state.
struct LifeRecord: Codable, Equatable, Sendable {
    var dayID: String
    var dayTitle: String
    var entryNumber: Int
    var category: LifeRecordCategory
    var sourceStatus: String
    var origin: String
    var age: String
    var stage: String
    var episodeIDs: [String]
    var planned: Bool
    var linkedTaskID: UUID?
    var sessionNumber: Int?
    var draftKind: LifeDraftKind?
}

struct PathDayGroup: Identifiable, Equatable {
    var id: String
    var date: Date?
    var year: Int?
    var title: String
    var stage: String
    var entries: [PathNode]
    var isPlanned: Bool

    var entryCount: Int { entries.count }
    var haloSegmentCount: Int { entryCount > 1 ? entryCount : 0 }
    var displayNode: PathNode {
        var node = entries[0]
        node.title = title
        node.date = date
        if entries.count > 1 { node.kind = .event; node.informationRead = false }
        return node
    }
}

extension AppState {
    var pathCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: lifeScenario?.timeZone ?? fixtureTimeZoneIdentifier) ?? .current
        return calendar
    }

    var pathDays: [PathDayGroup] {
        let calendar = pathCalendar
        var groups: [String: [PathNode]] = [:]
        for node in nodes {
            let key: String
            if let date = node.date {
                let c = calendar.dateComponents([.year, .month, .day], from: date)
                key = String(format: "day-%04d-%02d-%02d", c.year!, c.month!, c.day!)
            } else { key = "entry-\(node.id.uuidString)" }
            groups[key, default: []].append(node)
        }
        return groups.map { key, records in
            let ordered = records.sorted {
                let lhs = $0.history?.entryNumber ?? Int.max
                let rhs = $1.history?.entryNumber ?? Int.max
                if lhs != rhs { return lhs < rhs }
                return $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
            }
            let first = ordered[0]
            let titles = Set(ordered.map { $0.history?.dayTitle ?? $0.title })
            let title = ordered.count > 1 && ordered.allSatisfy { $0.vaccination != nil }
                ? String(localized: "Impfungen") : titles.count == 1 ? titles.first! : String(localized: "Mein Tag")
            let date = first.date.map { calendar.startOfDay(for: $0) }
            let snapshot = lifeScenario?.snapshot
            return PathDayGroup(id: key, date: date, year: date.map { calendar.component(.year, from: $0) },
                                title: title, stage: first.history?.stage ?? String(localized: first.vaccination == nil ? "Eigene Schritte" : "Mein Leben heute"), entries: ordered,
                                isPlanned: date.map { d in snapshot.map { d > calendar.startOfDay(for: $0) } ?? false } ?? false)
        }.sorted {
            switch ($0.date, $1.date) {
            case let (a?, b?): a == b ? $0.id < $1.id : a < b
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0.entries[0].createdAt < $1.entries[0].createdAt
            }
        }
    }

    var uniqueOpenTasks: [PathNode] {
        nodes.filter { $0.kind == .task && $0.history?.linkedTaskID == nil && $0.taskStatus != .completed && $0.taskStatus != .cancelled }
    }

    var documentedTherapySessions: Int {
        let historical = nodes.filter { $0.history?.sessionNumber != nil && $0.history?.category == .treatment }.count
        let recorded = nodes.filter { node in
            guard node.history?.sessionNumber != nil, let id = node.appointmentID else { return false }
            return appointments.first { $0.id == id }?.attendance == .attended
        }.count
        return historical + recorded
    }

    var currentPathDayID: String? {
        guard let snapshot = lifeScenario?.snapshot else { return pathDays.last?.id }
        let calendar = pathCalendar
        guard nodes.contains(where: { $0.date.map { calendar.isDate($0, inSameDayAs: snapshot) } ?? false }) else { return nil }
        let c = calendar.dateComponents([.year, .month, .day], from: snapshot)
        return String(format: "day-%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

private struct LifePathFixture: Decodable {
    struct Entry: Decodable {
        var number: Int; var title: String; var category: LifeRecordCategory
        var status: String; var detail: String; var origin: String; var passage: String
    }
    struct Day: Decodable {
        var id: String; var date: String; var title: String; var year: Int
        var stage: String; var age: String; var episodeIDs: [String]
        var planned: Bool; var entries: [Entry]
    }
    var version: Int; var birthDate: String; var snapshot: String
    var timeZone: String; var age: Int; var sex: String
    var days: [Day]; var references: [LifeContextSource]
}

enum LifePathSeed {
    static func state(now: Date, calendar fixtureCalendar: Calendar, bundle: Bundle = .main, includingVaccinationPass: Bool = true) throws -> AppState {
        guard let dataURL = resource("life-path-33", extension: "json", bundle: bundle),
              let textURL = resource("life-path-33", extension: "txt", bundle: bundle) else {
            throw SoviError.invalidInput("Der synthetische 33-Jahre-Beispielpfad fehlt im App-Bundle.")
        }
        let fixture = try JSONDecoder().decode(LifePathFixture.self, from: Data(contentsOf: dataURL))
        guard fixture.version == 1, fixture.days.count == 222,
              fixture.days.reduce(0, { $0 + $1.entries.count }) == 328,
              let zone = TimeZone(identifier: fixture.timeZone),
              let snapshot = ISO8601DateFormatter().date(from: fixture.snapshot) else {
            throw SoviError.invalidInput("Der synthetische Beispielpfad ist nicht vollständig lesbar.")
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let formatter = DateFormatter(); formatter.calendar = calendar
        formatter.timeZone = zone; formatter.locale = Locale(identifier: "de_AT"); formatter.dateFormat = "dd.MM.yyyy"
        guard let birthDate = formatter.date(from: fixture.birthDate) else { throw SoviError.invalidAction }
        let text = try String(contentsOf: textURL, encoding: .utf8)
        let document = SourceDocument(id: stableID("life-path-33-source"),
                                      title: "33 Jahre · synthetische Textvorlage", text: text, importedAt: now,
                                      originalFingerprint: SHA256.hash(data: Data(text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines).utf8)).map { String(format: "%02x", $0) }.joined())
        var nodes: [PathNode] = []; var appointments: [AppointmentRecord] = []
        for day in fixture.days {
            guard let parsedDate = formatter.date(from: day.date) else { throw SoviError.invalidAction }
            for entry in day.entries {
                let identity = "\(day.id)-\(entry.number)"
                let id = stableID(identity)
                var date = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: parsedDate)!
                let chapter = day.year == 1993 ? 0 : day.year < 1999 ? 1 : day.year < 2011 ? 2 : day.year < 2023 ? 3 : 4
                let linkedTaskID: UUID? = identity == "P220-1" ? stableID("P217-3") : nil
                let draftKind: LifeDraftKind? = ["P217-3", "P220-1"].contains(identity) ? .questionnaire : identity == "P220-2" ? .medicationList : nil
                let session = sessionNumber(in: entry.detail)
                let record = LifeRecord(dayID: day.id, dayTitle: day.title, entryNumber: entry.number,
                                        category: entry.category, sourceStatus: entry.status, origin: entry.origin,
                                        age: day.age, stage: day.stage, episodeIDs: day.episodeIDs,
                                        planned: day.planned, linkedTaskID: linkedTaskID,
                                        sessionNumber: session, draftKind: draftKind)
                let evidence = EvidenceReference(id: stableID(identity + "-evidence"), documentID: document.id,
                                                 documentTitle: document.title, locator: "\(day.id) · Eintrag \(entry.number)", quote: entry.passage)
                var node = PathNode(id: id, kind: entry.category.nodeKind, title: entry.title, detail: entry.detail,
                                    chapter: chapter, taskStatus: entry.status == "Demo-erledigt" ? .completed : .open,
                                    evidence: [evidence], createdAt: now, date: date)
                node.history = record
                if entry.category == .appointment {
                    // Only the five explicit appointment entries create local appointments.
                    // The planning evidence and historical attendance remain separate records.
                    let times = ["P217-1": (16,0), "P218-1": (16,0), "P219-1": (9,0), "P221-1": (8,30), "P222-1": (9,30)]
                    guard let (hour, minute) = times[identity] else { throw SoviError.invalidAction }
                    date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: parsedDate)!
                    let appointment = AppointmentRecord(id: stableID(identity + "-appointment"),
                        title: day.title == "Mein Tag" ? entry.title : day.title, date: date,
                        location: "Fiktive Ordination/Praxis · genauer Ort nicht angegeben",
                        status: .confirmed, attendance: .unrecorded,
                        provenance: "Im synthetischen Beispieldatensatz als vereinbart beschrieben. Keine reale Buchung oder Anbieterbestätigung durch Sovi.",
                        preparation: entry.detail, createdAt: now, updatedAt: now)
                    node.appointmentID = appointment.id; node.date = date; appointments.append(appointment)
                }
                nodes.append(node)
            }
        }
        var state = AppState(seededAt: now, nodes: nodes, documents: [document], appointments: appointments,
                             fixtureEpoch: now, fixtureTimeZoneIdentifier: fixtureCalendar.timeZone.identifier)
        state.lifeScenario = LifeScenario(version: fixture.version, birthDate: birthDate, snapshot: snapshot,
                                          timeZone: fixture.timeZone, age: fixture.age, sex: fixture.sex, references: fixture.references)
        guard state.pathDays.count == 222, Set(nodes.map(\.id)).count == 328 else { throw SoviError.invalidAction }
        return includingVaccinationPass ? try VaccinationPassSeed.updatingDemo(state, now: now, bundle: bundle) : state
    }

    static func stableID(_ key: String) -> UUID {
        var b = Array(SHA256.hash(data: Data(("sovi-life-33-v1:" + key).utf8)).prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50; b[8] = (b[8] & 0x3F) | 0x80
        return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
    }
    private static func resource(_ name: String, extension ext: String, bundle: Bundle) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") ?? bundle.url(forResource: name, withExtension: ext)
    }
    private static func sessionNumber(in text: String) -> Int? {
        guard let range = text.range(of: #"Einheit [1-6] von 6"#, options: .regularExpression) else { return nil }
        return text[range].split(separator: " ").dropFirst().first.flatMap { Int($0) }
    }
}
