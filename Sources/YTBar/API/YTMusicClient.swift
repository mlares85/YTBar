import Foundation

enum YTMusicError: Error, Equatable {
    case httpError(Int)
    case invalidResponse
}

final class YTMusicClient: Sendable {
    private let httpClient: HTTPClient
    private let tokenProvider: @Sendable () -> String?
    let onTokenExpired: @Sendable () async -> Void

    private static let baseURL = "https://music.youtube.com/youtubei/v1"
    // YouTube Music "innertube" API key — the same public key used by the
    // YouTube Music web client for unauthenticated search requests. This is
    // NOT a per-user credential; it's embedded in every YTM web page. Safe
    // to include in source code. See: https://github.com/sigma67/ytmusicapi
    private static let apiKey = "AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30"

    init(
        httpClient: HTTPClient,
        tokenProvider: @escaping @Sendable () -> String?,
        onTokenExpired: @escaping @Sendable () async -> Void = {}
    ) {
        self.httpClient = httpClient
        self.tokenProvider = tokenProvider
        self.onTokenExpired = onTokenExpired
    }

    func search(query: String) async throws -> SearchResult {
        let body: [String: Any] = ["query": query]
        let json = try await post(endpoint: "search", body: body)
        let tracks = YTMusicParser.parseSearchTracks(from: json)
        let playlists = YTMusicParser.parseSearchPlaylists(from: json)
        return SearchResult(tracks: tracks, playlists: playlists)
    }

    func getLibraryPlaylists() async throws -> [Playlist] {
        let json = try await getYTData(
            path: "playlists?part=snippet,contentDetails&mine=true&maxResults=50"
        )
        return YTDataParser.parsePlaylists(from: json)
    }

    func getRadioMix(videoId: String) async throws -> [Track] {
        let body: [String: Any] = [
            "videoId": videoId,
            "isAudioOnly": true,
            "enablePersistentPlaylistPanel": true,
            "tunerSettingValue": "AUTOMIX_SETTING_NORMAL",
            "playlistId": "RDAMVM\(videoId)"
        ]
        let json = try await post(endpoint: "next", body: body)
        return YTMusicParser.parseRadioMix(from: json)
    }

    func getPlaylistTracks(playlistId: String) async throws -> [Track] {
        try await getPlaylistPage(playlistId: playlistId, pageToken: nil).tracks
    }

    func rateVideo(videoId: String, rating: String) async throws {
        try await postYTData(
            path: "videos/rate?id=\(videoId)&rating=\(rating)"
        )
    }

    func getVideoRating(videoId: String) async throws -> String {
        let json = try await getYTData(
            path: "videos/getRating?id=\(videoId)"
        )
        guard let dict = json as? [String: Any],
              let items = dict["items"] as? [[String: Any]],
              let first = items.first,
              let rating = first["rating"] as? String else {
            return "none"
        }
        return rating
    }

    func createPlaylist(title: String) async throws -> String {
        let body: [String: Any] = [
            "snippet": ["title": title],
            "status": ["privacyStatus": "private"]
        ]
        let json = try await postYTDataJSON(
            path: "playlists?part=snippet,status", body: body
        )
        guard let dict = json as? [String: Any],
              let id = dict["id"] as? String else {
            throw YTMusicError.invalidResponse
        }
        return id
    }

    func addToPlaylist(playlistId: String, videoId: String) async throws {
        let body: [String: Any] = [
            "snippet": [
                "playlistId": playlistId,
                "resourceId": [
                    "kind": "youtube#video",
                    "videoId": videoId
                ]
            ]
        ]
        _ = try await postYTDataJSON(
            path: "playlistItems?part=snippet", body: body
        )
    }

    func getPlaylistPage(
        playlistId: String,
        pageToken: String?
    ) async throws -> (tracks: [Track], nextPageToken: String?) {
        var path = "playlistItems?part=snippet,contentDetails&playlistId=\(playlistId)&maxResults=50"
        if let token = pageToken, !token.isEmpty {
            path += "&pageToken=\(token)"
        }
        let json = try await getYTData(path: path)
        return YTDataParser.parsePlaylistPage(from: json)
    }
}

