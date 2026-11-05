import Foundation
import PDFKit

enum CaseDocumentImport {
    static func read(_ url: URL) throws -> (text: String, pdf: Data?, pageSpans: [DocumentPageSpan]?) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 5 * 1024 * 1024 else { throw SoviError.invalidInput(String(localized: "Leere Datei oder größer als 5 MB.")) }
        let data = try Data(contentsOf: url)
        guard data.count <= 5 * 1024 * 1024 else { throw SoviError.invalidInput(String(localized: "Leere Datei oder größer als 5 MB.")) }
        if url.pathExtension.lowercased() == "pdf" {
            guard let pdf = PDFDocument(data: data), !pdf.isLocked, pdf.pageCount <= 100 else { throw SoviError.invalidInput(String(localized: "PDF gesperrt, unlesbar oder über 100 Seiten.")) }
            var text = ""
            var spans: [DocumentPageSpan] = []
            for index in 0..<pdf.pageCount {
                let pageText = DemoPlanExtractor.normalized(pdf.page(at: index)?.string ?? "")
                guard !pageText.isEmpty else { continue }
                if !text.isEmpty { text += "\n\n" }
                text += "Seite \(index + 1)\n"
                spans.append(DocumentPageSpan(pageNumber: index + 1, utf16Start: (text as NSString).length, utf16Length: (pageText as NSString).length))
                text += pageText
            }
            guard !text.isEmpty else { throw SoviError.invalidInput(String(localized: "Kein lesbarer Text. Bitte eine Datei mit Text verwenden.")) }
            return (text, data, spans)
        }
        guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SoviError.invalidInput(String(localized: "Bitte eine UTF-8-Textdatei oder ein PDF auswählen.")) }
        return (text, nil, nil)
    }
    static func sampleURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "demo-discharge-navigation", withExtension: "pdf", subdirectory: "Fixtures") else { throw SoviError.missingRecord }
        return url
    }
}
