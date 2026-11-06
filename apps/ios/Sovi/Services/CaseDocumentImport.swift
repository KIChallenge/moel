import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import Vision

enum CaseDocumentImport {
    typealias Contents = (text: String, pdf: Data?, pageSpans: [DocumentPageSpan]?)
    private static let maxFileBytes = 5 * 1024 * 1024

    static func read(_ url: URL) throws -> Contents {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...maxFileBytes).contains(size) else { throw sizeError }
        let data = try Data(contentsOf: url)
        guard data.count <= maxFileBytes else { throw sizeError }
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        if url.pathExtension.lowercased() == "pdf" || type?.conforms(to: .pdf) == true { return try readPDF(data) }
        if type?.conforms(to: .image) == true || ["jpg", "jpeg", "png", "heic", "tiff"].contains(url.pathExtension.lowercased()) {
            return try readPDF(imagePDF(data))
        }
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SoviError.invalidInput(String(localized: "Keine lesbare Datei."))
        }
        return (text, nil, nil)
    }

    private static var sizeError: SoviError {
        .invalidInput(String(localized: "Leere Datei oder größer als 5 MB."))
    }

    private static func readPDF(_ data: Data) throws -> Contents {
        guard let pdf = PDFDocument(data: data), !pdf.isLocked, (1...100).contains(pdf.pageCount) else {
            throw SoviError.invalidInput(String(localized: "PDF gesperrt, unlesbar oder über 100 Seiten."))
        }
        var text = ""
        var byteCount = 0
        var spans: [DocumentPageSpan] = []
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index) else { throw SoviError.invalidAction }
            let native = DemoPlanExtractor.normalized(page.string ?? "")
            let scanned = native.isEmpty
            let pageText = try scanned ? recognize(page) : native
            guard !pageText.isEmpty else { continue }
            let heading = (text.isEmpty ? "" : "\n\n") + "Seite \(index + 1)\n"
            byteCount += heading.utf8.count + pageText.utf8.count
            guard byteCount <= 2_000_000 else {
                throw SoviError.invalidInput(String(localized: "Textdatei zu groß. Maximal 2 MB."))
            }
            text += heading
            spans.append(DocumentPageSpan(pageNumber: index + 1, utf16Start: text.utf16.count,
                                          utf16Length: pageText.utf16.count, usedTextRecognition: scanned))
            text += pageText
        }
        guard !text.isEmpty else { throw SoviError.invalidInput(String(localized: "Kein lesbarer Text gefunden.")) }
        return (text, data, spans)
    }

    private static func recognize(_ page: PDFPage) throws -> String {
        guard let ref = page.pageRef else { throw SoviError.invalidAction }
        let bounds = page.bounds(for: .cropBox)
        guard bounds.width.isFinite, bounds.height.isFinite, min(bounds.width, bounds.height) > 0 else {
            throw SoviError.invalidAction
        }
        let rotated = abs(ref.rotationAngle) % 180 == 90
        let scale = min(3, 2400 / max(bounds.width, bounds.height))
        let width = max(1, Int((rotated ? bounds.height : bounds.width) * scale))
        let height = max(1, Int((rotated ? bounds.width : bounds.height) * scale))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                 bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw SoviError.invalidAction }
        cg.setFillColor(gray: 1, alpha: 1)
        cg.fill(rect)
        cg.concatenate(ref.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        cg.drawPDFPage(ref)
        guard let image = cg.makeImage() else { throw SoviError.invalidAction }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE", "en-US"]
        // Correction of product names or batch numbers can change the evidence.
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        return DemoPlanExtractor.normalized((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
    }

    /// Save the selected image as a single-page PDF so the same page viewer can show the original pixels.
    private static func imagePDF(_ data: Data) throws -> Data {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(src) == 1 else {
            throw SoviError.invalidInput(String(localized: "Bitte ein einzelnes Bild oder ein PDF auswählen."))
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 2400]
        guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            throw SoviError.invalidInput(String(localized: "Keine lesbare Datei."))
        }
        let bytes = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let consumer = CGDataConsumer(data: bytes), let cg = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw SoviError.invalidAction
        }
        cg.beginPDFPage(nil)
        cg.draw(image, in: box)
        cg.endPDFPage()
        cg.closePDF()
        guard bytes.length <= maxFileBytes else { throw sizeError }
        return bytes as Data
    }

    static func sampleURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "demo-discharge-navigation", withExtension: "pdf", subdirectory: "Fixtures") else {
            throw SoviError.missingRecord
        }
        return url
    }
}
