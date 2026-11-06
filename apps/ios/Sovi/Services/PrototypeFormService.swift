import Foundation
import PDFKit

struct PrototypeForm: Decodable, Identifiable {
    struct Field: Decodable, Identifiable {
        var id: String
        var page: Int
        var name: String
        var profileKey: String?
        var label: String
    }
    var id: String
    var title: String
    var pages: Int
    var note: String
    var fields: [Field]
    var url: URL? {
        Bundle.main.url(forResource: id, withExtension: "pdf", subdirectory: "Fixtures/Forms")
    }
    static func load() throws -> [PrototypeForm] {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json", subdirectory: "Fixtures/Forms") else { throw SoviError.missingRecord }
        return try JSONDecoder().decode([PrototypeForm].self, from: Data(contentsOf: url))
    }
    /// A specifically requested template can open directly. Generic care applications
    /// go through the guided case so the payer and responsible authority are checked.
    static func requestedID(in message: String) -> String? {
        let t = ChatLanguage.normalized(message)
        let named: [(String, [String])] = [
            ("reha-unfall", ["reha nach unfall", "rehabilitation nach unfall", "accident rehabilitation", "rehab after an accident", "kaza sonrasi rehabilitasyon", "تأهيل بعد حادث"]),
            ("einrichtungswunsch", ["einrichtungswunsch", "preferred facility", "facility preference", "kurum tercihi", "تفضيل المؤسسة"]),
            ("senioren-wg", ["seniorinnen-wohngemeinschaft", "senior:innen-wohngemeinschaft", "senioren-wg", "seniorenwohngemeinschaft", "senior shared housing", "shared senior housing", "yasli ortak konut", "سكن مشترك للمسنين"]),
            ("fahrtkosten", ["fahrtkosten", "travel cost", "transport cost", "ulasim masraf", "تكاليف النقل", "تكاليف السفر"]),
            ("kur-reha", ["reha-antrag", "rehaantrag", "rehabilitation application", "rehab form", "rehabilitasyon basvuru", "طلب اعاده التأهيل", "طلب إعادة التأهيل"]),
            ("fsw-foerderung", ["fsw-antrag", "fsw antrag", "fsw application", "fsw funding", "fsw basvuru", "طلب fsw"]),
            ("pflegegeld", ["pv-pflegegeldantrag", "pv care allowance form"])
        ]
        let matches = named.filter { $0.1.contains { phrase in t.contains(ChatLanguage.normalized(phrase)) } }
        guard matches.count == 1 else { return nil }
        return matches[0].0
    }

    func prefilledDraft(for person: FormPerson, caseProgress: DemoScenarioProgress? = nil) -> SavedFormDraft {
        let purpose = caseProgress?.preparation?.answers["purpose"]
        let selections: [String: String]? = id == "pflegegeld" && ["first", "increase"].contains(purpose ?? "")
            ? ["Antrag Pflg": purpose == "first" ? "01" : "02"] : nil
        return SavedFormDraft(formID: id, personID: person.id, values: prefill(person),
                              caseScenario: caseProgress?.scenario.rawValue, selections: selections)
    }

    func prefill(_ person: FormPerson) -> [String: String] {
        var values = person.values
        values["fullName"] = person.name
        values["address"] = person.address
        values["birthYear"] = person.values["birthDate"].flatMap { $0.split(separator: ".").last.map(String.init) }
        values["houseStairDoor"] = [person.values["house"], person.values["stair"], person.values["door"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
        values["lastNameTitle"] = [person.values["title"], person.values["lastName"]].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return Dictionary(uniqueKeysWithValues: fields.compactMap { field in
            guard let key = field.profileKey, let value = values[key], !value.isEmpty else { return nil }
            return (field.id, value)
        })
    }

    /// Reviewed text fields are written. Selection choices stay in the case for
    /// review; checkbox appearances are not rewritten by PDFKit. Originals stay intact.
    @MainActor func document(values: [String: String]) throws -> PDFDocument {
        guard let url, let pdf = PDFDocument(url: url) else { throw SoviError.missingRecord }
        for field in fields {
            guard let value = values[field.id], !value.isEmpty,
                  let page = pdf.page(at: field.page), let annotation = page.annotations.first(where: {
                      $0.widgetFieldType == .text && $0.fieldName == field.name
                  }) else { continue }
            annotation.widgetStringValue = value
        }
        return pdf
    }

    @MainActor func export(values: [String: String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SoviFormDrafts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.protectionKey: FileProtectionType.complete])
        let url = directory.appendingPathComponent(id + "-" + UUID().uuidString + "-Entwurf.pdf")
        guard try document(values: values).write(to: url) else { throw SoviError.invalidAction }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        return url
    }
    static func clearExports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SoviFormDrafts", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}
