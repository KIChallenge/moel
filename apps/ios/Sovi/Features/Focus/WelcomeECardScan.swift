import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The welcome conversation owns the scan. Picking or taking a photo returns to the same chat.
struct WelcomeECardScan: View {
    let draft: WelcomeECardScanDraft
    @Binding var reviewFields: [PersonField: String]
    let perform: (WelcomeECardAction) throws -> Void

    @Environment(\.openURL) private var openURL
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var cameraDenied = false
    @State private var operation: Task<Void, Never>?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if draft.nextSide != nil {
                if operation != nil {
                    ProgressView("Daten werden gelesen …").accessibilityIdentifier("welcome.ecard.progress")
                } else {
                    Button(action: requestCamera) {
                        Label("Foto aufnehmen", systemImage: "camera.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(SheetPrimaryButtonStyle())
                    .accessibilityIdentifier("welcome.ecard.camera")
                    PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                        Label("Foto auswählen", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("welcome.ecard.photo")
                }
            } else {
                WelcomeECardReview(fields: $reviewFields)
            }
            if let error {
                Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("welcome.ecard.error")
            }
            if cameraDenied {
                Button("Einstellungen") {
                    if let settings = URL(string: UIApplication.openSettingsURLString) { openURL(settings) }
                }.frame(minHeight: 44)
            }
            Button {
                operation?.cancel()
                apply(.cancel(draft.id))
            } label: {
                Text(draft.front == nil ? "Manuell weiter" : "Scan verwerfen").frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityIdentifier("welcome.ecard.manual")
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            read {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw SoviError.invalidInput(String(localized: "Keine lesbare Datei."))
                }
                return data
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            ECardCamera { data in
                showsCamera = false
                if let data { read { data } }
            }.ignoresSafeArea()
        }
        .onDisappear { if !showsCamera { operation?.cancel() } }
    }

    private func apply(_ action: WelcomeECardAction) {
        do { try perform(action); error = nil }
        catch { self.error = error.localizedDescription }
    }

    private func requestCamera() {
        guard operation == nil, draft.nextSide != nil else { return }
        error = nil; cameraDenied = false
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
        guard operation == nil, let side = draft.nextSide else { return }
        error = nil; cameraDenied = false
        operation = Task { @MainActor in
            defer { operation = nil }
            do {
                let data = try await imageData()
                try Task.checkCancellation()
                let capture = try await ECardReader.read(data, expecting: side)
                try Task.checkCancellation()
                try perform(.post(draft.id, capture.photo, capture.fields))
            } catch is CancellationError { return }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

private struct WelcomeECardReview: View {
    @Binding var fields: [PersonField: String]
    @FocusState private var focused: PersonField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(WelcomeProgress.eCardFields.filter { fields[$0] != nil }) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.title).font(.subheadline.weight(.semibold))
                    TextField(field.title, text: Binding(get: { fields[field] ?? "" }, set: { value in
                        fields[field] = field == .insuranceNumber ? String(value.filter { $0.isASCII && $0.isNumber }.prefix(10)) : value
                    }))
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(field == .firstName || field == .lastName ? .words : .never)
                    .autocorrectionDisabled()
                    .keyboardType(field == .insuranceNumber ? .numberPad : field == .birthDate ? .numbersAndPunctuation : .default)
                    .focused($focused, equals: field)
                    .accessibilityLabel(Text(field.title))
                    .accessibilityIdentifier("welcome.ecard.field." + field.rawValue)
                    .privacySensitive()
                    if let value = fields[field], let problem = field.validate(value) {
                        Text(problem).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
    }
}

struct WelcomeCardPhotoSheet: View {
    let photo: WelcomeECardPhoto
    var body: some View {
        SheetPage(title: photo.side.caption, closeIdentifier: "welcome.ecard.preview.close", startsCompact: true) {
            if let image = UIImage(data: photo.jpeg) {
                Image(uiImage: image).resizable().scaledToFit().privacySensitive().accessibilityLabel(Text(photo.side.caption))
            }
        }
    }
}

struct WelcomeECardPhotoBubble: View {
    let photo: WelcomeECardPhoto
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 6) {
                if let image = UIImage(data: photo.jpeg) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: 260, maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(photo.side.caption).font(.caption.weight(.medium))
            }
            .padding(10)
            .background(SoviTheme.bubble, in: RoundedRectangle(cornerRadius: 18))
            .privacySensitive()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel(Text(photo.side.caption))
        .accessibilityIdentifier("welcome.ecard.message." + photo.side.rawValue)
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
