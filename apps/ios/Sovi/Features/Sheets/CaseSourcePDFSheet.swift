import SwiftUI
import PDFKit

struct CaseSourcePDFSheet: View {
    let document: SourceDocument
    var pageNumber = 1
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let data = document.importedPDFData { CaseOriginalPDF(data: data, pageNumber: pageNumber) }
                else if let name = document.bundledPDFName { BundledPDFSheet(name: name, pageNumber: pageNumber) }
                else { ScrollView { Text(document.text).textSelection(.enabled).padding(24) } }
            }.navigationTitle("Original-PDF").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

private struct CaseOriginalPDF: UIViewRepresentable {
    let data: Data
    let pageNumber: Int
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous
        view.document = PDFDocument(data: data)
        if let doc = view.document, let page = doc.page(at: max(0, min(pageNumber - 1, doc.pageCount - 1))) { view.go(to: page) }
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {}
}
