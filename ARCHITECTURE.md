# Architecture Notes — YTBar

Non-obvious patterns and constraints discovered during implementation. Not a file list or restatement of CLAUDE.md — things not derivable from reading the code alone.

**Tags:** `[api]`, `[player]`, `[auth]`, `[cache]`, `[ui]`, `[build]`, `[yt-dlp]`

Retrieve by tag: `grep '\[player\]' ARCHITECTURE.md`

---

- [api] Bearer tokens DO NOT work with YTM internal API (causes 400) — search must be unauthenticated
- [api] YouTube innertube search returns `musicCardShelfRenderer` + `itemSectionRenderer` (not `musicShelfRenderer`); parser handles both old and new formats
- [api] Artist in search results is at column 1 runs index 2 in new format (`['Song', ' • ', 'Artist']`)
- [api] Radio mix `longBylineText` includes views/likes — use `shortBylineText` for clean artist names
- [api] `parsePlaylistTracks` and `parseLibraryPlaylists` in YTMusicParser are dead code (library uses YTDataParser via YouTube Data API v3)
- [player] AVPlayer reports 2x duration for YouTube m4a streams — use Track.durationSeconds from search, or /2 fallback
- [player] `playGeneration` counter prevents race conditions when rapidly clicking songs
- [player] yt-dlp stderr must be separated from stdout (warnings corrupt URL parsing)
- [player] `checkRealEnd` uses `realDuration` (from search metadata) to detect true end of track, since AVPlayer's reported duration is doubled
- [player] Session restore saves PlaybackState to `playback-state.json` on quit; restores visually (paused) on launch — does NOT call `playTrack()`, user hits play to start streaming
- [auth] File-based token storage (not Keychain) to avoid password prompts from unsigned debug builds
- [auth] Ephemeral URLSession with no cookies for music API (prevents OAuth cookie leakage to YTM internal API)
- [auth] `nonisolated(unsafe)` on cachedAccessToken for cross-actor access
- [cache] Audio file cache: JSON metadata + file storage in `~/Library/Application Support/YTBar/cache/`, LRU eviction, configurable size/threshold
- [cache] Lyrics disk cache: `{videoId}.lyrics.json` in same cache dir, tracked in CacheMetadata via `lyricsFileSize`, counted toward total cache limit
- [cache] Memory caps: urlCache 200 entries LRU, CacheMetadata prunes entries >90 days with no cached files, QueueManager.maxTracks = 500
- [ui] Popover sizing: must set `browsePanelExpanded` and call `updatePopoverSizeIfNeeded()` BEFORE `popover.show()`, not in `popoverWillShow` delegate — async resize during show causes offscreen positioning
- [ui] Timer-based UI sync: 0.1s for playback progress (keeps lyrics in sync), 0.5s for queue state/cache stats
- [build] Swift Package Manager project, no Xcode project — `swift build`, `swift test`
- [build] Bundle ID: `com.ytmusicbar.app`, LSUIElement: true (menubar-only), unsigned
- [yt-dlp] yt-dlp bundled in `~/Library/Application Support/YTBar/bin/`, auto-downloaded from GitHub Releases on first launch
- [yt-dlp] Must pass `--js-runtimes node:/opt/homebrew/bin/node` for YouTube extraction
- [yt-dlp] `DependencyManager.ensureUpToDate()` checks both existence and age (>90 days = outdated); `ensureInstalled()` only checks existence
- [yt-dlp] Stale yt-dlp extracts URLs that return HTTP 403 — AVPlayer then fails silently; `onPlaybackError` callback now surfaces these as toasts
- [yt-dlp] Auto-update on launch controlled by `UIConfig.autoUpdateYtdlp` (default: true); manual update via Settings yt-dlp section
