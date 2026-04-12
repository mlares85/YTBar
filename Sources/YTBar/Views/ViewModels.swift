import SwiftUI
import Combine
import AppKit

enum AudioQuality: String, CaseIterable, Codable {
    case low = "Low"
    case normal = "Normal"
    case high = "High"

    /// yt-dlp format selector for streaming. Same itag strategy as DownloadQuality.
    var ytdlpFormat: String {
        switch self {
        case .low:
            return "139/bestaudio[ext=m4a][abr<=64]/worstaudio[ext=m4a]/worstaudio"
        case .normal:
            return "140/bestaudio[ext=m4a][abr<=128]/bestaudio[abr<=128]/bestaudio"
        case .high:
            return "141/bestaudio[ext=m4a]/bestaudio"
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var currentTrack: Track?
    @Published var playerState: PlayerState = .idle
    @Published var progress: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.7

    @Published var searchQuery = ""
    @Published var searchResults: [Track] = []
    @Published var isSearching = false

    @Published var playlists: [Playlist] = []
    @Published var isLoadingLibrary = false
    @Published var isAuthenticated = false

    @Published var audioQuality: AudioQuality = .normal
    @Published var previousRestartEnabled: Bool = true
    @Published var previousRestartThreshold: Double = 5.0
    @Published var autoHideBrowsePanel: Bool = true
    @Published var browsePanelExpanded: Bool = false
    @Published var autoExtendQueueEnabled: Bool = true
    @Published var debugLoggingEnabled: Bool = false
    @Published var autoExtendStartIndex: Int?
    @Published var isAppendingToPlaylist: Bool = false
    @Published var deviceCode: String?
    @Published var configClientID: String = ""
    @Published var configClientSecret: String = ""
    var onSaveConfig: ((String, String) -> Void)?
    @Published var queueTracks: [Track] = []
    @Published var queueIndex: Int = 0
    @Published var showQueue = false
    @Published var cacheConfig: CacheConfig = .default
    @Published var cacheUsageMB: Int = 0
    @Published var windowOpacity: Double = 1.0
    @Published var showLyrics = false
    @Published var currentLyrics: LyricsResult?
    @Published var lyricsLoading = false
    @Published var selectedTab = 0
    @Published var isLiked = false
    @Published var isTogglingLike = false
    @Published var queueSourcePlaylistId: String?
    @Published var queueSourcePlaylistTitle: String?
    @Published var isSavingPlaylist = false
    @Published var activeToast: Toast?
    private var toastDismissTask: Task<Void, Never>?

    // Liked Music cache — persists across navigations within the same app
    // run. 30-minute TTL: navigating back after 30 minutes triggers a
    // silent background re-fetch while the stale cache is still shown.
    @Published var likedTracks: [Track] = []
    @Published var likedNextPageToken: String?
    @Published var isLoadingLiked: Bool = false
    @Published var isLoadingMoreLiked: Bool = false
    private var likedLastFetchedAt: Date?
    private static let likedCacheTTL: TimeInterval = 30 * 60

    // Service callbacks — set by AppDelegate
    var onSearch: ((String) async throws -> [Track])?
    var onPlayTrack: ((Track) async -> Void)?
    var onNext: (() async -> Void)?
    var onPrevious: (() async -> Void)?
    var onSeek: ((Double) -> Void)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onSetVolume: ((Float) -> Void)?
    var onQueueTracks: (([Track], Int) -> Void)?
    var onAddToQueue: ((Track) -> Void)?
    var onStartRadio: ((Track) async -> Void)?
    var onSignIn: (() async throws -> String?)?
    var onPollForToken: ((String) async throws -> Void)?
    var onSignOut: (() -> Void)?
    @Published var isSigningIn = false
    @Published var signInError: String?
    var onFetchLibrary: (() async throws -> [Playlist])?
    var onFetchPlaylistTracks: ((String) async throws -> [Track])?
    var onFetchPlaylistPage: ((String, String?) async throws -> ([Track], String?))?
    var onSaveCacheConfig: ((CacheConfig) -> Void)?
    var onClearCache: (() -> Void)?
    var onFetchCacheUsage: (() -> Int)?
    var onKeepOffline: (([String]) -> Void)?
    var onCachedCount: (([String]) -> Int)?
    var onSetWindowOpacity: ((Double) -> Void)?
    var onSetAudioQuality: ((AudioQuality) -> Void)?
    var onSetPreviousRestartEnabled: ((Bool) -> Void)?
    var onSetPreviousRestartThreshold: ((Double) -> Void)?
    var onSetAutoHideBrowsePanel: ((Bool) -> Void)?
    var onSetAutoExtendQueueEnabled: ((Bool) -> Void)?
    var onSetDebugLogging: ((Bool) -> Void)?
    var onAppendTracksToPlaylist: ((String, [Track]) async throws -> Void)?
    var onQueueReorder: ((IndexSet, Int) -> Void)?
    var onFetchLyrics: ((String, String, String) async -> LyricsResult?)?
    var onRateVideo: ((String, String) async throws -> Void)?
    var onGetRating: ((String) async throws -> String)?
    var onSaveQueueAsPlaylist: ((String, [Track]) async throws -> String)?

    func toggleLyrics() {
        showLyrics.toggle()
        if showLyrics {
            browsePanelExpanded = true
            if currentLyrics == nil {
                fetchLyricsForCurrentTrack()
            }
        }
    }

    /// Whether the browse/tab-content panel should be shown. The panel is
    /// visible when `browsePanelExpanded` is set, or always when there's no
    /// active track (so the user has something to interact with).
    ///
    /// The `autoHideBrowsePanel` setting controls the *initial* value of
    /// `browsePanelExpanded` each time the popover opens — it no longer
    /// force-overrides this computed property, so click-to-collapse works
    /// regardless of the setting.
    var isBrowsePanelVisible: Bool {
        browsePanelExpanded || !hasActiveTrack
    }

    /// Called from the nav/tab buttons.
    /// - If the lyrics overlay is up, dismiss it and switch to the clicked
    ///   tab (keeps the existing "click a tab to dismiss lyrics" behavior).
    /// - Else if the clicked tab is already the active one and the panel
    ///   is expanded (and there's an active track), collapse the panel.
    /// - Otherwise, select the tab and expand the panel.
    func selectTab(_ index: Int) {
        let shouldCollapse =
            !showLyrics
            && browsePanelExpanded
            && selectedTab == index
            && hasActiveTrack
        showLyrics = false
        if shouldCollapse {
            browsePanelExpanded = false
        } else {
            selectedTab = index
            browsePanelExpanded = true
        }
    }

    func fetchLyricsForCurrentTrack() {
        guard let track = currentTrack else { return }
        lyricsLoading = true
        Task {
            let result = await onFetchLyrics?(track.id, track.title, track.artist)
            currentLyrics = result
            lyricsLoading = false
        }
    }

    func clearLyrics() {
        currentLyrics = nil
    }

    func toggleLike() {
        guard let track = currentTrack, !isTogglingLike else { return }
        isTogglingLike = true
        let newRating = isLiked ? "none" : "like"
        Task {
            defer { isTogglingLike = false }
            do {
                try await onRateVideo?(track.id, newRating)
                isLiked = newRating == "like"
            } catch {
                debugLog("Rate error: \(error)")
                showToast(.error, message: "Failed to update rating")
            }
        }
    }

    func saveQueueAsPlaylist(name: String) {
        guard !queueTracks.isEmpty, !isSavingPlaylist else { return }
        isSavingPlaylist = true
        let tracks = queueTracks
        Task {
            defer { isSavingPlaylist = false }
            do {
                if let newId = try await onSaveQueueAsPlaylist?(name, tracks) {
                    // Queue is now backed by the newly created playlist —
                    // remember its ID so the "append auto-extended" button
                    // can add subsequent radio tracks to it.
                    queueSourcePlaylistId = newId
                }
                queueSourcePlaylistTitle = name
                await loadLibrary()
                showToast(.success, message: "Playlist saved")
            } catch {
                debugLog("Save playlist error: \(error)")
                showToast(.error, message: "Failed to save playlist")
            }
        }
    }

    /// True when the browse view should show the "append auto-extended
    /// tracks to the source playlist" button.
    var canAppendAutoExtendedToPlaylist: Bool {
        guard let id = queueSourcePlaylistId, id != "LM" else { return false }
        guard let divider = autoExtendStartIndex else { return false }
        guard divider < queueTracks.count else { return false }
        return isAuthenticated && !isAppendingToPlaylist
    }

    /// Tracks that were appended by the auto-extend workflow (i.e. sit
    /// after the divider). Empty when there's no divider.
    var autoExtendedTracks: [Track] {
        guard let divider = autoExtendStartIndex,
              divider < queueTracks.count else {
            return []
        }
        return Array(queueTracks.dropFirst(divider))
    }

    func moveQueueItems(from source: IndexSet, to destination: Int) {
        onQueueReorder?(source, destination)
    }

    func appendAutoExtendedToSourcePlaylist() {
        guard canAppendAutoExtendedToPlaylist,
              let playlistId = queueSourcePlaylistId else { return }
        let tracksToAppend = autoExtendedTracks
        guard !tracksToAppend.isEmpty else { return }
        isAppendingToPlaylist = true
        Task {
            defer { isAppendingToPlaylist = false }
            do {
                try await onAppendTracksToPlaylist?(playlistId, tracksToAppend)
                showToast(.success, message: "Tracks added to playlist")
            } catch {
                debugLog("Append to playlist error: \(error)")
                showToast(.error, message: "Failed to add tracks to playlist")
            }
        }
    }

    var queueIsFromExistingPlaylist: Bool {
        queueSourcePlaylistId != nil
    }

    func fetchRating(for videoId: String) {
        Task {
            let rating = try? await onGetRating?(videoId)
            isLiked = rating == "like"
        }
    }

    func setWindowOpacity(_ value: Double) {
        windowOpacity = value
        onSetWindowOpacity?(value)
    }

    var progressFormatted: String { formatTime(progress) }
    var durationFormatted: String { formatTime(duration) }

    var hasActiveTrack: Bool {
        currentTrack != nil && playerState.isActive
    }

    private var searchTask: Task<Void, Never>?

    func search(_ query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task { await performSearch(query) }
    }

    func play(_ track: Track) {
        Task { await onPlayTrack?(track) }
    }

    func playFromList(
        _ track: Track,
        in tracks: [Track],
        playlistId: String? = nil,
        playlistTitle: String? = nil
    ) {
        queueSourcePlaylistId = playlistId
        queueSourcePlaylistTitle = playlistTitle
        let idx = tracks.firstIndex(of: track) ?? 0
        onQueueTracks?(tracks, idx)
        Task { await onPlayTrack?(track) }
    }

    func playWithRadio(_ track: Track) {
        queueSourcePlaylistId = nil
        queueSourcePlaylistTitle = nil
        onQueueTracks?([track], 0)
        Task { await onPlayTrack?(track) }
    }

    func addToQueue(_ track: Track) {
        onAddToQueue?(track)
    }

    func startRadio(from track: Track) {
        queueSourcePlaylistId = nil
        queueSourcePlaylistTitle = nil
        let isCurrentlyPlaying = currentTrack == track && playerState.isActive
        if !isCurrentlyPlaying {
            onQueueTracks?([track], 0)
        }
        Task {
            if !isCurrentlyPlaying {
                await onPlayTrack?(track)
            }
            await onStartRadio?(track)
        }
    }

    func playFromQueue(at index: Int) {
        guard index < queueTracks.count else { return }
        let track = queueTracks[index]
        onQueueTracks?(queueTracks, index)
        Task { await onPlayTrack?(track) }
    }

    func toggleQueue() { showQueue.toggle() }

    func pause() {
        onPause?()
        playerState = .paused
    }

    func resume() {
        onResume?()
        playerState = .playing
    }

    func togglePlayPause() {
        playerState == .playing ? pause() : resume()
    }

    func next() {
        Task { await onNext?() }
    }

    func previous() {
        Task { await onPrevious?() }
    }

    func seek(to position: Double) {
        progress = position
        onSeek?(position)
    }

    func setVolume(_ value: Double) {
        volume = value
        onSetVolume?(Float(value))
    }

    func fetchLibrary() {
        Task { await loadLibrary() }
    }

    // MARK: - Liked Music cache

    /// True if the liked-music cache is older than the TTL or has never
    /// been fetched. The view calls `loadLikedIfNeeded()` on appear; if
    /// the cache is still fresh the call is a no-op.
    var likedCacheIsStale: Bool {
        guard let at = likedLastFetchedAt else { return true }
        return Date().timeIntervalSince(at) > Self.likedCacheTTL
    }

    /// Called from `LikedMusicView.onAppear`. Fetches only when the cache
    /// is stale; otherwise leaves the current `likedTracks` in place.
    func loadLikedIfNeeded() {
        guard likedCacheIsStale else { return }
        performLikedFetch()
    }

    /// Called from the refresh button. Always fetches, bypassing the TTL.
    func refreshLiked() {
        performLikedFetch()
    }

    private func performLikedFetch() {
        guard !isLoadingLiked else { return }
        isLoadingLiked = true
        Task {
            defer { isLoadingLiked = false }
            do {
                guard let page = try await onFetchPlaylistPage?("LM", nil) else {
                    return
                }
                likedTracks = page.0
                likedNextPageToken = page.1
                likedLastFetchedAt = Date()
            } catch {
                debugLog("Liked fetch error: \(error)")
                showToast(.error, message: "Failed to load liked music")
            }
        }
    }

    func loadMoreLiked() {
        guard !isLoadingMoreLiked,
              let token = likedNextPageToken,
              !token.isEmpty else { return }
        isLoadingMoreLiked = true
        Task {
            defer { isLoadingMoreLiked = false }
            do {
                guard let page = try await onFetchPlaylistPage?("LM", token) else {
                    return
                }
                likedTracks.append(contentsOf: page.0)
                likedNextPageToken = page.1
            } catch {
                debugLog("Liked load-more error: \(error)")
                showToast(.error, message: "Failed to load more tracks")
            }
        }
    }

    func signIn() {
        debugLog("signIn() called")
        Task { await performSignIn() }
    }

    func debugLog(_ msg: String) {
        DebugLogger.shared.log("[VM] \(msg)")
    }

    func signOut() {
        onSignOut?()
        isAuthenticated = false
        playlists = []
    }

    func checkForUpdates() {}

    func showToast(_ style: ToastStyle, message: String, detail: String? = nil) {
        toastDismissTask?.cancel()
        activeToast = Toast(id: UUID(), style: style, message: message, detail: detail)
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            dismissToast()
        }
    }

    func dismissToast() {
        activeToast = nil
    }

    func saveCacheConfig() {
        onSaveCacheConfig?(cacheConfig)
    }

    func clearCache() {
        onClearCache?()
        cacheUsageMB = 0
    }

    func refreshCacheUsage() {
        cacheUsageMB = onFetchCacheUsage?() ?? 0
    }

    func keepOffline(tracks: [Track]) {
        onKeepOffline?(tracks.map(\.id))
    }

    func cachedCount(tracks: [Track]) -> Int {
        onCachedCount?(tracks.map(\.id)) ?? 0
    }
}

// MARK: - Private

private extension AppViewModel {
    func performSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        debugLog("Searching: \(query)")
        do {
            let results = try await onSearch?(query)
            searchResults = results ?? []
            debugLog("Search got \(searchResults.count) tracks")
        } catch {
            debugLog("Search error: \(error)")
            searchResults = []
            showToast(.error, message: "Search failed")
        }
    }

