import Foundation
import Observation
import UIKit
@preconcurrency import AVFAudio
@preconcurrency import Speech
@preconcurrency import UserNotifications

/// Native device features. No permissions are requested during initialization.
/// Audio stays in memory and recognition is allowed only when it can stay on device.
@MainActor
@Observable
final class DeviceServices: NSObject {
    private(set) var isListening = false
    private(set) var isSpeaking = false
    private(set) var notificationStatus = String(localized: "Wird geprüft")
    var errorMessage: String?
    var notificationNodeID: UUID?

    @ObservationIgnored private let notificationCenter: UNUserNotificationCenter
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let speechSynthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var speechRecognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var audioSink: RecognitionAudioSink?
    @ObservationIgnored private var inputTapInstalled = false
    @ObservationIgnored private var recordingSessionID: UUID?
    @ObservationIgnored private var recordingPreparationID: UUID?
    @ObservationIgnored private var activeUtteranceID: ObjectIdentifier?
    @ObservationIgnored private var observerTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var notificationGeneration = 0
    @ObservationIgnored private var isReconciling = false
    @ObservationIgnored private var desiredNotificationState: AppState?

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.notificationCenter = notificationCenter
        self.clock = now
        self.calendar = calendar
        super.init()
        notificationCenter.delegate = self
        speechSynthesizer.delegate = self
        // The app owns one service for its lifetime. Weak observers never retain it.
        for name in [AVAudioSession.interruptionNotification, UIApplication.didEnterBackgroundNotification] {
            observerTokens.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let wasListening = self.isListening
                    self.stopAudio()
                    if wasListening {
                        self.errorMessage = String(localized: "Aufnahme unterbrochen. Dein Text bleibt erhalten.")
                    }
                }
            })
        }
    }

    // MARK: Local notifications

    func refreshNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            notificationStatus = String(localized: "Noch nicht angefragt")
        case .denied:
            notificationStatus = String(localized: "In iOS nicht erlaubt")
        case .authorized:
            notificationStatus = String(localized: "Erlaubt")
        case .provisional, .ephemeral:
            notificationStatus = String(localized: "Eingeschränkt erlaubt")
        @unknown default:
            notificationStatus = String(localized: "iOS-Status unbekannt")
        }
    }

    /// Call only after the person deliberately asks to enable reminders.
    func requestNotifications() async -> Bool {
        do {
            let allowed = try await notificationCenter.requestAuthorization(options: [.alert, .sound])
            await refreshNotificationStatus()
            if !allowed {
                errorMessage = String(localized: "Mitteilungen in den iOS-Einstellungen erlauben.")
            }
            return allowed
        } catch {
            errorMessage = String(localized: "Mitteilungsberechtigung konnte nicht geprüft werden.")
            return false
        }
    }

    /// Serial reconciliation prevents a pending scheduling callback from reviving
    /// a reminder after logging, deletion, or disabling reminders.
    func reconcileNotifications(state: AppState) async {
        notificationGeneration += 1
        desiredNotificationState = state
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }
        while let next = desiredNotificationState {
            desiredNotificationState = nil
            let generation = notificationGeneration
            await applyNotificationState(next, generation: generation)
        }
    }

    func cancelAllNotifications() async {
        notificationGeneration += 1
        desiredNotificationState = nil
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        notificationNodeID = nil
    }

    private func applyNotificationState(_ state: AppState, generation: Int) async {
        guard state.notificationsEnabled else {
            notificationCenter.removeAllPendingNotificationRequests()
            notificationCenter.removeAllDeliveredNotifications()
            await refreshNotificationStatus()
            return
        }
        let settings = await notificationCenter.notificationSettings()
        guard generation == notificationGeneration else { return }
        let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        guard allowed else {
            notificationCenter.removeAllPendingNotificationRequests()
            await refreshNotificationStatus()
            errorMessage = String(localized: "Mitteilungen in den iOS-Einstellungen erlauben.")
            return
        }

        let reminders = Array(notificationCandidates(state: state).sorted { $0.date < $1.date }.prefix(60))
        let desiredIDs = Set(reminders.map(\.id))
        let pending = await notificationCenter.pendingNotificationRequests()
        guard generation == notificationGeneration else { return }
        let obsolete = pending.map(\.identifier).filter { $0.hasPrefix("sovi.") && !desiredIDs.contains($0) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: obsolete)
        // Clear delivered reminders whose records were logged or removed as well.
        let delivered = await notificationCenter.deliveredNotifications()
        guard generation == notificationGeneration else { return }
        let oldDelivered = delivered.map { $0.request.identifier }.filter { $0.hasPrefix("sovi.") && !desiredIDs.contains($0) }
        notificationCenter.removeDeliveredNotifications(withIdentifiers: oldDelivered)

        for reminder in reminders {
            guard generation == notificationGeneration else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Sovi")
            content.body = String(localized: "Ein Eintrag wartet auf dich.")
            content.sound = .default
            content.userInfo = ["nodeID": reminder.nodeID.uuidString]
            var notificationCalendar = calendar
            notificationCalendar.timeZone = reminder.timeZone
            var components = notificationCalendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: reminder.date
            )
            components.calendar = notificationCalendar
            components.timeZone = reminder.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await notificationCenter.add(UNNotificationRequest(
                    identifier: reminder.id, content: content, trigger: trigger
                ))
                // A deletion can happen while the OS is accepting this request.
                if generation != notificationGeneration {
                    notificationCenter.removePendingNotificationRequests(withIdentifiers: [reminder.id])
                    return
                }
            } catch {
                errorMessage = String(localized: "Erinnerung konnte nicht gespeichert werden.")
            }
        }
        guard generation == notificationGeneration else { return }
        await refreshNotificationStatus()
    }

    private struct Reminder {
        var id: String
        var date: Date
        var nodeID: UUID
        var timeZone: TimeZone
    }

    private func notificationCandidates(state: AppState) -> [Reminder] {
        let now = clock()
        var candidates: [Reminder] = []
        for schedule in state.schedules {
            guard let node = state.nodes.first(where: { $0.scheduleID == schedule.id }) else { continue }
            let zone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? calendar.timeZone
            for occurrence in schedule.occurrences where occurrence.log == .unrecorded && occurrence.date > now {
                candidates.append(Reminder(
                    id: "sovi.medication.\(schedule.id.uuidString).\(occurrence.id.uuidString)",
                    date: occurrence.date, nodeID: node.id, timeZone: zone
                ))
            }
        }
        for appointment in state.appointments where appointment.status == .confirmed && appointment.attendance == .unrecorded && appointment.date > now {
            guard let node = state.nodes.first(where: { $0.appointmentID == appointment.id }) else { continue }
            candidates.append(Reminder(
                id: "sovi.appointment.\(appointment.id.uuidString)",
                date: appointment.date, nodeID: node.id, timeZone: calendar.timeZone
            ))
        }
        return candidates
    }

    // MARK: Push to talk

    /// A tap starts or stops recording. Opening Sovi never calls this method.
    /// Recognized text is returned for editing, never sent as a conversation turn.
    func toggleRecording(onTranscript: @escaping @MainActor (String) -> Void) async {
        if isListening {
            stopRecording()
            return
        }
        guard recordingPreparationID == nil else { return }
        stopAudio()
        let preparationID = UUID()
        recordingPreparationID = preparationID
        defer {
            if recordingPreparationID == preparationID { recordingPreparationID = nil }
        }

        // Check local support first so unsupported devices do not receive prompts.
        let recognizers = ["de-AT", "de-DE"].compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
        guard let recognizer = recognizers.first(where: { $0.supportsOnDeviceRecognition }) else {
            errorMessage = String(localized: "Spracherkennung nicht verfügbar. Bitte tippe deine Nachricht.")
            return
        }
        let speechAuthorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
        guard recordingPreparationID == preparationID else { return }
        guard speechAuthorization == .authorized else {
            errorMessage = String(localized: "Spracherkennung in den iOS-Einstellungen erlauben.")
            return
        }
        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
        guard recordingPreparationID == preparationID else { return }
        guard microphoneAllowed else {
            errorMessage = String(localized: "Mikrofon in den iOS-Einstellungen erlauben.")
            return
        }
        guard recognizer.isAvailable, recognizer.supportsOnDeviceRecognition,
              UIApplication.shared.applicationState == .active else {
            errorMessage = String(localized: "Spracherkennung nicht verfügbar. Bitte tippe deine Nachricht.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            let sink = RecognitionAudioSink(request: request)
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw AudioFeatureError.noInput
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                sink.append(buffer)
            }
            inputTapInstalled = true
            audioSink = sink
            speechRecognizer = recognizer
            let sessionID = UUID()
            recordingSessionID = sessionID
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let transcript = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let didFail = error != nil
                Task { @MainActor [weak self] in
                    guard let self, self.recordingSessionID == sessionID else { return }
                    if let transcript { onTranscript(transcript) }
                    if isFinal || didFail {
                        self.stopRecording()
                        if didFail {
                            self.errorMessage = String(localized: "Aufnahme beendet. Bitte prüfe den Text.")
                        }
                    }
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = audioEngine.isRunning
        } catch {
            stopRecording()
            errorMessage = String(localized: "Aufnahme nicht möglich. Bitte tippe deine Nachricht.")
        }
    }

    func stopAudio() {
        recordingPreparationID = nil
        // Ordinary chat taps must not synchronously deactivate an unused audio session.
        guard isListening || isSpeaking || recordingSessionID != nil || activeUtteranceID != nil
                || inputTapInstalled || audioEngine.isRunning || recognitionTask != nil else { return }
        stopRecording()
        activeUtteranceID = nil
        speechSynthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func stopRecording() {
        recordingSessionID = nil
        if audioEngine.isRunning { audioEngine.stop() }
        if inputTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        audioSink?.finish()
        audioSink = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        speechRecognizer = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Explicitly opt-in. The displayed reply remains the caption for the audio.
    func speak(_ text: String, enabled: Bool) {
        guard enabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        stopAudio()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try session.setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "de-AT") ?? AVSpeechSynthesisVoice(language: "de-DE")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            activeUtteranceID = ObjectIdentifier(utterance)
            speechSynthesizer.speak(utterance)
        } catch {
            errorMessage = String(localized: "Vorlesen ist gerade nicht verfügbar.")
        }
    }

    func cleanupExports() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SoviExports", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            errorMessage = String(localized: "Exportdateien konnten nicht vollständig gelöscht werden.")
        }
    }

    private enum AudioFeatureError: Error { case noInput }
}

extension DeviceServices: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.content.userInfo["nodeID"] as? String
        guard let identifier, let nodeID = UUID(uuidString: identifier) else { return }
        await MainActor.run { self.notificationNodeID = nodeID }
        // Opening a notification never logs a dose or changes any record.
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension DeviceServices: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == identifier else { return }
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishSpeaking(identifier: ObjectIdentifier(utterance))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishSpeaking(identifier: ObjectIdentifier(utterance))
    }

    nonisolated private func finishSpeaking(identifier: ObjectIdentifier) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtteranceID == identifier else { return }
            self.activeUtteranceID = nil
            self.isSpeaking = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

/// The audio render callback never touches observable/main-actor state. A lock
/// serializes append/endAudio on this legacy thread-safe framework request.
private final class RecognitionAudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var finished = false

    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if !finished { request.append(buffer) }
    }

    func finish() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        request.endAudio()
    }
}
