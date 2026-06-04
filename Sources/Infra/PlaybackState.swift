import Foundation

struct PlaybackState: Codable {
    var queue: [Track]
    var currentIndex: Int
    var progressSeconds: Double
    var repeatMode: RepeatMode
    var isShuffled: Bool
    var queueSourcePlaylistId: String?
    var queueSourcePlaylistTitle: String?
    var autoExtendStartIndex: Int?

    static var filePath: String {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("YTBar")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent(
            "playback-state.json"
        ).path
    }

    static func load() -> PlaybackState? {
        guard let data = FileManager.default.contents(
            atPath: filePath
        ) else { return nil }
        return try? JSONDecoder().decode(
            PlaybackState.self, from: data
        )
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(
            to: URL(fileURLWithPath: Self.filePath),
            options: .atomic
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(atPath: filePath)
    }
}

extension PlaybackState {
    enum CodingKeys: String, CodingKey {
        case queue, currentIndex, progressSeconds, repeatMode
        case isShuffled, queueSourcePlaylistId
        case queueSourcePlaylistTitle, autoExtendStartIndex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        queue = (try? c.decode([Track].self, forKey: .queue)) ?? []
        currentIndex = (try? c.decode(Int.self, forKey: .currentIndex)) ?? 0
        progressSeconds = (try? c.decode(Double.self, forKey: .progressSeconds)) ?? 0
        repeatMode = (try? c.decode(RepeatMode.self, forKey: .repeatMode)) ?? .off
        isShuffled = (try? c.decode(Bool.self, forKey: .isShuffled)) ?? false
        queueSourcePlaylistId = try? c.decode(String.self, forKey: .queueSourcePlaylistId)
        queueSourcePlaylistTitle = try? c.decode(String.self, forKey: .queueSourcePlaylistTitle)
        autoExtendStartIndex = try? c.decode(Int.self, forKey: .autoExtendStartIndex)
    }
}
