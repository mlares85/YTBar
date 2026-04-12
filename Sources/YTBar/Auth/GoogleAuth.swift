import Foundation

protocol HTTPClient: Sendable {
    func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

enum GoogleAuthError: Error {
    case noTokens
    case invalidResponse
    case deviceFlowFailed(String)
}

@MainActor
final class GoogleAuth: ObservableObject {
    @Published var isAuthenticated = false
    @Published var userCode: String?
    @Published var verificationURL: String?
    var deviceCode: String?

    private let client: HTTPClient
    private let keychain: KeychainHelper
    private var clientID: String
    private var clientSecret: String
    private let scope = "https://www.googleapis.com/auth/youtube"

    init(
        client: HTTPClient = URLSession.shared,
        keychain: KeychainHelper = KeychainHelper()
    ) {
        self.client = client
        self.keychain = keychain
        let config = AppConfig.load()
        self.clientID = config.clientID
        self.clientSecret = config.clientSecret
        loadExistingTokens()
    }

    func updateCredentials(id: String, secret: String) {
        clientID = id
        clientSecret = secret
    }

    func startDeviceFlow() async throws {
        let body = buildDeviceCodeBody()
        logToFile("POST \(Endpoints.deviceCode)")
        logToFile("Body: \(body)")
        let data: Data
        do {
            data = try await post(url: Endpoints.deviceCode, body: body)
        } catch {
            logToFile("Request failed: \(error)")
            throw error
        }
        let raw = String(data: data, encoding: .utf8) ?? "nil"
        logToFile("Response: \(raw)")
        let response = try parseJSON(data)
        userCode = response["user_code"] as? String
        deviceCode = response["device_code"] as? String
        verificationURL = response["verification_url"] as? String
        logToFile("userCode: \(userCode ?? "nil"), deviceCode: \(deviceCode != nil ? "set" : "nil")")
    }

    func pollForToken(deviceCode: String) async throws {
        let body = buildPollBody(deviceCode: deviceCode)
        let data = try await post(
            url: Endpoints.token,
            body: body
        )
        let raw = String(data: data, encoding: .utf8) ?? ""
        logToFile("Poll status: received response")
        let json = try parseJSON(data)
        if let error = json["error"] as? String {
            throw GoogleAuthError.deviceFlowFailed(error)
        }
        let tokens = try parseTokenResponse(data)
        try keychain.save(tokens)
        cachedAccessToken = tokens.accessToken
        isAuthenticated = true
    }

    func refreshToken() async throws {
        guard let existing = keychain.retrieve() else {
            throw GoogleAuthError.noTokens
        }
        let body = buildRefreshBody(
            refreshToken: existing.refreshToken
        )
        let data = try await post(
            url: Endpoints.token,
            body: body
        )
        let tokens = try parseRefreshResponse(
            data,
            existingRefresh: existing.refreshToken
        )
        try keychain.save(tokens)
        cachedAccessToken = tokens.accessToken
        isAuthenticated = true
    }

    nonisolated(unsafe) var cachedAccessToken: String?

    func logout() {
        keychain.delete()
        cachedAccessToken = nil
        isAuthenticated = false
        userCode = nil
        verificationURL = nil
    }
}

// MARK: - Private

private extension GoogleAuth {
    enum Endpoints {
        static let deviceCode =
            "https://oauth2.googleapis.com/device/code"
        static let token =
            "https://oauth2.googleapis.com/token"
    }

    func logToFile(_ msg: String) {
        DebugLogger.shared.log("[AUTH] \(msg)")
    }

    func loadExistingTokens() {
        guard let tokens = keychain.retrieve() else {
            logToFile("No tokens in keychain")
            return
        }
        logToFile("Tokens found, expired: \(tokens.isExpired)")
        cachedAccessToken = tokens.accessToken
        if tokens.isExpired {
            Task {
                do {
                    try await refreshToken()
                    logToFile("Token refresh succeeded")
                } catch {
                    logToFile("Token refresh failed: \(error)")
                }
            }
        } else {
            isAuthenticated = true
        }
    }

    func post(url: String, body: String) async throws -> Data {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        let (data, _) = try await client.data(for: request)
        return data
    }

    func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any] else {
            throw GoogleAuthError.invalidResponse
        }
        return json
    }

    func buildDeviceCodeBody() -> String {
        "client_id=\(clientID)&scope=\(scope)"
    }

    func buildPollBody(deviceCode: String) -> String {
        "client_id=\(clientID)"
            + "&client_secret=\(clientSecret)"
            + "&device_code=\(deviceCode)"
            + "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
    }

    func buildRefreshBody(refreshToken: String) -> String {
        "client_id=\(clientID)"
            + "&client_secret=\(clientSecret)"
            + "&refresh_token=\(refreshToken)"
            + "&grant_type=refresh_token"
    }

    func parseTokenResponse(_ data: Data) throws -> AuthTokens {
        let json = try parseJSON(data)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Int
        else { throw GoogleAuthError.invalidResponse }
        return AuthTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(
                TimeInterval(expiresIn)
            )
        )
    }

    func parseRefreshResponse(
        _ data: Data,
        existingRefresh: String
    ) throws -> AuthTokens {
        let json = try parseJSON(data)
        guard let access = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int
        else { throw GoogleAuthError.invalidResponse }
        let refresh = json["refresh_token"] as? String
            ?? existingRefresh
        return AuthTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(
                TimeInterval(expiresIn)
            )
        )
    }
}
