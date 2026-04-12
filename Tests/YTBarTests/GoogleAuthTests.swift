import XCTest
@testable import YTBar

@MainActor
final class GoogleAuthTests: XCTestCase {
    private var mockClient: MockAuthHTTPClient!
    private var keychain: KeychainHelper!
    private var sut: GoogleAuth!

    override func setUp() {
        super.setUp()
        mockClient = MockAuthHTTPClient()
        keychain = KeychainHelper(service: "com.ytbar.auth.test2")
        keychain.delete()
        sut = GoogleAuth(client: mockClient, keychain: keychain)
    }

    override func tearDown() {
        keychain.delete()
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsUnauthenticated() {
        XCTAssertFalse(sut.isAuthenticated)
        XCTAssertNil(sut.userCode)
        XCTAssertNil(sut.verificationURL)
    }

    func testInitWithValidKeychainTokenIsAuthenticated() throws {
        let tokens = makeTokens(expired: false)
        try keychain.save(tokens)

        let auth = GoogleAuth(client: mockClient, keychain: keychain)
        XCTAssertTrue(auth.isAuthenticated)
    }

    func testInitWithExpiredKeychainTokenIsNotAuthenticated() throws {
        let tokens = makeTokens(expired: true)
        try keychain.save(tokens)

        let auth = GoogleAuth(client: mockClient, keychain: keychain)
        XCTAssertFalse(auth.isAuthenticated)
    }

    // MARK: - Device Flow

    func testStartDeviceFlowSetsUserCode() async throws {
        mockClient.result = makeDeviceCodeResponse()
        try await sut.startDeviceFlow()

        XCTAssertEqual(sut.userCode, "ABCD-EFGH")
        XCTAssertEqual(
            sut.verificationURL,
            "https://www.google.com/device"
        )
    }

    func testStartDeviceFlowRequestFormat() async throws {
        mockClient.result = makeDeviceCodeResponse()
        try await sut.startDeviceFlow()

        let request = mockClient.lastRequest
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertTrue(
            request?.url?.absoluteString
                .contains("device/code") ?? false
        )
    }

    // MARK: - Poll For Token

    func testPollForTokenSuccess() async throws {
        mockClient.result = makeTokenResponse()
        try await sut.pollForToken(deviceCode: "test-device-code")

        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertNotNil(keychain.retrieve())
    }

    func testPollForTokenStoresInKeychain() async throws {
        mockClient.result = makeTokenResponse()
        try await sut.pollForToken(deviceCode: "test-device-code")

        let stored = keychain.retrieve()
        XCTAssertEqual(stored?.accessToken, "ya29.access")
        XCTAssertEqual(stored?.refreshToken, "1//refresh")
    }

    // MARK: - Refresh Token

    func testRefreshTokenUpdatesTokens() async throws {
        let old = makeTokens(expired: true)
        try keychain.save(old)
        mockClient.result = makeRefreshResponse()

        try await sut.refreshToken()

        let stored = keychain.retrieve()
        XCTAssertEqual(stored?.accessToken, "ya29.refreshed")
        XCTAssertTrue(sut.isAuthenticated)
    }

    func testRefreshTokenWithNoKeychainThrows() async {
        do {
            try await sut.refreshToken()
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is GoogleAuthError)
        }
    }

    // MARK: - Logout

    func testLogoutClearsState() throws {
        try keychain.save(makeTokens(expired: false))
        let auth = GoogleAuth(client: mockClient, keychain: keychain)
        XCTAssertTrue(auth.isAuthenticated)

        auth.logout()

        XCTAssertFalse(auth.isAuthenticated)
        XCTAssertNil(keychain.retrieve())
    }

    // MARK: - Helpers

    private func makeTokens(expired: Bool) -> AuthTokens {
        let offset: TimeInterval = expired ? -3600 : 3600
        return AuthTokens(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(offset)
        )
    }

    private func makeDeviceCodeResponse() -> (Data, URLResponse) {
        let json: [String: Any] = [
            "device_code": "device123",
            "user_code": "ABCD-EFGH",
            "verification_url": "https://www.google.com/device",
            "expires_in": 1800,
            "interval": 5,
        ]
        return makeResponse(json: json)
    }

    private func makeTokenResponse() -> (Data, URLResponse) {
        let json: [String: Any] = [
            "access_token": "ya29.access",
            "refresh_token": "1//refresh",
            "expires_in": 3600,
            "token_type": "Bearer",
        ]
        return makeResponse(json: json)
    }

    private func makeRefreshResponse() -> (Data, URLResponse) {
        let json: [String: Any] = [
            "access_token": "ya29.refreshed",
            "expires_in": 3600,
            "token_type": "Bearer",
        ]
        return makeResponse(json: json)
    }

    private func makeResponse(
        json: [String: Any]
    ) -> (Data, URLResponse) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: URL(string: "https://oauth2.googleapis.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

// MARK: - Mock

final class MockAuthHTTPClient: HTTPClient, @unchecked Sendable {
    var result: (Data, URLResponse)?
    var lastRequest: URLRequest?
    var error: Error?

    func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error { throw error }
        return result!
    }
}
