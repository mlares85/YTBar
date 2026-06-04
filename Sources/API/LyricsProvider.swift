import Foundation

struct LyricLine: Equatable, Codable {
    let timestamp: TimeInterval
    let text: String
}

struct LyricsResult: Equatable, Codable {
    let plainLyrics: String?
    let syncedLyrics: [LyricLine]?

    var isEmpty: Bool { plainLyrics == nil && syncedLyrics == nil }
}

actor LyricsProvider {
    private var cache: [String: LyricsResult] = [:]
    private var cacheAccessOrder: [String] = []
    private let cacheDir: URL
    private let onLyricsCached: (@Sendable (String, Int64) -> Void)?

    init(
        cacheDir: URL,
        onLyricsCached: (@Sendable (String, Int64) -> Void)? = nil
    ) {
        self.cacheDir = cacheDir
        self.onLyricsCached = onLyricsCached
    }

    func fetch(
        videoId: String, title: String, artist: String
    ) async -> LyricsResult? {
        let memKey = "\(artist)|\(title)"
        if let cached = cache[memKey] {
            touchAccessOrder(memKey)
            return cached
        }
        if let disk = loadFromDisk(videoId: videoId) {
            cache[memKey] = disk
            touchAccessOrder(memKey)
            return disk
        }

        log("Fetching lyrics: artist='\(artist)' title='\(title)'")
        let result: LyricsResult?
        if let exact = await exactMatch(title: title, artist: artist) {
            log("Exact match found")
            result = exact
        } else if let search = await searchMatch(title: title, artist: artist) {
            log("Search match found")
            result = search
        } else {
            log("No lyrics found")
            return nil
        }
        if let result {
            cache[memKey] = result
            saveToDisk(videoId: videoId, result: result)
        }
        return result
    }
}

// MARK: - Memory Cache Management

extension LyricsProvider {
    func trimCache(maxEntries: Int) {
        guard cache.count > maxEntries else { return }
        let toRemove = cacheAccessOrder.prefix(cache.count - maxEntries)
        for key in toRemove { cache.removeValue(forKey: key) }
        cacheAccessOrder.removeFirst(toRemove.count)
        log("Trimmed in-memory cache to \(cache.count) entries")
    }

    private func touchAccessOrder(_ key: String) {
        if let idx = cacheAccessOrder.firstIndex(of: key) {
            cacheAccessOrder.remove(at: idx)
        }
        cacheAccessOrder.append(key)
    }
}

// MARK: - Disk Cache

private extension LyricsProvider {
    func lyricsPath(for videoId: String) -> URL {
        cacheDir.appendingPathComponent("\(videoId).lyrics.json")
    }

    func loadFromDisk(videoId: String) -> LyricsResult? {
        let path = lyricsPath(for: videoId)
        guard let data = try? Data(contentsOf: path) else { return nil }
        return try? JSONDecoder().decode(LyricsResult.self, from: data)
    }

    func saveToDisk(videoId: String, result: LyricsResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        let path = lyricsPath(for: videoId)
        try? data.write(to: path)
        let size = Int64(data.count)
        onLyricsCached?(videoId, size)
        log("Saved lyrics to disk: \(videoId) (\(size) bytes)")
    }
}

// MARK: - API

private extension LyricsProvider {
    func exactMatch(title: String, artist: String) async -> LyricsResult? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title),
        ]
        return await fetchAndParse(components: components)
    }

    func searchMatch(title: String, artist: String) async -> LyricsResult? {
        let query = "\(cleanForSearch(artist)) \(cleanForSearch(title))"
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("YTBar/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let results = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = results.first else { return nil }
        return parseJSON(first)
    }

    func fetchAndParse(components: URLComponents) async -> LyricsResult? {
        guard let url = components.url else { return nil }
        var req = URLRequest(url: url)
        req.setValue("YTBar/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parseJSON(json)
    }

    func parseJSON(_ json: [String: Any]) -> LyricsResult? {
        let plain = json["plainLyrics"] as? String
        let synced = (json["syncedLyrics"] as? String).flatMap(parseLRC)
        guard plain != nil || synced != nil else { return nil }
        return LyricsResult(plainLyrics: plain, syncedLyrics: synced)
    }

    func cleanForSearch(_ text: String) -> String {
        var cleaned = text
        for suffix in [" - Topic", " (Official Audio)", " (Official Video)",
                       " (Lyric Video)", " (Audio)", " [Official Video]",
                       " (Official Music Video)"] {
            cleaned = cleaned.replacingOccurrences(of: suffix, with: "",
                                                    options: .caseInsensitive)
        }
        if let range = cleaned.range(of: #"\s*[\(\[](feat\.|ft\.).*?[\)\]]"#,
                                      options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    func parseLRC(_ raw: String) -> [LyricLine]? {
        var lines: [LyricLine] = []
        for line in raw.components(separatedBy: "\n") {
            guard line.range(of: #"^\[(\d+):(\d+\.\d+)\]"#, options: .regularExpression) != nil else {
                continue
            }
            let scanner = Scanner(string: line)
            guard scanner.scanString("[") != nil,
                  let minutes = scanner.scanDouble(),
                  scanner.scanString(":") != nil,
                  let seconds = scanner.scanDouble(),
                  scanner.scanString("]") != nil else { continue }
            let text = String(line[scanner.currentIndex...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            lines.append(LyricLine(timestamp: minutes * 60 + seconds, text: text))
        }
        return lines.isEmpty ? nil : lines
    }

    func log(_ msg: String) {
        DebugLogger.shared.log("[LYRICS] \(msg)")
    }
}
