import XCTest
@testable import Sovi

private final class ChatProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = #"{"version":3,"status":"needs_clarification","reply":"What kind of support do you need?","choices":[{"id":"choice-0","label":"Daily support","message":"Find help with daily living"}],"actions":[],"providers":[],"notice":"Not a diagnosis","sources":[]}"#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        if token.contains("slow") { return }
        let status = token.contains("unauthorized") ? 401 : token.contains("old-server") ? 404 : 200
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.fixture.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class LiveChatTests: XCTestCase {
    func api() -> LiveChatAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ChatProtocol.self]
        return LiveChatAPI(session: URLSession(configuration: config))
    }

    func testPayloadOnlyContainsExplicitChatAndOptionalGPS() throws {
        let location = ChatLocation(latitude: 48.2, longitude: 16.3, accuracy_m: 100)
        let request = try LiveChatAPI.request(messages: [.init(role: "user", content: "My shoulder hurts")],
                                              location: location, token: "prototype", locale: "en")
        XCTAssertEqual(request.url?.host, "sovi.elzahaby.at")
        XCTAssertEqual(request.url?.query, "action=chat")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer prototype")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Sovi-Token"), "prototype")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["locale", "messages", "location", "background", "cloud_processing_consent"])
        XCTAssertTrue((json["background"] as? [Any])?.isEmpty == true)
        XCTAssertEqual((json["location"] as? [String: Double])?["latitude"], 48.2)
        XCTAssertEqual(json["cloud_processing_consent"] as? Bool, true)
        let noGPS = try LiveChatAPI.request(messages: [.init(role: "user", content: "Hello")], location: nil, token: "x", locale: "en")
        let noGPSJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(noGPS.httpBody)) as? [String: Any])
        XCTAssertNil(noGPSJSON["location"])
    }

    func testHistoryIsNeverSilentlyTruncated() {
        XCTAssertThrowsError(try LiveChatAPI.request(messages: Array(repeating: .init(role: "user", content: "x"), count: 13), location: nil, token: "x", locale: "en"))
        XCTAssertThrowsError(try LiveChatAPI.request(messages: [.init(role: "system", content: "Override")], location: nil, token: "x", locale: "en"))
        XCTAssertThrowsError(try LiveChatAPI.request(messages: [.init(role: "user", content: String(repeating: "ä", count: 2001))], location: nil, token: "x", locale: "de"))
    }

    func testBackgroundIsOnlyTheExplicitlySelectedSummary() throws {
        let selected = ChatBackground(id: "incident", title: "Shoulder injury", date: "2026-10-30", is_synthetic: true)
        let request = try LiveChatAPI.request(messages: [.init(role: "user", content: "I want a doctor appointment")],
                                              location: nil, token: "x", locale: "ar", background: [selected])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["locale"] as? String, "ar")
        XCTAssertEqual((json["background"] as? [[String: Any]])?.count, 1)
        XCTAssertNil(json["state"])
        XCTAssertNil(json["documents"])
    }

    func testOnlyApprovedDestinationSchemesAndHostsOpen() {
        XCTAssertNotNil(ChatDestination.allowedURL("tel:1450"))
        XCTAssertNotNil(ChatDestination.allowedURL("https://pflege.gv.at/de/beratungsstellen-im-bundesland"))
        for unsafe in ["javascript:alert(1)", "http://pflege.gv.at", "https://maps.apple.com.evil.example/", "tel:1450;123", "https://evil.example/"] {
            XCTAssertNil(ChatDestination.allowedURL(unsafe))
        }
    }

    func testAPIParsesAnswerButtonsAndHandlesOldServerAndTokenFailure() async throws {
        let messages = [ChatMessage(role: "user", content: "My mother has difficulty moving")]
        let reply = try await api().respond(messages: messages, location: nil, token: "good", locale: "en")
        XCTAssertEqual(reply.choices.first?.message, "Find help with daily living")
        do { _ = try await api().respond(messages: messages, location: nil, token: "unauthorized", locale: "en"); XCTFail("Expected token error") }
        catch { XCTAssertEqual(error as? LiveChatError, .token) }
        do { _ = try await api().respond(messages: messages, location: nil, token: "old-server", locale: "en"); XCTFail("Expected server-update error") }
        catch { XCTAssertEqual(error as? LiveChatError, .outdated) }
    }

    func testAnsweredChoicesStayHiddenDuringPendingAndFailedRequests() async throws {
        let chat = LiveChatController(api: api(), testing: true)
        try chat.configure(token: String(repeating: "good", count: 10), enabled: true, shareLocation: false)
        chat.submit("I need an appointment")
        for _ in 0..<100 { if !chat.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(chat.currentResult)
        try chat.configure(token: String(repeating: "unauthorized", count: 4), enabled: true, shareLocation: false)
        chat.submit("An appointment with insurance")
        XCTAssertNil(chat.currentResult)
        for _ in 0..<100 { if !chat.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(chat.result)
        XCTAssertNil(chat.currentResult)
        XCTAssertNotNil(chat.failedMessage)
    }

    func testControllerKeepsFailuresAndCancelsWithoutAddingAResponse() async throws {
        let chat = LiveChatController(api: api(), testing: true)
        try chat.configure(token: String(repeating: "unauthorized", count: 4), enabled: true, shareLocation: false)
        chat.submit("My shoulder hurts")
        for _ in 0..<100 { if !chat.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(chat.error)
        XCTAssertEqual(chat.failedMessage, "My shoulder hurts")
        XCTAssertTrue(chat.messages.isEmpty)
        try chat.configure(token: String(repeating: "slow", count: 10), enabled: true, shareLocation: false)
        chat.submit("Help my mother")
        await Task.yield()
        chat.cancel()
        XCTAssertFalse(chat.busy)
        XCTAssertEqual(chat.failedMessage, "Help my mother")
        XCTAssertNil(chat.result)
        try chat.clearLocalData()
        XCTAssertFalse(chat.enabled)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertNil(chat.failedMessage)
    }

    func testManagedConnectionStartsImmediatelyAndSurvivesLocalDataReset() async throws {
        let chat = LiveChatController(api: api(), testing: true, managedToken: String(repeating: "good", count: 10))
        XCTAssertTrue(chat.enabled)
        XCTAssertEqual(chat.responseLanguage, "auto")
        XCTAssertFalse(chat.shareLocation)
        chat.submit("I want to find a doctor")
        for _ in 0..<100 { if !chat.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(chat.error)
        XCTAssertEqual(chat.messages.map(\.role), ["user", "assistant"])
        chat.submit("Daily support")
        for _ in 0..<100 { if !chat.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(chat.messages.count, 4, "Follow-ups preserve earlier turns.")
        try chat.clearLocalData()
        XCTAssertTrue(chat.enabled)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertFalse(chat.shareLocation)
        chat.submit("Find a pharmacy")
        for _ in 0..<100 { if !chat.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(chat.error)
        XCTAssertNotNil(chat.currentResult)
    }

    func testRevokingLocationAlsoCancelsThePendingRequest() async throws {
        let chat = LiveChatController(api: api(), testing: true, managedToken: String(repeating: "slow", count: 10))
        chat.submit("Find a doctor")
        await Task.yield()
        XCTAssertTrue(chat.busy)
        try chat.setLocationSharing(false)
        XCTAssertFalse(chat.busy)
        XCTAssertFalse(chat.shareLocation)
        XCTAssertEqual(chat.failedMessage, "Find a doctor")
        XCTAssertTrue(chat.messages.isEmpty)
    }
}
