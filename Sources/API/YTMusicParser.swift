import Foundation

enum YTMusicParser {
    static func parseSearchTracks(from json: Any) -> [Track] {
        let shelves = extractMusicShelves(from: extractSearchSections(json))
        return shelves.flatMap { extractTracks(from: $0) }
    }

    static func parseSearchPlaylists(from json: Any) -> [Playlist] {
        let shelves = extractMusicShelves(from: extractSearchSections(json))
        return shelves.flatMap { extractPlaylists(from: $0) }
    }

    static func parseLibraryPlaylists(from json: Any) -> [Playlist] {
        let sections = extractBrowseSections(json)
        return sections.flatMap { extractGridPlaylists(from: $0) }
    }

    static func parsePlaylistTracks(from json: Any) -> [Track] {
        let sections = extractBrowseSections(json)
        let shelves = extractMusicShelves(from: sections)
        return shelves.flatMap { extractTracks(from: $0) }
    }

    static func parseRadioMix(from json: Any) -> [Track] {
        let root = json as? [String: Any] ?? [:]
        let contents = dig(root, "contents", "singleColumnMusicWatchNextResultsRenderer", "tabbedRenderer", "watchNextTabbedResultsRenderer")
        let tabs = contents["tabs"] as? [[String: Any]] ?? []
        guard let tab = tabs.first else { return [] }
        let panel = dig(tab, "tabRenderer", "content", "musicQueueRenderer", "content", "playlistPanelRenderer")
        let items = panel["contents"] as? [[String: Any]] ?? []
        return items.compactMap { parseRadioTrack(from: $0) }
    }

    static func parseRadioTrack(from item: [String: Any]) -> Track? {
        let r = item["playlistPanelVideoRenderer"] as? [String: Any] ?? [:]
        guard let vid = r["videoId"] as? String, !vid.isEmpty else { return nil }
        let title = extractRunText(from: r["title"])
        let artist = extractRunText(from: r["longBylineText"])
        let durText = extractRunText(from: r["lengthText"])
        let thumb = dig(r, "thumbnail", "thumbnails")
        let thumbs = r["thumbnail"] as? [String: Any] ?? [:]
        let tList = thumbs["thumbnails"] as? [[String: Any]] ?? []
        let thumbURL = (tList.first?["url"] as? String).flatMap { URL(string: $0) }
        return Track(id: vid, title: title, artist: artist, album: nil, durationSeconds: durationToSeconds(durText), thumbnailURL: thumbURL)
    }
}

// MARK: - Section Extraction
extension YTMusicParser {
    static func extractSearchSections(_ json: Any) -> [[String: Any]] {
        let root = dig(json, "contents", "tabbedSearchResultsRenderer")
        return extractTabSections(from: root)
    }

    static func extractBrowseSections(_ json: Any) -> [[String: Any]] {
        let root = dig(json, "contents", "singleColumnBrowseResultsRenderer")
        return extractTabSections(from: root)
    }

    private static func extractTabSections(from renderer: [String: Any]) -> [[String: Any]] {
        let tab = (renderer["tabs"] as? [[String: Any]])?.first?["tabRenderer"] as? [String: Any] ?? [:]
        return dig(tab, "content", "sectionListRenderer")["contents"] as? [[String: Any]] ?? []
    }

    static func dig(_ json: Any, _ keys: String...) -> [String: Any] {
        keys.reduce(json as? [String: Any] ?? [:]) { ($0[($1)] as? [String: Any]) ?? [:] }
    }
}

// MARK: - Shelf Extraction
extension YTMusicParser {
    static func extractMusicShelves(from sections: [[String: Any]]) -> [[[String: Any]]] {
        sections.compactMap { section in
            let shelf = section["musicShelfRenderer"] as? [String: Any]
            return shelf?["contents"] as? [[String: Any]]
        }
    }
}

// MARK: - Track Parsing

extension YTMusicParser {
    static func extractTracks(from items: [[String: Any]]) -> [Track] {
        items.compactMap { extractTrack(from: $0) }
    }

    static func extractTrack(from item: [String: Any]) -> Track? {
        guard let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
        guard let videoId = extractVideoId(from: renderer) else { return nil }
        let columns = flexColumnTexts(from: renderer)
        guard columns.count >= 2 else { return nil }
        return Track(
            id: videoId,
            title: columns[0],
            artist: columns[1],
            album: columns.count >= 3 ? columns[2] : nil,
            durationSeconds: parseDuration(from: renderer),
            thumbnailURL: extractThumbnailURL(from: renderer)
        )
    }
}

// MARK: - Playlist Parsing

extension YTMusicParser {
    static func extractPlaylists(from items: [[String: Any]]) -> [Playlist] {
        items.compactMap { extractPlaylist(from: $0) }
    }

