# Active Context — YTBar (formerly YTMusicBar)

**Last updated:** 2026-04-12

## Current Focus

App renamed to YTBar and publicly released on GitHub as `mlares85/YTBar` (GPL v3). v1.0.0 tagged and DMG uploaded to GitHub Releases.

## Recent Changes (This Session)

### Features
- **Previous button smart restart**: Configurable threshold (default 5s) — restart current song on back press, jump to previous if pressed early. Toggle + stepper in Settings > Playback.
- **Player layout reshaped**: 100×100 artwork left, controls right in an HStack. Same overall footprint.
- **Nav bar moved below player**: Tab bar sits directly under the now-playing view.
- **Auto-hide browse panel**: Panel collapses when popover closes (configurable toggle). Click a nav button to expand, click the same button again to collapse. Popover snaps instantly (no slide animation). Panel fades were attempted but removed in favor of instant show/hide.
- **Auto-extend queue with radio**: When ≤5 tracks remain, fetches radio mix seeded from current track, dedupes against queue, appends. Visual divider between original and auto-added tracks. "Append to playlist" button to push radio tracks into source playlist.
- **Queue drag-to-reorder**: Grab handles on each row, `.onMove` within original and radio sections independently.
- **Queue playlist title**: Shows source playlist name centered in header. Updates after save-queue-as-playlist.
- **Search radio button**: Each search result now has a radio mix button.
- **Search query persistence**: Query + results survive tab navigation (moved from local @State to AppViewModel).
- **Liked music 30-minute cache**: Tracks cached on AppViewModel with TTL. No re-fetch on tab switch within 30 minutes. Manual refresh bypasses TTL.
- **Hover tooltips**: Added `.help()` to all buttons across all views.
- **Nav button highlight**: Active tab has rounded rectangle background with primary opacity.
- **Playlist action buttons enlarged**: Refresh, download, play, shuffle bumped from 11pt to 16pt.
- **Tab bar bottom padding**: Added 10pt below nav bar labels for breathing room.

### Toast notification system
- `ToastView.swift`: Error (red), success (green), info (blue) styles. Auto-dismiss 3.5s.
- Wired to all previously-silent error paths: search, playback, radio mix, playlist save, like/unlike, liked music fetch, append-to-playlist.
- Success toasts for playlist save and track append.

### Debug logging system
- `DebugLogger.swift`: Singleton writing to `~/Library/Logs/YTBar/ytbar.log`. Thread-safe, auto-rotates at 500KB.
- Replaced all `/tmp/ytbar-debug.log` calls across 7 files. Zero `/tmp/` references remain.
- Settings > Diagnostics: toggle (default OFF) + Export button with NSSavePanel.

### Lyrics fix
- Disabled initial-render animation via `Transaction { disablesAnimations = true }` on `.onAppear` to prevent flicker when lyrics view re-mounts.

### Release prep
- **Renamed**: YTMusicBar → YTBar (dirs, targets, all string refs, Package.swift, cache paths, UI strings). YTMusicClient/YTMusicParser kept as-is (refer to the YouTube Music service).
- **Flattened dirs**: `Sources/YTBar/` → `Sources/`, `Tests/YTBarTests/` → `Tests/`.
- **GPL v3 LICENSE** added.
- **`.gitignore`** created (excludes .build, AuthConfig.swift, DMGs).
- **API key comment** on the public innertube key.
- **AuthConfig.swift untracked** from git (gitignored).
- **Dev artifacts removed**: activeContext.md, public-release-plan.md, LESSONS_LEARNED.md.
- **README.md** written: features, setup, privacy, diagnostics, architecture. Screenshots + animated GIF gallery.
- **Info.plist** created for proper .app bundle (bundle ID: com.mlares85.ytbar, LSUIElement: true).
- **DMG** built via hdiutil, uploaded to GitHub Releases.
- **Fresh public repo**: `mlares85/YTBar`, single squashed initial commit, tagged v1.0.0.

## Recent Decisions

- **No slide animation** for browse panel show/hide — instant snap. Slide caused player jitter due to SwiftUI layout passes; fade was tried but user preferred instant.
- **VStack architecture** for ContentView: topControlsLayer is a SIBLING of slideContainer (not inside ZStack), completely decoupled from animation. Prevents player jitter.
- **GPL v3** chosen over MIT to prevent closed-source commercial forks.
- **YTBar** chosen as name (checked: not taken on GitHub, npm, PyPI, crates.io, Homebrew).
- **60 MB RAM** is the accurate physical footprint (Activity Monitor), not the ~104 MB RSS from `ps aux`.
- **Debug logging default OFF** for privacy — users must opt in via Settings.
- **Liked music cache** uses in-memory 30-minute TTL, not disk persistence.

## Blockers / Open Questions

- Pre-existing Swift 6 sendability warnings in `startUISync` timer closure (unchanged)
- App is unsigned — users must right-click > Open on first launch. Code signing would eliminate this.
- No app icon — using default macOS generic app icon.
- The `shuffleOrder` / `toggleShuffle()` code path in QueueManager is dead code (never called from UI). Could be cleaned up or wired to a shuffle button.

## Next Steps

1. Consider adding an app icon
2. Consider code signing for Gatekeeper
3. Monitor GitHub issues for bug reports
4. Potential v1.1 features: shuffle button in player, album art improvements, persist repeat/volume across launches