// MARK: - Request Building

extension YTMusicClient {
    private func post(endpoint: String, body: [String: Any]) async throws -> Any {
        let request = try buildRequest(endpoint: endpoint, body: body)
        logToFile("REQ \(endpoint)")
        let (data, response) = try await httpClient.data(for: request)
        try validateResponse(response, data: data)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static let ytDataBase = "https://www.googleapis.com/youtube/v3/"

    private func getYTData(path: String) async throws -> Any {
        let result = try await fetchYTData(path: path)
        let http = result.1 as? HTTPURLResponse
        if http?.statusCode == 401 {
            logToFile("Token expired, refreshing...")
            await onTokenExpired()
            let retry = try await fetchYTData(path: path)
            try validateResponse(retry.1, data: retry.0)
            return try JSONSerialization.jsonObject(with: retry.0)
        }
        try validateResponse(result.1, data: result.0)
        return try JSONSerialization.jsonObject(with: result.0)
    }

    private func postYTDataJSON(path: String, body: [String: Any]) async throws -> Any {
        let url = URL(string: "\(Self.ytDataBase)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        addAuthHeader(to: &request)
        logToFile("REQ YTData POST+body \(path.prefix(40))")
        let (data, response) = try await httpClient.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 401 {
            logToFile("Token expired, refreshing...")
            await onTokenExpired()
            var retry = URLRequest(url: url)
            retry.httpMethod = "POST"
            retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
            retry.httpBody = try JSONSerialization.data(withJSONObject: body)
            addAuthHeader(to: &retry)
            let (retryData, retryResp) = try await httpClient.data(for: retry)
            try validateResponse(retryResp, data: retryData)
            return try JSONSerialization.jsonObject(with: retryData)
        }
        try validateResponse(response, data: data)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func postYTData(path: String) async throws {
        let url = URL(string: "\(Self.ytDataBase)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuthHeader(to: &request)
        logToFile("REQ YTData POST \(path.prefix(40))")
        let (data, response) = try await httpClient.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 401 {
            logToFile("Token expired, refreshing...")
            await onTokenExpired()
            var retry = URLRequest(url: url)
            retry.httpMethod = "POST"
            retry.setValue("application/json", forHTTPHeaderField: "Content-Type")
            addAuthHeader(to: &retry)
            let (retryData, retryResp) = try await httpClient.data(for: retry)
            try validateResponse(retryResp, data: retryData)
            return
        }
        try validateResponse(response, data: data)
    }

    private func fetchYTData(path: String) async throws -> (Data, URLResponse) {
        let url = URL(string: "\(Self.ytDataBase)\(path)")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        addAuthHeader(to: &request)
        logToFile("REQ YTData \(path.prefix(40))")
        return try await httpClient.data(for: request)
    }

    private func buildRequest(endpoint: String, body: [String: Any]) throws -> URLRequest {
        let urlStr = "\(Self.baseURL)/\(endpoint)?key=\(Self.apiKey)"
        var request = URLRequest(url: URL(string: urlStr)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try serializeBody(body)
        return request
    }

    private func addAuthHeader(to request: inout URLRequest) {
        guard let token = tokenProvider() else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func serializeBody(_ body: [String: Any]) throws -> Data {
        var merged = body
        merged["context"] = Self.clientContext
        return try JSONSerialization.data(withJSONObject: merged)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw YTMusicError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            logToFile("HTTP \(http.statusCode): \(body.replacingOccurrences(of: "\n", with: " ").prefix(800))")
            throw YTMusicError.httpError(http.statusCode)
        }
    }

    private func logToFile(_ msg: String) {
        DebugLogger.shared.log("[API] \(msg)")
    }

    private static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:88.0) Gecko/20100101 Firefox/88.0"

    private static var clientContext: [String: Any] {
        let version = "1.\(Self.todayVersion).01.00"
        return [
            "client": [
                "clientName": "WEB_REMIX",
                "clientVersion": version,
                "hl": "en",
                "gl": "US"
            ],
            "user": [String: Any]()
        ]
    }

    private static var todayVersion: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }
}
