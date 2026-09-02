import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var viewModel: AppViewModel!
    private var auth: GoogleAuth!
    private var musicClient: YTMusicClient!
    private var audioPlayer: AudioPlayer!
    private var queueManager: QueueManager!
    private var streamExtractor: StreamExtractor!
    private var dependencyManager: DependencyManager!
    private var nowPlayingBridge: NowPlayingBridge!
    private var cacheMetadata: CacheMetadata!
    private var cacheConfig: CacheConfig!
    private var audioFileCache: AudioFileCache!
    private var uiConfig: UIConfig!
    private var lyricsProvider: LyricsProvider!
    private var urlCache: [String: (URL, Date)] = [:]
    private var playGeneration: UInt64 = 0
    private var pendingTrack: Track?
    private var isAutoExtendingQueue: Bool = false
    /// Minimum number of upcoming tracks that must remain before the
    /// radio-extend workflow triggers. Pre-loading 5-deep gives time for
    /// the radio fetch and URL prefetching so playback doesn't gap.
    private static let autoExtendLookahead: Int = 5

    nonisolated override init() { super.init() }

    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupServices()
        setupMenuBar()
        setupNowPlayingBridge()
        bindViewModel()
        syncAuthState()
        installDependencies()
        restoreSessionIfEnabled()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveSessionIfEnabled()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool { false }
}

// MARK: - Setup

private extension AppDelegate {
    func setupServices() {
        auth = GoogleAuth()
        dependencyManager = DependencyManager()
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        let musicSession = URLSession(configuration: config)
        let authRef = auth!
        musicClient = YTMusicClient(
            httpClient: musicSession,
            tokenProvider: { authRef.cachedAccessToken },
            onTokenExpired: { @Sendable in
                try? await authRef.refreshToken()
            }
        )
        streamExtractor = StreamExtractor(
            shell: ProcessShellExecutor(),
            ytdlpPath: dependencyManager.ytdlpPath
        )
        audioPlayer = AudioPlayer()
        queueManager = QueueManager()
        nowPlayingBridge = NowPlayingBridge()
        cacheConfig = CacheConfig.load()
        uiConfig = UIConfig.load()
        cacheMetadata = CacheMetadata.load()
        audioFileCache = AudioFileCache(
            metadata: cacheMetadata,
            shell: ProcessShellExecutor(),
            ytdlpPath: dependencyManager.ytdlpPath,
            maxSizeBytes: cacheConfig.maxSizeBytes,
            downloadQuality: cacheConfig.downloadQuality
        )
        let metadataRef = cacheMetadata!
        lyricsProvider = LyricsProvider(
            cacheDir: audioFileCache.cacheDirURL,
            onLyricsCached: { videoId, size in
                metadataRef.markLyricsCached(videoId: videoId, fileSize: size)
                metadataRef.save()
            }
        )
        viewModel = AppViewModel()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )
        configureStatusButton()
        popover = NSPopover()
        popover.contentSize = NSSize(
            width: Self.popoverWidth,
            height: Self.expandedPopoverHeight
        )
        popover.behavior = .transient
        popover.delegate = self
        let hostView = ContentView()
            .environmentObject(viewModel)
        popover.contentViewController = NSHostingController(
            rootView: hostView
        )
    }

    func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "YTBar"
        )
        button.action = #selector(handleClick)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func buildRightClickMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "About YTBar",
                     action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit YTBar",
                     action: #selector(quitApp),
                     keyEquivalent: "q")
        return menu
    }

    func syncAuthState() {
        auth.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] val in
                self?.viewModel.isAuthenticated = val
                _ = val  // auth.logout() handles clearing
            }
            .store(in: &cancellables)
    }

    func installDependencies() {
        Task {
            if uiConfig.autoUpdateYtdlp {
                try? await dependencyManager.ensureUpToDate()
            } else {
                try? await dependencyManager.ensureInstalled()
            }
            viewModel.ytdlpOutdated = dependencyManager.isOutdated
        }
    }
}

// MARK: - Popover

