import CryptoKit
import Foundation

/// Fields transcribed from a provided test document, never a derived vaccine schedule.
struct VaccinationRecord: Codable, Equatable, Sendable {
    var disease: String
    var hasDocumentedTime: Bool
    var administrationText: String
    var product: String
    var batch: String
    var productNumber: String
    var doseLabel: String
    var location: String
    var responsiblePerson: String
    var facility: String
    var setting: String?
    var program: String?
    var recordedAtText: String
}

private struct VaccinationPassFixture: Decodable {
    struct Entry: Decodable {
        var id: String
        var date: String
        var record: VaccinationRecord
        var page: Int
        var quote: String
    }
    var version: Int
    var documentDate: String
    var documentVersion: String
    var timeZone: String
    var entries: [Entry]
}

enum VaccinationPassSeed {
    static let resourceName = "vaccination-pass-2026"

    /// One explicit demo update. Existing tasks, drafts and user-added entries
    /// survive; empty/deleted stores and other profiles are never reseeded.
    static func updatingDemo(_ state: AppState, now: Date, bundle: Bundle = .main) throws -> AppState {
        let originalSourceID = LifePathSeed.stableID("life-path-33-source")
        guard state.lifeScenario != nil, (state.vaccinationPassVersion ?? 0) < 1,
              state.documents.contains(where: { $0.id == originalSourceID }) else { return state }
        guard let json = resourceURL(extension: "json", bundle: bundle),
              let textURL = resourceURL(extension: "txt", bundle: bundle),
              resourceURL(extension: "pdf", bundle: bundle) != nil else {
            throw SoviError.invalidInput(String(localized: "Impfpass nicht verfügbar."))
        }
        let fixture = try JSONDecoder().decode(VaccinationPassFixture.self, from: Data(contentsOf: json))
        guard fixture.version == 1, fixture.entries.count == 9,
              Set(fixture.entries.map(\.id)).count == 9,
              let zone = TimeZone(identifier: fixture.timeZone) else { throw SoviError.invalidAction }
        let text = try String(contentsOf: textURL, encoding: .utf8)
        var updated = state
        let fingerprint = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        var source = updated.documents.first { $0.originalFingerprint == fingerprint }
            ?? SourceDocument(id: LifePathSeed.stableID("vaccination-pass-source"),
                              title: "Impfpass.pdf", text: text,
                              importedAt: now, originalFingerprint: fingerprint, fixtureID: resourceName)
        source.bundledPDFName = resourceName

        let removed = Set(updated.nodes.filter { node in
            guard let history = node.history, history.category == .vaccination else { return false }
            return node.id == LifePathSeed.stableID("\(history.dayID)-\(history.entryNumber)")
                && node.evidence.contains { $0.documentID == originalSourceID }
        }.map(\.id))
        updated.nodes.removeAll { removed.contains($0.id) }
        if let context = updated.focusContextID, removed.contains(context) { updated.focusContextID = nil }

        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let dayFormatter = DateFormatter(); dayFormatter.calendar = calendar
        dayFormatter.timeZone = zone; dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"; dayFormatter.isLenient = false
        for entry in fixture.entries {
            let record = entry.record
            let date = record.hasDocumentedTime ? ISO8601DateFormatter().date(from: entry.date) : dayFormatter.date(from: entry.date)
            guard let date, (1...2).contains(entry.page), text.contains(entry.quote),
                  entry.quote.contains(record.product), entry.quote.contains(record.batch),
                  entry.quote.contains(record.administrationText) else { throw SoviError.invalidAction }
            let id = LifePathSeed.stableID("vaccination-pass-" + entry.id)
            guard !updated.nodes.contains(where: { $0.id == id }) else { continue }
            let evidence = EvidenceReference(id: LifePathSeed.stableID(entry.id + "-vaccination-evidence"),
                documentID: source.id, documentTitle: source.title,
                locator: "Seite \(entry.page) · \(record.disease) · Charge \(record.batch)",
                quote: entry.quote, pageNumber: entry.page)
            updated.nodes.append(PathNode(id: id, kind: .event, title: record.disease,
                detail: "\(record.product) · \(record.doseLabel)", chapter: 4,
                evidence: [evidence], createdAt: now, date: date, vaccination: record))
        }
        if let index = updated.documents.firstIndex(where: { $0.id == source.id }) { updated.documents[index] = source }
        else { updated.documents.append(source) }
        updated.vaccinationPassVersion = 1
        return updated
    }

    static func resourceURL(extension ext: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: resourceName, withExtension: ext, subdirectory: "Fixtures")
            ?? bundle.url(forResource: resourceName, withExtension: ext)
    }
}
