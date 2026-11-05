import PDFKit
import SwiftUI

struct VaccinationDetails: View {
    let record: VaccinationRecord

    var body: some View {
        SheetSection(title: "Impfung") {
            LabeledContent("Impfdatum", value: record.administrationText)
            LabeledContent("Impfstoff", value: record.product)
            LabeledContent("Dosis", value: record.doseLabel)
            LabeledContent("Charge", value: record.batch)
            LabeledContent("PZN", value: record.productNumber)
            LabeledContent("Ort", value: record.location)
            DisclosureGroup("Weitere Angaben") {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("Impfende Stelle", value: record.facility)
                    LabeledContent("Verantwortlich", value: record.responsiblePerson)
                    if let setting = record.setting { LabeledContent("Impfsetting", value: setting) }
                    if let program = record.program { LabeledContent("Impfprogramm", value: program) }
                    LabeledContent("Eingetragen am", value: record.recordedAtText)
                }
                .padding(.top, 8)
            }
        }
        .accessibilityIdentifier("vaccination.details")
    }
}

struct BundledPDFSheet: View {
    let name: String
    var pageNumber = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "Fixtures")
                    ?? Bundle.main.url(forResource: name, withExtension: "pdf") {
                    OriginalPDFView(url: url, pageNumber: pageNumber)
                        .accessibilityIdentifier("source.pdf")
                } else {
                    ContentUnavailableView("Original-PDF nicht verfügbar", systemImage: "doc")
                }
            }
            .navigationTitle("Original-PDF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

private struct OriginalPDFView: UIViewRepresentable {
    let url: URL
    let pageNumber: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .systemBackground
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.document = PDFDocument(url: url)
        if let document = view.document,
           let page = document.page(at: max(0, min(pageNumber - 1, document.pageCount - 1))) {
            view.go(to: page)
        }
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
