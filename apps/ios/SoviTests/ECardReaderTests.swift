import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Sovi

final class ECardReaderTests: XCTestCase {
    func testRealOCRReadsBothSidesAndProducesMetadataFreeChatPhotos() async throws {
        let bundle = Bundle(for: Self.self)
        func input(_ name: String, override: String) throws -> Data {
            let path = ProcessInfo.processInfo.environment[override]
            let url = try XCTUnwrap(path.map(URL.init(fileURLWithPath:)) ?? bundle.url(forResource: name, withExtension: "png", subdirectory: "Fixtures"))
            return try Data(contentsOf: url)
        }
        let source = try XCTUnwrap(CGImageSourceCreateWithData(try input("synthetic-e-card-front", override: "SOVI_TEST_ECARD_FRONT") as CFData, nil))
        let tagged = NSMutableData()
        let output = try XCTUnwrap(CGImageDestinationCreateWithData(tagged, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 1, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 1, kCGImagePropertyGPSLongitudeRef: "E"]
        CGImageDestinationAddImageFromSource(output, source, 0, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(output))
        let frontData = tagged as Data
        let taggedSource = try XCTUnwrap(CGImageSourceCreateWithData(frontData as CFData, nil))
        let taggedProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(taggedSource, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(taggedProperties[kCGImagePropertyGPSDictionary])
        let front = try await ECardReader.read(frontData, expecting: .front)
        let back = try await ECardReader.read(try input("synthetic-e-card", override: "SOVI_TEST_ECARD_BACK"), expecting: .back)
        XCTAssertEqual([front.photo.side, back.photo.side], [.front, .back])
        XCTAssertTrue(front.fields[.insuranceNumber] != nil && front.fields[.insuranceNumber] == back.fields[.insuranceNumber])
        XCTAssertNotNil(back.fields[.birthDate])
        XCTAssertNotNil(back.fields[.insurer])
        var person = FormPerson(isSelf: true)
        var welcome = WelcomeProgress(personID: person.id)
        let now = Date()
        try welcome.recordAnswer(String(localized: "Hi"), person: &person, now: now)
        try welcome.recordAnswer(String(localized: "Akzeptieren"), person: &person, now: now)
        try welcome.handleECard(.start, person: &person, now: now)
        let id = try XCTUnwrap(welcome.eCardScan?.id)
        try welcome.handleECard(.post(id, front.photo, front.fields), person: &person, now: now)
        try welcome.handleECard(.post(id, back.photo, back.fields), person: &person, now: now)
        let recognized = try XCTUnwrap(welcome.eCardScan?.recognized)
        try welcome.handleECard(.confirm(id, recognized), person: &person, now: now)
        XCTAssertEqual(welcome.field, .street)
        XCTAssertTrue(WelcomeProgress.eCardFields.allSatisfy { person.values[$0.rawValue]?.isEmpty == false })
        for photo in [front.photo, back.photo] {
            XCTAssertLessThanOrEqual(photo.jpeg.count, WelcomeECardPhoto.maxBytes)
            let image = try XCTUnwrap(CGImageSourceCreateWithData(photo.jpeg as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(image) as String?, UTType.jpeg.identifier)
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
            XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        }
        do {
            _ = try await ECardReader.read(frontData, expecting: .back)
            XCTFail("A second front must not be posted as the reverse.")
        } catch { XCTAssertEqual(error.localizedDescription, String(localized: "Das ist die Vorderseite. Jetzt brauche ich die Rückseite.")) }
    }

    private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.18, height: CGFloat = 0.03) -> ECardReader.Line {
        .init(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    func testBackUsesNumberedFieldsAndKeepsSequenceExpiryAndCardIDOut() {
        let rows = [
            line("Europäische Krankenversicherungskarte", x: 0.22, y: 0.04),
            line("AT", x: 0.84, y: 0.11),
            line("3 Name", x: 0.07, y: 0.50), line("MAG. BEISPIEL-TEST", x: 0.08, y: 0.55),
            line("4 Vorname", x: 0.07, y: 0.61), line("TESTA", x: 0.08, y: 0.66),
            line("5 Geburtsdatum", x: 0.78, y: 0.61), line("02/03/1984", x: 0.76, y: 0.66),
            line("6 Persönliche Kennnummer", x: 0.07, y: 0.71), line("9000 000000", x: 0.08, y: 0.76),
            line("Kennnummer des Trägers", x: 0.70, y: 0.71), line("1100 - OEGK", x: 0.76, y: 0.76),
            line("8 Kennnummer der Karte", x: 0.07, y: 0.81), line("80000000000000000000", x: 0.08, y: 0.86),
            line("9 Ablaufdatum", x: 0.78, y: 0.81), line("31/12/2020", x: 0.76, y: 0.86)
        ]
        XCTAssertEqual(ECardReader.fields(in: rows), [.lastName: "BEISPIEL-TEST", .firstName: "TESTA", .birthDate: "02.03.1984",
                                                      .insuranceNumber: "9000000000", .insurer: "ÖGK"])
        let unreadable = rows.filter { !["02/03/1984", "9000 000000"].contains($0.text) }
        XCTAssertNil(ECardReader.fields(in: unreadable)[.insuranceNumber])
        XCTAssertNil(ECardReader.fields(in: unreadable)[.birthDate])
    }

    func testFrontOnlyReturnsNamesAndTenDigitNumberFromPrintedArea() {
        let rows = [
            line("e-card", x: 0.32, y: 0.25, width: 0.21, height: 0.10),
            line("Mag.", x: 0.30, y: 0.62), line("Testa", x: 0.30, y: 0.66),
            line("Beispiel", x: 0.30, y: 0.71), line("004", x: 0.30, y: 0.56), line("9000 000000", x: 0.46, y: 0.56),
            line("telephone number", x: 0.07, y: 0.79), line("0501243311", x: 0.07, y: 0.85),
            line("1450", x: 0.62, y: 0.76)
        ]
        XCTAssertEqual(ECardReader.fields(in: rows), [.firstName: "Testa", .lastName: "Beispiel", .insuranceNumber: "9000000000"])
        let unclearName = rows.filter { $0.text != "Beispiel" }
        XCTAssertEqual(ECardReader.fields(in: unclearName), [.insuranceNumber: "9000000000"])
        XCTAssertTrue(ECardReader.fields(in: rows.filter { $0.text != "e-card" }).isEmpty)
    }

    func testUnrecognizedPhotoAndConflictingValuesStayEmpty() {
        XCTAssertTrue(ECardReader.fields(in: [line("9000 000000", x: 0.46, y: 0.56)]).isEmpty)
        let rows = [
            line("e-card", x: 0.32, y: 0.25, width: 0.21, height: 0.10),
            line("004", x: 0.30, y: 0.56), line("9000 000000", x: 0.46, y: 0.56),
            line("9000 000001", x: 0.48, y: 0.565)
        ]
        XCTAssertTrue(ECardReader.fields(in: rows).isEmpty)
        XCTAssertTrue(ECardReader.fields(in: [rows[0], line("0501243311", x: 0.46, y: 0.56)]).isEmpty)
    }
}
