import Foundation

enum DownloadQuality: String, Codable, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// yt-dlp format selector. itag 139 ~48kbps, 140 ~128kbps, 141 ~256kbps (Premium).
    var ytdlpFormat: String {
        switch self {
        case .low:
            return "139/bestaudio[ext=m4a][abr<=64]/worstaudio[ext=m4a]/worstaudio"
        case .medium:
            return "140/bestaudio[ext=m4a][abr<=128]/bestaudio[abr<=128]/bestaudio"
        case .high:
            return "141/bestaudio[ext=m4a]/bestaudio"
        }
    }
}

struct CacheConfig: Codable {
    var maxSizeMB: Int
    var autoCacheThreshold: Int
    var isEnabled: Bool
    var downloadQuality: DownloadQuality = .high

    var maxSizeBytes: Int64 { Int64(maxSizeMB) * 1_048_576 }

    static let `default` = CacheConfig(
        maxSizeMB: 500,
        autoCacheThreshold: 3,
        isEnabled: true,
        downloadQuality: .high
    )

    static var filePath: String {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("YTBar")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("cache-config.json").path
    }

    static func load() -> CacheConfig {
        guard let data = FileManager.default.contents(
            atPath: filePath
        ) else { return .default }
        return (try? JSONDecoder().decode(
            CacheConfig.self, from: data
        )) ?? .default
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: URL(fileURLWithPath: Self.filePath))
    }
}
