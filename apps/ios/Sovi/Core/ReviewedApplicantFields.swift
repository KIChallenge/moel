import Foundation

/// Candidate fields from the patient header. Saving them always goes through the person editor.
struct ReviewedApplicantFields {
    let document: SourceDocument
    var values: [String: String] = [:]
    var name = ""
    var evidence: [String] = []

    init?(_ document: SourceDocument) {
        self.document = document
        let ns = document.text as NSString
        let header: String
        if let page = document.pageSpans?.first, page.utf16Start >= 0, page.utf16Length > 0,
           page.utf16Start <= ns.length - page.utf16Length {
            header = ns.substring(with: NSRange(location: page.utf16Start, length: page.utf16Length))
        } else { header = String(document.text.prefix(3000)) }
        let labels = [
            ("firstName", "Vorname|First name"), ("lastName", "Familienname|Nachname|Surname|Last name"),
            ("birthDate", "Geburtsdatum|Date of birth"), ("insuranceNumber", "SVNR|Sozialversicherungsnummer|SV-Nummer"),
            ("name", "Patient(?:in)?|Patientenname|Patient name|Name"), ("address", "Wohnadresse|Home address")
        ]
        for line in header.components(separatedBy: .newlines).prefix(32) {
            if line.range(of: #"^\s*(?:\d+[. ]+)?(?:Hauptdiagnose|Anamnese|Zuweiser|Behandelnde|Zuweisende|Empfänger|Referring physician|Angehörige|Kontaktperson)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { break }
            for (key, label) in labels {
                guard let match = Self.parts(line, "^\\s*(?:" + label + ")(?:\\s*[:\\t]\\s*| +)(.{1,180})\\s*$").first else { continue }
                let raw = match.trimmingCharacters(in: .whitespaces)
                if key == "name" {
                    guard name.isEmpty, raw.range(of: #"^[\p{L}][\p{L} ,.'’–-]{1,90}$"#, options: .regularExpression) != nil else { continue }
                    name = raw
                    // Keep the complete printed name alongside editable candidate fields.
                    let pair = raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    if pair.count == 2 && pair.allSatisfy({ !$0.isEmpty }) {
                        values["lastName"] = pair[0]
                        values["firstName"] = pair[1]
                    } else if pair.count == 1 {
                        let words = raw.split(separator: " ")
                        if words.count == 2 && words.allSatisfy({ $0.first?.isUppercase == true }) {
                            values["firstName"] = String(words[0])
                            values["lastName"] = String(words[1])
                        }
                    }
                } else if key == "address" {
                    let fields = Self.parts(raw, #"^(.+?)\s+(\d+[a-zA-Z]?)\s*,\s*(\d{4})\s+([\p{L} -]+)$"#)
                    guard fields.count == 4 else { continue }
                    for (field, value) in zip(["street","house","postcode","city"], fields) { values[field] = value }
                } else {
                    let value = key == "insuranceNumber" ? raw.replacingOccurrences(of: " ", with: "") : raw
                    guard values[key] == nil, let field = PersonField(rawValue: key), field.validate(value) == nil else { continue }
                    values[key] = value
                }
                evidence.append(line)
            }
        }
        guard !name.isEmpty || values["firstName"] != nil || values["lastName"] != nil else { return nil }
    }

    var person: FormPerson { FormPerson(label: name, values: values) }

    private static func parts(_ line: String, _ pattern: String) -> [String] {
        let text = line as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return [] }
        return (1..<match.numberOfRanges).map { text.substring(with: match.range(at: $0)) }
    }
}
