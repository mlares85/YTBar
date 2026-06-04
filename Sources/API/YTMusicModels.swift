import Foundation

struct Track: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let artist: String
    let album: String?
    let durationSeconds: Int
    let thumbnailURL: URL?

    var durationFormatted: String {
        let m = durationSeconds / 60
        let s = durationSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct Playlist: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let trackCount: Int
    let thumbnailURL: URL?
}

struct SearchResult: Equatable {
    let tracks: [Track]
    let playlists: [Playlist]
}

enum RepeatMode: String, CaseIterable, Codable {
    case off
    case all
    case one
}

enum PlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case error(String)

    var isActive: Bool {
        switch self {
        case .playing, .paused, .loading: return true
        default: return false
        }
    }
}

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt }
}