extension AppDelegate {
    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = buildRightClickMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            togglePopover()
        }
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            viewModel.browsePanelExpanded = !viewModel.autoHideBrowsePanel
            updatePopoverSizeIfNeeded()
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            applyWindowOpacity(viewModel.windowOpacity)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { false }

    func popoverWillShow(_ notification: Notification) {
        // Each time the popover opens, restore the browse panel to the
        // state dictated by the auto-hide setting. This keeps
        // click-to-collapse as a session-scoped override that doesn't leak
        // across open/close cycles.
        guard let vm = viewModel else { return }
        vm.browsePanelExpanded = !vm.autoHideBrowsePanel
    }

    func popoverDidClose(_ notification: Notification) {
        // Free search results memory when the popover is dismissed.
        viewModel.searchResults = []
        // When auto-hide is on, every time the user dismisses the popover we
        // reset the browse panel so the next open starts with it hidden.
        guard viewModel?.autoHideBrowsePanel == true else { return }
        viewModel.browsePanelExpanded = false
        viewModel.showLyrics = false
    }
}

// MARK: - Now Playing Bridge

private extension AppDelegate {
    func setupNowPlayingBridge() {
        nowPlayingBridge.onPlay = { [weak self] in Task { @MainActor in self?.viewModel.resume() } }
        nowPlayingBridge.onPause = { [weak self] in Task { @MainActor in self?.viewModel.pause() } }
        nowPlayingBridge.onTogglePlayPause = { [weak self] in
            Task { @MainActor in
                guard let vm = self?.viewModel else { return }
                vm.playerState == .playing ? vm.pause() : vm.resume()
            }
        }
        nowPlayingBridge.onNext = { [weak self] in Task { @MainActor in self?.viewModel.next() } }
        nowPlayingBridge.onPrevious = { [weak self] in Task { @MainActor in self?.viewModel.previous() } }
        nowPlayingBridge.onSeek = { [weak self] time in
            Task { @MainActor in self?.viewModel.seek(to: time) }
        }
    }
}

// MARK: - ViewModel Bindings

private extension AppDelegate {
    func bindViewModel() {
        bindConfig()
        bindSearch()
        bindPlayback()
        bindAuth()
        bindLibrary()
        bindCache()
        bindUI()
        bindLyrics()
        bindRating()
        bindSavePlaylist()
    }

    func bindUI() {
        viewModel.windowOpacity = uiConfig.windowOpacity
        viewModel.audioQuality = uiConfig.streamQuality
        viewModel.previousRestartEnabled = uiConfig.previousRestartEnabled
        viewModel.previousRestartThreshold = uiConfig.previousRestartThreshold
        viewModel.autoHideBrowsePanel = uiConfig.autoHideBrowsePanel
        viewModel.browsePanelExpanded = !uiConfig.autoHideBrowsePanel
        viewModel.autoExtendQueueEnabled = uiConfig.autoExtendQueueWithRadio
        viewModel.volume = uiConfig.volume
        audioPlayer.setVolume(Float(uiConfig.volume))
        viewModel.debugLoggingEnabled = uiConfig.debugLoggingEnabled
        DebugLogger.shared.isEnabled = uiConfig.debugLoggingEnabled
        streamExtractor.currentFormat = uiConfig.streamQuality.ytdlpFormat
        observeBrowsePanelSize()
        viewModel.onSetWindowOpacity = { [weak self] value in
            guard let self else { return }
            self.uiConfig.windowOpacity = value
            try? self.uiConfig.save()
            self.applyWindowOpacity(value)
        }
        viewModel.onSetAudioQuality = { [weak self] quality in
            guard let self else { return }
            self.uiConfig.streamQuality = quality
            try? self.uiConfig.save()
            self.streamExtractor.currentFormat = quality.ytdlpFormat
            self.urlCache.removeAll()
        }
        viewModel.onSetPreviousRestartEnabled = { [weak self] enabled in
            guard let self else { return }
            self.uiConfig.previousRestartEnabled = enabled
            try? self.uiConfig.save()
        }
        viewModel.onSetPreviousRestartThreshold = { [weak self] seconds in
            guard let self else { return }
            self.uiConfig.previousRestartThreshold = seconds
            try? self.uiConfig.save()
        }
        viewModel.onSetAutoHideBrowsePanel = { [weak self] enabled in
            guard let self else { return }
            self.uiConfig.autoHideBrowsePanel = enabled
            try? self.uiConfig.save()
            if !enabled {
                // Turning auto-hide off → reveal the panel immediately.
                // Turning it on leaves the current expanded state alone;
                // next popover open starts collapsed.
                self.viewModel.browsePanelExpanded = true
            }
        }
        viewModel.onSetAutoExtendQueueEnabled = { [weak self] enabled in
            guard let self else { return }
            self.uiConfig.autoExtendQueueWithRadio = enabled
            try? self.uiConfig.save()
        }
        viewModel.onSetDebugLogging = { [weak self] enabled in
            guard let self else { return }
            self.uiConfig.debugLoggingEnabled = enabled
            try? self.uiConfig.save()
            DebugLogger.shared.isEnabled = enabled
        }
        viewModel.resumeSessionEnabled = uiConfig.resumeSessionEnabled
        viewModel.onSetResumeSession = { [weak self] enabled in
            guard let self else { return }
            self.uiConfig.resumeSessionEnabled = enabled
            try? self.uiConfig.save()
            if !enabled { PlaybackState.clear() }
        }
        viewModel.autoUpdateYtdlp = uiConfig.autoUpdateYtdlp
        viewModel.onSetAutoUpdateYtdlp = { [weak self] enabled in
            guard let self else { return }
            self.uiConfig.autoUpdateYtdlp = enabled
            try? self.uiConfig.save()
        }
        viewModel.onUpdateYtdlp = { [weak self] in
            guard let self else { return }
            try await self.dependencyManager.update()
            self.urlCache.removeAll()
        }
    }

