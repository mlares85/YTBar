import Foundation

enum YTDataParser {
    static func parsePlaylists(from json: Any) -> [Playlist] {
        let root = json as? [String: Any] ?? [:]
        let items = root["items"] as? [[String: Any]] ?? []
        return items.compactMap { parsePlaylist(from: $0) }
    }

    static func parsePlaylistItems(from json: Any) -> [Track] {
        parsePlaylistPage(from: json).tracks
    }

    static func parsePlaylistPage(
        from json: Any
    ) -> (tracks: [Track], nextPageToken: String?) {
        let root = json as? [String: Any] ?? [:]
        let items = root["items"] as? [[String: Any]] ?? []
        let tracks = items.compactMap { parseTrack(from: $0) }
        let token = root["nextPageToken"] as? String
        return (tracks, token)
    }
}

// MARK: - Playlist Parsing

private extension YTDataParser {
    static func parsePlaylist(from item: [String: Any]) -> Playlist? {
        guard let id = item["id"] as? String else { return nil }
        let snippet = item["snippet"] as? [String: Any] ?? [:]
        let details = item["contentDetails"] as? [String: Any] ?? [:]
        let title = snippet["title"] as? String ?? ""
        let count = details["itemCount"] as? Int ?? 0
        let thumb = extractThumbnail(from: snippet)
        return Playlist(
            id: id, title: title,
            trackCount: count, thumbnailURL: thumb
        )
    }
}

// MARK: - Track Parsing

private extension YTDataParser {
    static func parseTrack(from item: [String: Any]) -> Track? {
        let snippet = item["snippet"] as? [String: Any] ?? [:]
        let details = item["contentDetails"] as? [String: Any] ?? [:]
        let videoId = details["videoId"] as? String
            ?? extractVideoId(from: snippet)
        guard !videoId.isEmpty else { return nil }
        let title = snippet["title"] as? String ?? ""
        let artist = snippet["videoOwnerChannelTitle"] as? String ?? ""
        let thumb = extractThumbnail(from: snippet)
        return Track(
            id: videoId, title: title, artist: artist,
            album: nil, durationSeconds: 0,
            thumbnailURL: thumb
        )
    }

    static func extractVideoId(from snippet: [String: Any]) -> String {
        let res = snippet["resourceId"] as? [String: Any] ?? [:]
        return res["videoId"] as? String ?? ""
    }

    static func extractThumbnail(from snippet: [String: Any]) -> URL? {
        let thumbs = snippet["thumbnails"] as? [String: Any] ?? [:]
        let medium = thumbs["medium"] as? [String: Any]
            ?? thumbs["default"] as? [String: Any] ?? [:]
        guard let url = medium["url"] as? String else { return nil }
        return URL(string: url)
    }
}
