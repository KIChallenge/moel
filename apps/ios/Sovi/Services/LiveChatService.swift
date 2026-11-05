import Foundation
import Observation
import Security
@preconcurrency import CoreLocation

struct ChatMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
}

struct ChatLocation: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var accuracy_m: Double
}

struct ChatChoice: Decodable, Identifiable, Sendable {
    var id: String
    var label: String
    var message: String
    var opens_composer: Bool?
}

struct ChatBackground: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var date: String
    var is_synthetic: Bool
}

struct ChatLink: Decodable, Sendable {
    var label: String
    var url: String
    var safeURL: URL? { ChatDestination.allowedURL(url) }
}

struct ChatSource: Decodable, Sendable {
    var title: String
    var url: String
}

struct ChatProvider: Decodable, Identifiable, Sendable {
    var id: String
    var name: String
    var specialty: String
    var address: String
    var distance_km: Double?
    var phone: String?
    var url: String?
    var map_url: String
    var insurance_verified: Bool
    var source_url: String
    var source_label: String
    var retrieved_at: String
    var latitude: Double?
    var longitude: Double?
}

enum ChatDestination {
    static func allowedURL(_ string: String) -> URL? {
        guard let url = URL(string: string) else { return nil }
        if url.scheme == "tel", string.range(of: #"^tel:\+?[0-9]{3,16}$"#, options: .regularExpression) != nil { return url }
        let hosts = ["www.gesundheit.gv.at", "pflege.gv.at", "www.pflege.gv.at", "www.apothekerkammer.at",
                     "www.data.gv.at", "praxisplan.at", "maps.apple.com", "www.sozialversicherung.at", "rehakompass.goeg.at"]
        guard url.scheme == "https", let host = url.host, hosts.contains(host), url.user == nil, url.password == nil else { return nil }
        return url
    }
}

struct LiveChatReply: Decodable, Sendable {
    var version: Int
    var status: String
    var reply: String
    var choices: [ChatChoice]
    var actions: [ChatLink]
    var providers: [ChatProvider]
    var notice: String
    var sources: [ChatSource]
    var language: String?
}

enum LiveChatError: LocalizedError {
    case setup, token, outdated, limit, unavailable, invalidReply, tooLong
    var errorDescription: String? {
        switch self {
        case .setup: String(localized: "Bitte aktiviere den Online-Chat in den Chat-Einstellungen.")
        case .token: String(localized: "Der API-Zugangscode ist ungültig. Prüfe die Chat-Einstellungen.")
        case .outdated: String(localized: "Der Server braucht das Chat-Update (Version 3). Bitte aktualisiere sovi.php auf dem Hosting.")
        case .limit: String(localized: "Das Anfrage-Limit ist erreicht. Bitte versuche es später erneut.")
        case .unavailable: String(localized: "Sovi ist gerade nicht erreichbar. Deine Nachricht bleibt zum erneuten Senden erhalten.")
        case .invalidReply: String(localized: "Die Serverantwort konnte nicht geprüft werden. Bitte versuche es erneut.")
        case .tooLong: String(localized: "Dieses Gespräch ist zu lang. Starte ein neues Gespräch und nenne die wichtigen Angaben erneut.")
        }
    }
}

/// Never follow redirects with the prototype token, conversation or GPS attached.
private final class ChatRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct LiveChatAPI: Sendable {
    static let endpoint = URL(string: "https://sovi.elzahaby.at/?action=chat")!
    var session: URLSession

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 35
        self.session = session ?? URLSession(configuration: configuration, delegate: ChatRedirectGuard(), delegateQueue: nil)
    }