    func applyWindowOpacity(_ value: Double) {
        popover.contentViewController?.view.window?.alphaValue = CGFloat(value)
    }

    /// Returns true if a "previous" press should restart the current song
    /// instead of moving to the previous track. False means the caller should
    /// proceed with the existing previous-track behavior.
    func shouldRestartOnPrevious() -> Bool {
        guard uiConfig.previousRestartEnabled else { return false }
        return audioPlayer.currentTime >= uiConfig.previousRestartThreshold
    }

    /// Popover height when the browse panel is collapsed (player + nav bar).
    /// This must match `ContentView.topBarHeight` so the collapsed popover
    /// exactly shows the top-controls layer with no empty strip below.
    static let collapsedPopoverHeight: CGFloat = 170
    static let expandedPopoverHeight: CGFloat = 520
    static let popoverWidth: CGFloat = 420

    /// Observes the view model so the popover resizes to match the
    /// collapsed/expanded browse-panel state.
    func observeBrowsePanelSize() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updatePopoverSizeIfNeeded() }
            .store(in: &cancellables)
    }

    func updatePopoverSizeIfNeeded() {
        let height = viewModel.isBrowsePanelVisible
            ? Self.expandedPopoverHeight
            : Self.collapsedPopoverHeight
        let target = NSSize(width: Self.popoverWidth, height: height)
        guard popover.contentSize != target else { return }
        // Snap the popover bubble instantly — no animation. Matches the
        // SwiftUI side which also has no `.animation(...)` on the browse
        // panel frame change.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            ctx.allowsImplicitAnimation = false
            popover.contentSize = target
        }
    }

    func bindSearch() {
        viewModel.onSearch = { [weak self] query in
            guard let self else { return [] }
            let result = try await self.musicClient.search(
                query: query
            )
            return result.tracks
        }
    }

    func bindPlayback() {
        viewModel.onPlayTrack = { [weak self] track in
            guard let self else { return }
            await self.playTrack(track)
        }
        viewModel.onNext = { [weak self] in
            guard let self else { return }
            guard let track = self.queueManager.next() else { return }
            await self.playTrack(track)
        }
        viewModel.onPrevious = { [weak self] in
            guard let self else { return }
            if self.shouldRestartOnPrevious() {
                self.audioPlayer.seek(to: 0)
                return
            }
            guard let track = self.queueManager.previous() else { return }
            await self.playTrack(track)
        }
        audioPlayer.onTrackFinished = { [weak self] in
            Task { @MainActor in self?.viewModel.next() }
        }
        audioPlayer.onPlaybackError = { [weak self] msg in
            Task { @MainActor in
                self?.handlePlaybackError(msg)
            }
        }
        viewModel.onSeek = { [weak self] seconds in
            guard let self else { return }
            let avDur = self.audioPlayer.duration
            guard avDur > 0 else { return }
            self.audioPlayer.seek(to: seconds / avDur)
        }
        viewModel.onPause = { [weak self] in
            self?.audioPlayer.pause()
        }
        viewModel.onResume = { [weak self] in
            self?.audioPlayer.play()
        }
        viewModel.onSetVolume = { [weak self] vol in
            guard let self else { return }
            self.audioPlayer.setVolume(vol)
            self.uiConfig.volume = Double(vol)
            try? self.uiConfig.save()
        }
        viewModel.onToggleShuffle = { [weak self] in
            self?.queueManager.toggleShuffle()
        }
        viewModel.onCycleRepeatMode = { [weak self] in
            guard let self else { return }
            switch self.queueManager.repeatMode {
            case .off: self.queueManager.repeatMode = .all
            case .all: self.queueManager.repeatMode = .one
            case .one: self.queueManager.repeatMode = .off
            }
        }
        viewModel.onQueueTracks = { [weak self] tracks, idx in
            self?.queueManager.setPlaylist(tracks, startAt: idx)
            self?.prefetchURLs(for: Array(tracks.dropFirst(idx + 1)))
        }
        viewModel.onQueueReorder = { [weak self] source, dest in
            guard let self else { return }
            self.queueManager.move(fromOffsets: source, toOffset: dest)
            self.prefetchNextInQueue()
        }
        viewModel.onAddToQueue = { [weak self] track in
            self?.queueManager.add(track)
        }
        viewModel.onStartRadio = { [weak self] track in
            guard let self else { return }
            await self.loadRadioForTrack(track)
        }
        startUISync()
    }

    func startUISync() {
        // Fast timer for playback progress — keeps lyrics in sync.
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.viewModel.progress = self.audioPlayer.currentTime
            if self.pendingTrack == nil {
                self.viewModel.playerState = self.audioPlayer.state
            }
            if let track = self.viewModel.currentTrack, track.durationSeconds > 0 {
                self.viewModel.duration = Double(track.durationSeconds)
            } else {
                self.viewModel.duration = self.audioPlayer.duration / 2
            }
        }
        // Slower timer for queue state, cache stats, Now Playing bridge.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.viewModel.queueTracks = self.queueManager.tracks
            self.viewModel.queueIndex = self.queueManager.currentIndex
            self.viewModel.autoExtendStartIndex = self.queueManager.autoExtendStartIndex
            self.viewModel.isShuffled = self.queueManager.isShuffled
            self.viewModel.repeatMode = self.queueManager.repeatMode
            self.viewModel.cacheUsageMB = self.cacheMB()
            self.syncNowPlaying()
        }
        startMemoryCleanup()
    }

    func startMemoryCleanup() {
        // Every 5 minutes: evict expired stream URLs and flush
        // the system thumbnail cache to keep RSS low.
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.evictExpiredURLCache()
            URLCache.shared.removeAllCachedResponses()
            self.cacheMetadata.pruneStaleEntries()
            Task { await self.lyricsProvider.trimCache(maxEntries: 50) }
        }
    }

    private static let urlCacheMaxEntries = 200
    private static let urlCacheTTL: TimeInterval = 18000

    func evictExpiredURLCache() {
        let now = Date()
        urlCache = urlCache.filter { now.timeIntervalSince($0.value.1) < Self.urlCacheTTL }
    }

    func trimURLCacheIfNeeded() {
        guard urlCache.count > Self.urlCacheMaxEntries else { return }
        let sorted = urlCache.sorted { $0.value.1 < $1.value.1 }
        let drop = urlCache.count - Self.urlCacheMaxEntries
        for (key, _) in sorted.prefix(drop) { urlCache.removeValue(forKey: key) }
    }

    func syncNowPlaying() {
        guard let track = viewModel.currentTrack else { return }
        nowPlayingBridge.update(
            track: track,
            state: viewModel.playerState,
            progress: audioPlayer.currentTime
        )
    }

    func bindConfig() {
        let config = AppConfig.load()
        viewModel.configClientID = config.clientID
        viewModel.configClientSecret = config.clientSecret
        viewModel.onSaveConfig = { [weak self] id, secret in
            let c = AppConfig(clientID: id, clientSecret: secret)
            do {
                try c.save()
            } catch {
                self?.logDebug("AppConfig save failed: \(error)")
            }
            self?.auth.updateCredentials(id: id, secret: secret)
        }
    }

    func bindAuth() {
        viewModel.onSignIn = { [weak self] in
            guard let self else { return nil }
            try await self.auth.startDeviceFlow()
            if let urlStr = self.auth.verificationURL,
               let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
            return self.auth.userCode
        }
        viewModel.onPollForToken = { [weak self] _ in
            guard let dc = self?.auth.deviceCode else { return }
            try await self?.auth.pollForToken(deviceCode: dc)
        }
        viewModel.onSignOut = { [weak self] in
            self?.auth.logout()
        }
    }

    func bindLibrary() {
        viewModel.onFetchLibrary = { [weak self] in
            guard let self else { return [] }
            return try await self.musicClient.getLibraryPlaylists()
        }
        viewModel.onFetchPlaylistTracks = { [weak self] id in
            guard let self else { return [] }
            return try await self.musicClient.getPlaylistTracks(
                playlistId: id
            )
        }
        viewModel.onFetchPlaylistPage = { [weak self] id, token in
            guard let self else { return ([], nil) }
            let page = try await self.musicClient.getPlaylistPage(
                playlistId: id, pageToken: token
            )
            return (page.tracks, page.nextPageToken)
        }
    }

    func bindCache() {
        viewModel.cacheConfig = cacheConfig
        viewModel.cacheUsageMB = cacheMB()
        viewModel.onSaveCacheConfig = { [weak self] config in
            self?.cacheConfig = config
            self?.audioFileCache.maxSizeBytes = config.maxSizeBytes
            self?.audioFileCache.downloadQuality = config.downloadQuality
            try? config.save()
        }
        viewModel.onClearCache = { [weak self] in
            try? self?.audioFileCache.clearAll()
        }
        viewModel.onFetchCacheUsage = { [weak self] in
            self?.cacheMB() ?? 0
        }
        viewModel.onKeepOffline = { [weak self] ids in
            self?.audioFileCache.downloadAll(videoIds: ids)
        }
        viewModel.onCachedCount = { [weak self] ids in
            self?.audioFileCache.cachedCount(of: ids) ?? 0
        }
    }

    func bindLyrics() {
        viewModel.onFetchLyrics = { [weak self] videoId, title, artist in
            await self?.lyricsProvider.fetch(
                videoId: videoId, title: title, artist: artist
            )
        }
    }

    func bindSavePlaylist() {
        viewModel.onSaveQueueAsPlaylist = { [weak self] name, tracks in
            guard let self else { throw YTMusicError.invalidResponse }
            let playlistId = try await self.musicClient.createPlaylist(title: name)
            for track in tracks {
                try await self.musicClient.addToPlaylist(
                    playlistId: playlistId, videoId: track.id
                )
            }
            return playlistId
        }
        viewModel.onAppendTracksToPlaylist = { [weak self] playlistId, tracks in
            guard let self else { return }
            for track in tracks {
                try await self.musicClient.addToPlaylist(
                    playlistId: playlistId, videoId: track.id
                )
            }
            // The auto-extended tracks are now part of the playlist;
            // clear the divider so they merge into the "original" section.
            self.queueManager.clearAutoExtendDivider()
        }
    }

    func bindRating() {
        viewModel.onRateVideo = { [weak self] videoId, rating in
            guard let self else { return }
            try await self.musicClient.rateVideo(
                videoId: videoId, rating: rating
            )
        }
        viewModel.onGetRating = { [weak self] videoId in
            guard let self else { return "none" }
            return try await self.musicClient.getVideoRating(
                videoId: videoId
            )
        }
    }

    func cacheMB() -> Int {
        Int(audioFileCache.currentUsage() / 1_048_576)
    }

    func playTrack(_ track: Track) async {
        playGeneration &+= 1
        let myGeneration = playGeneration
        let wasPlaying = audioPlayer.state == .playing
        pendingTrack = track
        logDebug("playTrack: \(track.title) gen=\(myGeneration)")
        if !wasPlaying {
            viewModel.currentTrack = track
            viewModel.playerState = .loading
        }
        do {
            let url = try await resolveTrackURL(for: track)
            guard myGeneration == playGeneration else {
                logDebug("Stale gen=\(myGeneration), skipping")
                return
            }
            pendingTrack = nil
            audioPlayer.realDuration = Double(track.durationSeconds)
            audioPlayer.load(url: url)
            audioPlayer.play()
            viewModel.currentTrack = track
            viewModel.playerState = .playing
            viewModel.clearLyrics()
            viewModel.isLiked = false
            viewModel.fetchRating(for: track.id)
            if viewModel.showLyrics { viewModel.fetchLyricsForCurrentTrack() }
            updateNowPlaying(track: track)
            recordPlayAndCache(track: track)
            loadRadioIfNeeded(for: track)
            maybeAutoExtendQueue(seed: track)
            prefetchNextInQueue()
        } catch {
            guard myGeneration == playGeneration else { return }
            pendingTrack = nil
            logDebug("playTrack error: \(error)")
            viewModel.playerState = .error(
                error.localizedDescription
            )
            viewModel.showToast(.error, message: "Failed to play track")
        }
    }

    func resolveTrackURL(for track: Track) async throws -> URL {
        if let localURL = audioFileCache.localFileURL(for: track.id) {
            logDebug("Playing from cache: \(track.id)")
            return localURL
        }
        return try await cachedStreamURL(for: track.id)
    }

    func recordPlayAndCache(track: Track) {
        let count = cacheMetadata.recordPlay(videoId: track.id)
        cacheMetadata.save()
        guard cacheConfig.isEnabled else { return }
        audioFileCache.downloadInBackground(
            videoId: track.id,
            playCount: count,
            threshold: cacheConfig.autoCacheThreshold
        )
    }

    func loadRadioIfNeeded(for track: Track) {
        guard queueManager.tracks.count <= 1 else { return }
        Task { await loadRadioForTrack(track) }
    }

    func loadRadioForTrack(_ track: Track) async {
        let mix = try? await musicClient.getRadioMix(videoId: track.id)
        guard let tracks = mix, tracks.count > 1 else {
            if mix == nil {
                viewModel.showToast(.error, message: "Failed to load radio mix")
            }
            return
        }
        let upcoming = tracks.filter { $0.id != track.id }
        queueManager.setPlaylist([track] + upcoming, startAt: 0)
        logDebug("Radio mix loaded: \(upcoming.count) tracks")
        prefetchNextInQueue()
    }

    /// Called each time a new track starts playing. If the queue has fewer
    /// than `autoExtendLookahead` upcoming tracks left, kicks off a
    /// background radio-mix fetch that appends deduplicated results to the
    /// end of the queue (preserving the original section and drawing a
    /// divider between it and the added tracks).
    func maybeAutoExtendQueue(seed: Track) {
        guard uiConfig.autoExtendQueueWithRadio else { return }
        guard !isAutoExtendingQueue else { return }
        guard queueManager.repeatMode != .all else { return }
        let tracks = queueManager.tracks
        guard tracks.count > 1 else { return }   // let loadRadioIfNeeded handle this
        guard tracks.count < QueueManager.maxTracks else { return }
        let remaining = tracks.count - 1 - queueManager.currentIndex
        guard remaining < Self.autoExtendLookahead else { return }
        isAutoExtendingQueue = true
        Task { await performAutoExtend(seed: seed) }
    }

    func performAutoExtend(seed: Track) async {
        defer { isAutoExtendingQueue = false }
        let mix = try? await musicClient.getRadioMix(videoId: seed.id)
        guard let mix, !mix.isEmpty else { return }
        let existing = Set(queueManager.tracks.map(\.id))
        let additions = mix.filter { !existing.contains($0.id) }
        guard !additions.isEmpty else {
            logDebug("Auto-extend: radio returned no new tracks")
            return
        }
        queueManager.appendAutoExtended(additions)
        logDebug("Auto-extended queue with \(additions.count) radio tracks")
        prefetchNextInQueue()
    }

    func clearQueueAfterCurrent() {
        let idx = queueManager.currentIndex
        let count = queueManager.tracks.count
        guard idx + 1 < count else { return }
        for i in stride(from: count - 1, through: idx + 1, by: -1) {
            queueManager.remove(at: i)
        }
    }

    func cachedStreamURL(for videoId: String) async throws -> URL {
        if let (url, time) = urlCache[videoId],
           Date().timeIntervalSince(time) < 18000 {
            return url
        }
        let url = try await streamExtractor.extractStreamURL(
            videoId: videoId
        )
        urlCache[videoId] = (url, Date())
        trimURLCacheIfNeeded()
        return url
    }

    func prefetchNextInQueue() {
        let idx = queueManager.currentIndex
        let upcoming = Array(queueManager.tracks.dropFirst(idx + 1).prefix(2))
        for track in upcoming {
            guard urlCache[track.id] == nil else { continue }
            Task.detached { [weak self] in
                _ = try? await self?.cachedStreamURL(for: track.id)
            }
        }
    }

    func prefetchURLs(for tracks: [Track]) {
        for track in tracks.prefix(2) {
            guard urlCache[track.id] == nil else { continue }
            Task.detached { [weak self] in
                _ = try? await self?.cachedStreamURL(for: track.id)
            }
        }
    }

    func handlePlaybackError(_ message: String) {
        let isOutdated = dependencyManager.daysSinceInstall() > 90
        if isOutdated {
            viewModel.showToast(
                .error,
                message: "Playback failed — yt-dlp is outdated",
                detail: "Update in Settings or restart the app"
            )
        } else {
            viewModel.showToast(.error, message: "Playback failed")
        }
    }

    func logDebug(_ msg: String) {
        DebugLogger.shared.log("[PLAY] \(msg)")
    }

    func updateNowPlaying(track: Track) {
        nowPlayingBridge.update(track: track, state: .playing, progress: 0)
        let name = "music.note.list"
        statusItem.button?.image = NSImage(
            systemSymbolName: name, accessibilityDescription: "YTBar"
        )
    }

    func saveSessionIfEnabled() {
        guard uiConfig.resumeSessionEnabled else { return }
        let tracks = queueManager.tracks
        guard !tracks.isEmpty else { return }
        let state = PlaybackState(
            queue: tracks,
            currentIndex: queueManager.currentIndex,
            progressSeconds: audioPlayer.currentTime,
            repeatMode: queueManager.repeatMode,
            isShuffled: queueManager.isShuffled,
            queueSourcePlaylistId: viewModel.queueSourcePlaylistId,
            queueSourcePlaylistTitle: viewModel.queueSourcePlaylistTitle,
            autoExtendStartIndex: queueManager.autoExtendStartIndex
        )
        state.save()
        logDebug("Session saved: \(tracks.count) tracks, idx=\(state.currentIndex)")
    }

    func restoreSessionIfEnabled() {
        guard uiConfig.resumeSessionEnabled else { return }
        guard let state = PlaybackState.load(), !state.queue.isEmpty else { return }
        let idx = min(state.currentIndex, state.queue.count - 1)
        queueManager.setPlaylist(state.queue, startAt: idx)
        queueManager.repeatMode = state.repeatMode
        queueManager.autoExtendStartIndex = state.autoExtendStartIndex
        viewModel.queueSourcePlaylistId = state.queueSourcePlaylistId
        viewModel.queueSourcePlaylistTitle = state.queueSourcePlaylistTitle
        let track = state.queue[idx]
        viewModel.currentTrack = track
        viewModel.progress = state.progressSeconds
        viewModel.duration = Double(track.durationSeconds)
        viewModel.playerState = .paused
        logDebug("Restored session: \(state.queue.count) tracks, idx=\(idx)")
    }
}
