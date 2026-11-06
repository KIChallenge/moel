import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct WelcomeECardScan: View {
    let eligibleFields: Set<PersonField>
    var existingValues: [String: String] = [:]
    let onConfirm: ([PersonField: String]) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var cameraDenied = false
    @State private var operation: Task<Void, Never>?
    @State private var error: String?
    @State private var scanned: [PersonField: String] = [:]
    @State private var fields: [PersonField: String] = [:]
    @State private var alternative: [PersonField: String]?
    @FocusState private var focusedField: PersonField?

    private var reviewFields: [PersonField] {
        [.firstName, .lastName, .birthDate, .insuranceNumber, .insurer].filter { fields[$0] != nil }
    }

    private var answers: [PersonField: String] {
        fields.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.value.isEmpty }
    }

    private var canConfirm: Bool {
        operation == nil && !answers.isEmpty && answers.allSatisfy { $0.key.validate($0.value) == nil }
    }

    var body: some View {
        SheetPage(title: "e-card einlesen", closeIdentifier: "welcome.ecard.close") {
            if reviewFields.isEmpty {
                Text("Fotografiere eine Seite deiner e-card. Du kannst auch ein Foto auswählen. Sovi liest es nur auf diesem Gerät.")
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Prüfe die Angaben. Du kannst sie ändern oder ein Feld leeren.")
                    ForEach(reviewFields) { field in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(field.title).font(.subheadline.weight(.semibold))
                            TextField(field.title, text: binding(for: field))
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(field == .firstName || field == .lastName ? .words : .never)
                                .autocorrectionDisabled()
                                .keyboardType(field == .insuranceNumber ? .numberPad : field == .birthDate ? .numbersAndPunctuation : .default)
                                .focused($focusedField, equals: field)
                                .accessibilityLabel(Text(field.title))
                                .accessibilityIdentifier("welcome.ecard.field." + field.rawValue)
                                .privacySensitive()
                            if let value = fields[field], let problem = field.validate(value) {
                                Text(problem).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    Button("Angaben übernehmen", action: confirm)
                        .buttonStyle(SheetPrimaryButtonStyle())
                        .disabled(!canConfirm)
                        .accessibilityIdentifier("welcome.ecard.confirm")
                }
                Text("Weitere Kartenseite einlesen").font(.headline).accessibilityAddTraits(.isHeader)
            }
            if operation != nil {
                ProgressView("Daten werden gelesen …")
                    .accessibilityIdentifier("welcome.ecard.progress")
            }
            VStack(spacing: 8) {
                Button(action: requestCamera) {
                    Label("Foto aufnehmen", systemImage: "camera.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("welcome.ecard.camera")
                PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                    Label("Foto auswählen", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("welcome.ecard.photo")
            }
            .disabled(operation != nil)
            if let error {
                Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("welcome.ecard.error")
            }
            if cameraDenied {
                Button("Einstellungen") {
                    if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
                }.frame(minHeight: 44)
            }
            Button("Manuell weiter") { operation?.cancel(); dismiss() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("welcome.ecard.manual")
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            read {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw SoviError.invalidInput(String(localized: "Keine lesbare Datei.")) }
                return data
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            ECardCamera { data in
                showsCamera = false
                if let data { read { data } }
            }.ignoresSafeArea()
        }
        .confirmationDialog("Diese Aufnahmen lassen sich nicht sicher derselben Karte zuordnen.",
                            isPresented: Binding(get: { alternative != nil }, set: { if !$0 { alternative = nil } }),
                            titleVisibility: .visible, presenting: alternative) { newScan in
            Button("Nur die neue Aufnahme verwenden", role: .destructive) { use(newScan, replacing: true) }
            Button("Bisherige Angaben behalten", role: .cancel) {}
        }
        .onDisappear { if !showsCamera { operation?.cancel() } }
    }

    private func binding(for field: PersonField) -> Binding<String> {
        Binding(get: { fields[field] ?? "" }, set: { value in
            fields[field] = field == .insuranceNumber ? String(value.filter { $0.isASCII && $0.isNumber }.prefix(10)) : value
        })
    }

    private func requestCamera() {
        guard operation == nil else { return }
        focusedField = nil
        error = nil
        cameraDenied = false
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            error = String(localized: "Die Kamera ist nicht verfügbar. Du kannst ein Foto auswählen.")
            return
        }
        operation = Task { @MainActor in
            defer { operation = nil }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            let allowed: Bool
            if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            else { allowed = status == .authorized }
            guard !Task.isCancelled else { return }
            if allowed { showsCamera = true }
            else {
                cameraDenied = status != .restricted
                error = String(localized: "Erlaube den Kamerazugriff in den Einstellungen oder wähle ein Foto aus.")
            }
        }
    }

    private func read(_ imageData: @escaping @MainActor () async throws -> Data) {
        guard operation == nil else { return }
        focusedField = nil
        error = nil
        cameraDenied = false
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let data = try await imageData()
                try Task.checkCancellation()
                let values = try await ECardReader.read(data)
                try Task.checkCancellation()
                acceptScan(values)
            } catch is CancellationError { return }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func acceptScan(_ values: [PersonField: String]) {
        guard values.contains(where: { eligibleFields.contains($0.key) && !$0.value.isEmpty }) else {
            error = String(localized: "Auf diesem Foto konnte ich keine neuen Angaben für die offenen Fragen lesen.")
            return
        }
        let identity: [PersonField] = [.firstName, .lastName, .birthDate, .insuranceNumber]
        if identity.contains(where: { field in mismatch(values[field], existingValues[field.rawValue]) }) {
            error = String(localized: "Die Angaben auf der Karte passen nicht zu deinen bisherigen Antworten.")
            return
        }
        if !scanned.isEmpty {
            let sameNumber = equal(values[.insuranceNumber], scanned[.insuranceNumber])
            let sameName = equal(values[.firstName], scanned[.firstName]) && equal(values[.lastName], scanned[.lastName])
            if (!sameNumber && !sameName) || identity.contains(where: { mismatch(values[$0], scanned[$0]) }) {
                alternative = values
                return
            }
        }
        use(values, replacing: false)
    }

    private func equal(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_AT")) == .orderedSame
    }

    private func mismatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        return !equal(lhs, rhs)
    }

    private func use(_ values: [PersonField: String], replacing: Bool) {
        if replacing { scanned = [:]; fields = [:] }
        scanned.merge(values) { first, _ in first }
        fields.merge(values.filter { eligibleFields.contains($0.key) }) { edited, _ in edited }
        alternative = nil
    }

    private func confirm() {
        guard canConfirm else { return }
        do {
            try onConfirm(answers)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct ECardCamera: UIViewControllerRepresentable {
    let finished: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier]
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let finished: (Data?) -> Void
        init(finished: @escaping (Data?) -> Void) { self.finished = finished }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage, image.size.width > 0, image.size.height > 0 else {
                finished(nil)
                return
            }
            // Draw the captured photo upright and pass only pixels to the local reader.
            let factor = min(1, 2400 / max(image.size.width, image.size.height))
            let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.94) { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            finished(data)
        }
    }
}