    func loadLibrary() async {
        isLoadingLibrary = true
        defer { isLoadingLibrary = false }
        debugLog("Fetching library playlists...")
        do {
            playlists = try await onFetchLibrary?() ?? []
            debugLog("Got \(playlists.count) playlists")
        } catch {
            debugLog("Library fetch error: \(error)")
            playlists = []
        }
    }

    func performSignIn() async {
        isSigningIn = true
        signInError = nil
        debugLog("performSignIn called, onSignIn is \(onSignIn == nil ? "nil" : "set")")
        do {
            deviceCode = try await onSignIn?()
            debugLog("deviceCode: \(deviceCode ?? "nil")")
        } catch {
            signInError = error.localizedDescription
            debugLog("Sign-in error: \(error)")
            isSigningIn = false
            return
        }
        guard let code = deviceCode else {
            signInError = "No device code received"
            isSigningIn = false
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        await pollUntilAuthenticated(code: code)
    }

    func pollUntilAuthenticated(code: String) async {
        for i in 0..<60 {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            debugLog("Poll attempt \(i + 1)")
            do {
                try await onPollForToken?(code)
                debugLog("Poll succeeded — authenticated!")
                isAuthenticated = true
                isSigningIn = false
                deviceCode = nil
                return
            } catch {
                debugLog("Poll attempt \(i + 1) error: \(error)")
            }
        }
        isSigningIn = false
    }

    func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