    static func request(messages: [ChatMessage], location: ChatLocation?, token: String, locale: String, background: [ChatBackground] = []) throws -> URLRequest {
        guard !messages.isEmpty, messages.count <= 12, messages.last?.role == "user",
              messages.allSatisfy({ ["user", "assistant"].contains($0.role) && !$0.content.isEmpty && $0.content.utf8.count <= 4000 }),
              messages.reduce(0, { $0 + $1.content.utf8.count }) <= 16000 else { throw LiveChatError.tooLong }
        struct Payload: Encodable {
            var locale: String
            var cloud_processing_consent = true
            var messages: [ChatMessage]
            var location: ChatLocation?
            var background: [ChatBackground]
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        // Shared-host CGI setups can strip Authorization; PHP accepts this too.
        request.setValue(token, forHTTPHeaderField: "X-Sovi-Token")
        request.httpBody = try JSONEncoder().encode(Payload(locale: locale, messages: messages, location: location, background: background))
        return request
    }

    func respond(messages: [ChatMessage], location: ChatLocation?, token: String, locale: String, background: [ChatBackground] = []) async throws -> LiveChatReply {
        let request = try Self.request(messages: messages, location: location, token: token, locale: locale, background: background)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw LiveChatError.invalidReply }
        switch response.statusCode {
        case 200: break
        case 401: throw LiveChatError.token
        case 404: throw LiveChatError.outdated
        case 429: throw LiveChatError.limit
        default: throw LiveChatError.unavailable
        }
        guard data.count <= 262144,
              let reply = try? JSONDecoder().decode(LiveChatReply.self, from: data), reply.version >= 3,
              !reply.reply.isEmpty, reply.reply.count <= 6000, reply.choices.count <= 8, reply.providers.count <= 3,
              Set(reply.choices.map(\.id)).count == reply.choices.count,
              reply.choices.allSatisfy({ !$0.label.isEmpty && ($0.opens_composer == true || !$0.message.isEmpty) && $0.message.utf8.count <= 4000 })
        else { throw LiveChatError.invalidReply }
        return reply
    }
}

@MainActor
@Observable
final class LiveChatController {
    private(set) var enabled = false
    private(set) var shareLocation = false
    private(set) var responseLanguage = "auto"
    private(set) var localServiceArea: String?
    private(set) var background: [ChatBackground] = []
    private(set) var busy = false
    private(set) var messages: [ChatMessage] = []
    private(set) var result: LiveChatReply?
    private(set) var error: String?
    private(set) var failedMessage: String?
    private(set) var locationNotice: String?
    @ObservationIgnored private var token = ""
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var pendingMessage: String?
    @ObservationIgnored private let location = ChatLocationService()
    @ObservationIgnored private let api: LiveChatAPI
    @ObservationIgnored private let testing: Bool

    init(api: LiveChatAPI = LiveChatAPI(), testing: Bool = ProcessInfo.processInfo.arguments.contains("--uitesting")) {
        self.api = api
        self.testing = testing
        if !testing, let saved = try? ChatCredentials.read() {
            token = saved.token; enabled = saved.enabled; shareLocation = saved.shareLocation
            responseLanguage = saved.responseLanguage ?? "auto"
        }
    }