    static func extractPlaylist(from item: [String: Any]) -> Playlist? {
        guard let renderer = item["musicResponsiveListItemRenderer"] as? [String: Any] else { return nil }
        guard let browseId = extractBrowseId(from: renderer) else { return nil }
        let columns = flexColumnTexts(from: renderer)
        guard !columns.isEmpty else { return nil }
        return Playlist(
            id: browseId,
            title: columns[0],
            trackCount: parseTrackCount(from: columns),
            thumbnailURL: extractThumbnailURL(from: renderer)
        )
    }

    static func extractGridPlaylists(from section: [String: Any]) -> [Playlist] {
        let grid = section["gridRenderer"] as? [String: Any] ?? [:]
        let items = grid["items"] as? [[String: Any]] ?? []
        return items.compactMap { extractGridPlaylist(from: $0) }
    }

    static func extractGridPlaylist(from item: [String: Any]) -> Playlist? {
        guard let renderer = item["musicTwoRowItemRenderer"] as? [String: Any] else { return nil }
        let browseId = extractGridBrowseId(from: renderer)
        let title = extractRunText(from: renderer["title"])
        guard !title.isEmpty else { return nil }
        return Playlist(
            id: stripVLPrefix(browseId),
            title: title,
            trackCount: parseTrackCount(from: renderer),
            thumbnailURL: extractGridThumbnailURL(from: renderer)
        )
    }
}

// MARK: - Field Helpers

extension YTMusicParser {
    static func extractVideoId(from renderer: [String: Any]) -> String? {
        let data = renderer["playlistItemData"] as? [String: Any]
        return data?["videoId"] as? String
    }

    static func extractBrowseId(from renderer: [String: Any]) -> String? {
        let nav = renderer["navigationEndpoint"] as? [String: Any]
        let browse = nav?["browseEndpoint"] as? [String: Any]
        return browse?["browseId"] as? String
    }

    static func flexColumnTexts(from renderer: [String: Any]) -> [String] {
        let columns = renderer["flexColumns"] as? [[String: Any]] ?? []
        return columns.compactMap { col in
            let flex = col["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any]
            return extractRunText(from: flex?["text"])
        }
    }

    static func parseDuration(from renderer: [String: Any]) -> Int {
        // Try fixedColumns first (standard location)
        let fixed = renderer["fixedColumns"] as? [[String: Any]] ?? []
        if let col = fixed.first {
            let flex = col["musicResponsiveListItemFixedColumnRenderer"] as? [String: Any]
            let text = extractRunText(from: flex?["text"])
            let secs = durationToSeconds(text)
            if secs > 0 { return secs }
        }
        // Fallback: check last flex column for duration-like text
        let columns = flexColumnTexts(from: renderer)
        for col in columns.reversed() {
            let secs = durationToSeconds(col)
            if secs > 0 { return secs }
        }
        return 0
    }

    static func extractThumbnailURL(from renderer: [String: Any]) -> URL? {
        let thumb = renderer["thumbnail"] as? [String: Any]
        let musicThumb = thumb?["musicThumbnailRenderer"] as? [String: Any]
        let container = musicThumb?["thumbnail"] as? [String: Any]
        let thumbs = container?["thumbnails"] as? [[String: Any]] ?? []
        guard let urlStr = thumbs.first?["url"] as? String else { return nil }
        return URL(string: urlStr)
    }

    static func extractRunText(from textObj: Any?) -> String {
        let text = textObj as? [String: Any]
        let runs = text?["runs"] as? [[String: Any]] ?? []
        return runs.compactMap { $0["text"] as? String }.joined()
    }

    static func durationToSeconds(_ text: String) -> Int {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    static func parseTrackCount(from columns: [String]) -> Int {
        for col in columns {
            let nums = col.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let count = Int(nums), count > 0 { return count }
        }
        return 0
    }

    private static func parseTrackCount(from renderer: [String: Any]) -> Int {
        let text = extractRunText(from: renderer["subtitle"])
        let nums = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(nums) ?? 0
    }

    private static func extractGridBrowseId(from renderer: [String: Any]) -> String {
        let browse = dig(renderer, "navigationEndpoint", "browseEndpoint")
        return browse["browseId"] as? String ?? ""
    }

    private static func extractGridThumbnailURL(from renderer: [String: Any]) -> URL? {
        let container = dig(renderer, "thumbnailRenderer", "musicThumbnailRenderer", "thumbnail")
        let thumbs = container["thumbnails"] as? [[String: Any]] ?? []
        return (thumbs.first?["url"] as? String).flatMap { URL(string: $0) }
    }

    static func stripVLPrefix(_ id: String) -> String {
        id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
    }
}
