import Foundation

struct CachedTrackInfo: Codable {
    let videoId: String
    var playCount: Int
    var lastPlayedAt: Date
    var fileSize: Int64
    var isCached: Bool
    var lyricsFileSize: Int64

    init(
        videoId: String, playCount: Int,
        lastPlayedAt: Date, fileSize: Int64,
        isCached: Bool, lyricsFileSize: Int64 = 0
    ) {
        self.videoId = videoId
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.fileSize = fileSize
        self.isCached = isCached
        self.lyricsFileSize = lyricsFileSize
    }
}

final class CacheMetadata {
    private var entries: [String: CachedTrackInfo]

    init(entries: [String: CachedTrackInfo] = [:]) {
        self.entries = entries
    }

    func recordPlay(videoId: String) -> Int {
        var entry = entries[videoId] ?? CachedTrackInfo(
            videoId: videoId, playCount: 0,
            lastPlayedAt: Date(), fileSize: 0, isCached: false
        )
        entry.playCount += 1
        entry.lastPlayedAt = Date()
        entries[videoId] = entry
        return entry.playCount
    }

    func markCached(videoId: String, fileSize: Int64) {
        entries[videoId]?.isCached = true
        entries[videoId]?.fileSize = fileSize
    }

    func markEvicted(videoId: String) {
        entries[videoId]?.isCached = false
        entries[videoId]?.fileSize = 0
        entries[videoId]?.lyricsFileSize = 0
    }

    func markLyricsCached(videoId: String, fileSize: Int64) {
        if entries[videoId] == nil {
            entries[videoId] = CachedTrackInfo(
                videoId: videoId, playCount: 0,
                lastPlayedAt: Date(), fileSize: 0,
                isCached: false, lyricsFileSize: fileSize
            )
        } else {
            entries[videoId]?.lyricsFileSize = fileSize
        }
    }

    func info(for videoId: String) -> CachedTrackInfo? {
        entries[videoId]
    }

    func totalCacheSize() -> Int64 {
        entries.values.reduce(0) { total, entry in
            let audio = entry.isCached ? entry.fileSize : 0
            return total + audio + entry.lyricsFileSize
        }
    }

    func evictionCandidates() -> [CachedTrackInfo] {
        entries.values
            .filter(\.isCached)
            .sorted { $0.lastPlayedAt < $1.lastPlayedAt }
    }
}

// MARK: - Persistence

extension CacheMetadata {
    static var filePath: String {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("YTBar")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent(
            "cache-metadata.json"
        ).path
    }

    static func load() -> CacheMetadata {
        guard let data = FileManager.default.contents(
            atPath: filePath
        ) else { return CacheMetadata() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let dict = try? decoder.decode(
            [String: CachedTrackInfo].self, from: data
        ) else { return CacheMetadata() }
        return CacheMetadata(entries: dict)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: URL(fileURLWithPath: Self.filePath))
    }
}