    var editableToken: String { token }
    func enableLocationFromWelcome() async throws -> Bool {
        let allowed = await location.requestPermission()
        try configure(token: token, enabled: enabled, shareLocation: allowed, responseLanguage: responseLanguage)
        return allowed
    }
    /// Only a coarse place name is returned to local demos; coordinates are not saved.
    func refreshLocalServiceArea() async -> String? {
        guard shareLocation, let point = await location.currentLocation() else { return nil }
        let geocoder = CLGeocoder()
        guard let place = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: point.latitude, longitude: point.longitude)).first,
              place.isoCountryCode == "AT" else { localServiceArea = nil; return nil }
        localServiceArea = place.locality ?? place.administrativeArea
        return localServiceArea
    }
    func currentServiceLocation() async -> ChatLocation? {
        guard shareLocation else { return nil }
        return await location.currentLocation()
    }
    var displayMessages: [ChatMessage] {
        let pending = busy ? pendingMessage : failedMessage
        return messages + (pending.map { [ChatMessage(role: "user", content: $0)] } ?? [])
    }

    func configure(token: String, enabled: Bool, shareLocation: Bool, responseLanguage: String = "auto") throws {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if enabled && (token.utf8.count < 32 || token.rangeOfCharacter(from: .whitespacesAndNewlines) != nil) { throw LiveChatError.token }
        guard ["auto", "de", "en", "ar", "tr"].contains(responseLanguage) else { throw LiveChatError.setup }
        if !testing { try ChatCredentials.save(.init(token: token, enabled: enabled, shareLocation: shareLocation, responseLanguage: responseLanguage)) }
        cancel()
        self.token = token; self.enabled = enabled; self.shareLocation = shareLocation
        if !shareLocation { localServiceArea = nil }
        self.responseLanguage = responseLanguage
        if !enabled { reset() }
    }

    func submit(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !message.isEmpty else { return }
        guard enabled else { error = LiveChatError.setup.localizedDescription; return }
        let pending = messages + [ChatMessage(role: "user", content: message)]
        do { _ = try LiveChatAPI.request(messages: pending, location: nil, token: token, locale: "de") }
        catch { self.error = error.localizedDescription; failedMessage = message; return }
        busy = true; error = nil; failedMessage = nil; locationNotice = nil; pendingMessage = message
        let id = UUID(); generation = id
        let token = token
        let locale = responseLanguage
        let background = background
        operation = Task { @MainActor in
            do {
                let coordinates = shareLocation ? await location.currentLocation() : nil
                try Task.checkCancellation()
                guard generation == id, enabled else { return }
                if shareLocation && coordinates == nil {
                    locationNotice = String(localized: "Kein aktueller Standort verfügbar. Du kannst einen Ort im Chat nennen.")
                }
                let reply = try await api.respond(messages: pending, location: coordinates, token: token, locale: locale, background: background)
                try Task.checkCancellation()
                guard generation == id, enabled else { return }
                messages = pending + [ChatMessage(role: "assistant", content: reply.reply)]
                result = reply
                busy = false; operation = nil; pendingMessage = nil
            } catch is CancellationError {
                if generation == id { busy = false; operation = nil }
            } catch {
                guard generation == id else { return }
                self.error = (error as? LiveChatError)?.localizedDescription ?? LiveChatError.unavailable.localizedDescription
                failedMessage = message; busy = false; operation = nil; pendingMessage = nil
            }
        }
    }

    func cancel() {
        if busy { failedMessage = pendingMessage; error = String(localized: "Senden abgebrochen. Du kannst die Nachricht erneut senden.") }
        generation = UUID(); operation?.cancel(); operation = nil; location.cancel(); busy = false
        pendingMessage = nil
    }
    func reset() { cancel(); messages = []; result = nil; error = nil; failedMessage = nil; locationNotice = nil }
    func setBackground(_ entries: [ChatBackground]) {
        if background != entries { reset(); background = Array(entries.prefix(4)) }
    }
    func deleteCredentials() throws {
        reset()
        if !testing { try ChatCredentials.delete() }
        token = ""; enabled = false; shareLocation = false; background = []; responseLanguage = "auto"
        localServiceArea = nil
    }
}

private enum ChatCredentials {
    struct Settings: Codable { var token: String; var enabled: Bool; var shareLocation: Bool; var responseLanguage: String? }
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "at.sovi.cloud-chat",
         kSecAttrAccount as String: "prototype-v1"]
    }
    static func read() throws -> Settings? {
        var query = query; query[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw LiveChatError.setup }
        return try JSONDecoder().decode(Settings.self, from: data)
    }
    static func save(_ settings: Settings) throws {
        let data = try JSONEncoder().encode(settings)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LiveChatError.setup }
        } else if status != errSecSuccess { throw LiveChatError.setup }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LiveChatError.setup }
    }
}

@MainActor
private final class ChatLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<ChatLocation?, Never>?
    private var timeout: Task<Void, Never>?
    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func requestPermission() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                permissionContinuation?.resume(returning: false)
                permissionContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        default: return false
        }
    }
    func currentLocation() async -> ChatLocation? {
        cancel()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                self?.finish(nil)
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            default: finish(nil)
            }
        }
    }
    func cancel() { finish(nil); permissionContinuation?.resume(returning: false); permissionContinuation = nil }
    private func finish(_ value: ChatLocation?) {
        timeout?.cancel(); timeout = nil; manager.stopUpdatingLocation()
        let pending = continuation; continuation = nil; pending?.resume(returning: value)
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.manager.authorizationStatus != .notDetermined {
                permissionContinuation?.resume(returning: self.manager.authorizationStatus == .authorizedAlways || self.manager.authorizationStatus == .authorizedWhenInUse)
                permissionContinuation = nil
            }
            guard continuation != nil else { return }
            switch self.manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: finish(nil)
            default: break
            }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let point = locations.last, point.horizontalAccuracy >= 0, abs(point.timestamp.timeIntervalSinceNow) <= 30 else { return }
        let value = ChatLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude, accuracy_m: point.horizontalAccuracy)
        Task { @MainActor [weak self] in self?.finish(value) }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in self?.finish(nil) }
    }
}
