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
