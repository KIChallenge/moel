import SwiftUI
import UIKit

struct SheetPage<Content: View>: View {
    let title: String
    var closeIdentifier = "sheet.close"
    var startsCompact = false
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) { content }
                    .padding(24)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("sheet.content")
            .background(reduceTransparency ? SoviTheme.background : .clear)
            .foregroundStyle(SoviTheme.ink)
            .navigationTitle(Text(LocalizedStringKey(title)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier(closeIdentifier)
                }
            }
        }
        .tint(SoviTheme.accent)
        .presentationDetents(startsCompact && !textSize.isAccessibilitySize ? [.medium, .large] : [.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .presentationContentInteraction(.resizes)
        .presentationBackground {
            if reduceTransparency { SoviTheme.background }
            else { Rectangle().fill(.regularMaterial) }
        }
    }
}

struct SheetSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LocalizedStringKey(title)).font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SoviTheme.softGreen.opacity(0.55), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct SheetPrimaryButtonStyle: ButtonStyle {
    var tone: SoviButtonTone = .green
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(enabled ? SoviTheme.ink : SoviTheme.secondary)
            .background(enabled ? tone.surface : SoviTheme.bubble, in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(SoviTheme.ink.opacity(0.15)).allowsHitTesting(false) }
            .shadow(color: SoviTheme.ink.opacity(enabled ? 0.26 : 0.1), radius: 0, y: configuration.isPressed ? 0 : 3)
            .offset(y: configuration.isPressed ? 2 : 0)
            .contentShape(Rectangle())
    }
}

struct EvidenceSheet: View {
    let evidence: EvidenceReference
    @Environment(SoviStore.self) private var store
    @State private var showsPDF = false

    var body: some View {
        SheetPage(title: "Quelle", startsCompact: true) {
            Label(evidence.displayDocumentTitle, systemImage: "doc.text")
                .font(.headline)
            Text(evidence.locator).font(.subheadline).foregroundStyle(SoviTheme.secondary)
            SheetSection(title: "Auszug") {
                Text(evidence.quote).textSelection(.enabled)
            }
            if let document = store.document(id: evidence.documentID) {
                if document.bundledPDFName != nil || document.importedPDFData != nil {
                    Button("PDF öffnen") { showsPDF = true }
                        .buttonStyle(SheetPrimaryButtonStyle())
                        .accessibilityIdentifier("source.openPDF")
                }
                DisclosureGroup("Dokument") {
                    Text(document.text)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(.top, 12)
                }
            }
        }
        .sheet(isPresented: $showsPDF) {
            if let document = store.document(id: evidence.documentID) {
                CaseSourcePDFSheet(document: document, pageNumber: evidence.pageNumber ?? 1)
            }
        }
    }
}

struct SheetErrorModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert("Fehler", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func sheetError(_ message: Binding<String?>) -> some View {
        modifier(SheetErrorModifier(message: message))
    }
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let file: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [file], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum DraftExportFiles {
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("SoviExports", isDirectory: true) }

    static func write(_ text: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let url = directory.appendingPathComponent("Sovi-Entwurf-\(UUID().uuidString).txt")
        try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    static func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
