import XCTest
@testable import Sovi

final class ECardReaderTests: XCTestCase {
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
