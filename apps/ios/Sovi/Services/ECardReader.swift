import Foundation
import ImageIO
import Vision

/// Only returns reviewable onboarding fields; the image and OCR observations live for this call.
enum ECardReader {
    struct Line {
        let text: String
        /// Normalized image coordinates, measured from the top left.
        let box: CGRect

        var key: String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT"))
                .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func read(_ imageData: Data) async throws -> [PersonField: String] {
        let task = Task.detached(priority: .userInitiated) { try recognize(imageData) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private static func recognize(_ data: Data) throws -> [PersonField: String] {
        try Task.checkCancellation()
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 2600]
        guard data.count <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SoviError.invalidInput(String(localized: "Keine lesbare Datei."))
        }
        // ImageIO applies EXIF orientation. A physical card can also be held sideways/upside down.
        for orientation in [CGImagePropertyOrientation.up, .right, .left, .down] {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: image, orientation: orientation).perform([request])
            let lines = (request.results ?? []).compactMap { item -> Line? in
                guard let candidate = item.topCandidates(1).first, candidate.confidence >= 0.45 else { return nil }
                let r = item.boundingBox
                return Line(text: candidate.string, box: CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height))
            }
            let values = fields(in: lines)
            try Task.checkCancellation()
            if !values.isEmpty { return values }
        }
        return [:]
    }

    static func fields(in lines: [Line]) -> [PersonField: String] {
        let backLabels = Set(lines.compactMap { Cell(label: $0.key) })
        if lines.contains(where: { $0.key.contains("europaische krankenversicherungskarte") })
            || (backLabels.contains(.personalNumber) && backLabels.contains(.cardNumber) && backLabels.contains(.institution)) {
            return backFields(lines)
        }
        return frontFields(lines)
    }

    // The EKVK labels 3–9 delimit their respective cells. Labels 8 and 9 only
    // establish row boundaries: their card identifier and expiry are never imported.
    private enum Cell: CaseIterable, Hashable {
        case surname, givenName, birth, personalNumber, institution, cardNumber, expiry

        init?(label: String) {
            let key = label.replacingOccurrences(of: #"^[3-9][.)]?\s*"#, with: "", options: .regularExpression)
            switch key {
            case "name": self = .surname
            case "vorname", "vornamen": self = .givenName
            case "geburtsdatum": self = .birth
            case "personliche kennnummer": self = .personalNumber
            case "kennnummer des tragers": self = .institution
            case "kennnummer der karte": self = .cardNumber
            case "ablaufdatum": self = .expiry
            default: return nil
            }
        }

        var onRight: Bool { self == .birth || self == .institution || self == .expiry }
    }

    private static func backFields(_ lines: [Line]) -> [PersonField: String] {
        let labels = Dictionary(grouping: lines.compactMap { line in Cell(label: line.key).map { ($0, line) } }, by: \.0)
            .compactMapValues { matches in matches.count == 1 ? matches[0].1 : nil }
        guard labels.count >= 3,
              let leftX = labels.filter({ !$0.key.onRight }).map(\.value.box.minX).min(),
              let rightX = labels.filter({ $0.key.onRight }).map(\.value.box.midX).min(),
              leftX < rightX else { return [:] }
        let divider = (leftX + rightX) / 2
        func value(_ cell: Cell, read: (String) -> String?) -> String? {
            guard let label = labels[cell] else { return nil }
            let next = labels.filter { $0.key.onRight == cell.onRight && $0.value.box.midY > label.box.midY }
                .map(\.value.box.minY).min()
            let bottom = min(next ?? 1, label.box.midY + label.box.height * 4)
            let candidates = lines.filter {
                Cell(label: $0.key) == nil && $0.box.midY > label.box.maxY && $0.box.midY < bottom &&
                    (($0.box.minX > divider) == cell.onRight)
            }.compactMap { read($0.text) }
            return candidates.count == 1 ? candidates[0] : nil
        }
        let institution = value(.institution, read: insurer)
        let isAustrian = lines.contains { $0.key == "at" }
            || ["ÖGK", "ÖSTERREICHISCHE GESUNDHEITSKASSE", "BVAEB", "SVS", "KFA"].contains(institution?.uppercased() ?? "")
        guard isAustrian else { return [:] }
        var fields: [PersonField: String] = [:]
        fields[.lastName] = value(.surname, read: name)
        fields[.firstName] = value(.givenName, read: name)
        fields[.birthDate] = value(.birth, read: birthDate)
        fields[.insuranceNumber] = value(.personalNumber, read: insuranceNumber)
        fields[.insurer] = institution
        return fields
    }

    private static func frontFields(_ lines: [Line]) -> [PersonField: String] {
        guard let logo = lines.first(where: { ["ecard", "e-card", "e card"].contains($0.key) })?.box,
              logo.width > 0 && logo.height > 0 else { return [:] }
        // The number is to the right of the printed sequence; names sit below
        // the sequence at the left. Keep illustration annotations and the service footer out.
        let numbers = lines.filter { line in
            line.box.minX >= logo.midX && line.box.minX < logo.maxX + logo.width &&
            line.box.midY > logo.maxY && line.box.midY < logo.maxY + 5 * logo.height &&
            insuranceNumber(line.text) != nil
        }
        let sequences = lines.filter {
            abs($0.box.minX - logo.minX) < logo.width * 0.40 &&
            $0.box.midY > logo.maxY && $0.box.midY < logo.maxY + 5 * logo.height &&
            $0.text.range(of: #"^[0-9]{1,4}$"#, options: .regularExpression) != nil
        }
        guard sequences.count <= 1 else { return [:] }
        let sequence = sequences.first
        let inNumberRow = numbers.filter { number in
            if let sequence {
                return abs(number.box.midY - sequence.box.midY) < max(sequence.box.height, number.box.height) * 1.5
            }
            // Without a sequence anchor, require the characteristic printed 4+6 grouping.
            return number.text.range(of: #"^[0-9]{4}\s[0-9]{6}$"#, options: .regularExpression) != nil
        }
        let number = inNumberRow.count == 1 ? inNumberRow[0] : nil
        guard let anchor = sequence ?? number else { return [:] }
        guard sequence != nil && number != nil || lines.contains(where: {
            $0.key == "sv" || $0.key.contains("kartenfolgenummer") || $0.key.contains("e-card serviceline")
        }) else { return [:] }
        var fields: [PersonField: String] = [:]
        if let number { fields[.insuranceNumber] = insuranceNumber(number.text) }
        let nameX = sequence?.box.minX ?? logo.minX
        let nameLines = lines.filter {
            abs($0.box.minX - nameX) < logo.width * 0.38 && $0.box.midY > anchor.box.maxY &&
            $0.box.midY < anchor.box.midY + logo.height * 2
        }.sorted { $0.box.midY < $1.box.midY }.compactMap { name($0.text) }
        if nameLines.count == 2 {
            fields[.firstName] = nameLines[0]
            fields[.lastName] = nameLines[1]
        }
        return fields
    }

    private static func insuranceNumber(_ text: String) -> String? {
        guard text.range(of: #"^[0-9]{4}[\s]?[0-9]{6}$"#, options: .regularExpression) != nil else { return nil }
        return text.filter { $0.isASCII && $0.isNumber }
    }

    private static func name(_ text: String) -> String? {
        let clean = text.replacingOccurrences(of: #"^(?:(?:mag|dr|prof|univ[.-]prof|dipl[.-]ing|ing)\.(?:\s+|$))+"#,
                                               with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
        guard clean.count <= 100, clean.range(of: #"^[\p{L}\p{M}]+(?:[ ’'\-][\p{L}\p{M}]+)*$"#, options: .regularExpression) != nil else { return nil }
        return clean
    }

    private static func birthDate(_ text: String) -> String? {
        guard text.range(of: #"^[0-9]{2}[/.\-][0-9]{2}[/.\-][0-9]{4}$"#, options: .regularExpression) != nil else { return nil }
        let date = text.replacingOccurrences(of: "/", with: ".").replacingOccurrences(of: "-", with: ".")
        return PersonField.birthDate.validate(date) == nil ? date : nil
    }

    private static func insurer(_ text: String) -> String? {
        let name = text.replacingOccurrences(of: #"^[0-9]{3,6}\s*[-–—]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard name.count >= 2, name.count <= 100, name.range(of: #"^[\p{L}][\p{L} .'’\-]*$"#, options: .regularExpression) != nil else { return nil }
        return ["OEGK", "ÖGK"].contains(name.uppercased()) ? "ÖGK" : name
    }
}
