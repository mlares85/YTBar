# YTBar

A lightweight native macOS menubar app for streaming YouTube Music. Built with Swift and SwiftUI, YTBar uses ~60 MB of RAM compared to ~300-500 MB for Electron-based alternatives.

## Features

**Playback**
- Stream any track from the YouTube Music catalog
- Synced lyrics with auto-scroll (plain text fallback)
- Radio mix generation from any track
- Auto-extend queue with radio when nearing the end of a playlist
- Smart previous button (restarts track or jumps to previous, configurable)
- Streaming quality selection (Low / Normal / High)
- macOS Now Playing integration (media keys, Control Center)

**Library**
- Browse your YouTube Music playlists
- View and play liked music
- Like/unlike tracks from the player
- Save queue as a new playlist
- Append auto-added radio tracks to the source playlist

**Queue**
- Drag-to-reorder with grab handles
- Visual divider between original queue and auto-added radio tracks
- Playlist name displayed in queue header

**Offline**
- Local audio cache with configurable size (100 - 2000 MB)
- Auto-cache after N plays (configurable)
- "Keep Offline" button for bulk playlist downloads
- Lyrics cached to disk

**Interface**
- Collapsible browse panel (auto-hides when the popover closes)
- Keyboard shortcuts (Space, Command+Arrow)
- Hover tooltips on all buttons
- Adjustable window opacity

## Requirements

- **macOS 14 (Sonoma)** or later
- A **Google account** with a Google Cloud project (free, setup takes ~5 minutes)
- **YouTube Premium** recommended for ad-free audio (not required)
- **yt-dlp** is downloaded automatically on first launch

## Installation

### Download

Download the latest release from the [Releases](../../releases) page. Unzip and drag `YTBar.app` to your Applications folder.

Since the app is unsigned, macOS Gatekeeper will block it on first launch. Right-click the app and choose **Open**, then click **Open** in the dialog.

### Build from source

```bash
git clone https://github.com/mlares85/YTBar.git
cd YTBar
swift build -c release
```

The binary is at `.build/release/YTBar`. To install, create an app bundle:

```bash
mkdir -p /Applications/YTBar.app/Contents/MacOS
cp .build/release/YTBar /Applications/YTBar.app/Contents/MacOS/
```

## Setup

YTBar requires a Google Cloud project with OAuth credentials to access your library, playlists, and liked music. Search works without authentication.

### Quick setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and create a new project
2. Enable the **YouTube Data API v3** in the API Library
3. Configure the **OAuth consent screen** (External, add yourself as a test user)
4. Create **OAuth credentials** (application type: "TVs and Limited Input devices")
5. Open YTBar, go to **Settings**, paste your Client ID and Client Secret, click **Save**
6. Click **Sign In with Google** and follow the device flow prompts

A detailed step-by-step guide is bundled with the app (Settings > Setup Guide).

### Required OAuth scope

The app requests the `https://www.googleapis.com/auth/youtube` scope, which allows it to:
- Read your playlists and liked music
- Create and modify playlists
- Rate (like/unlike) videos

The app does **not** upload videos, manage your channel, or access any data beyond your music library.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| Play / Pause | Space |
| Next track | Command + Right Arrow |
| Previous track | Command + Left Arrow |

## Privacy

**What stays on your machine:**
- Audio files (cached locally if caching is enabled)
- Lyrics (cached in Application Support)
- OAuth tokens (stored in `~/Library/Application Support/YTBar/`)
- All configuration and preferences
- Debug logs (`~/Library/Logs/YTBar/`, disabled by default)

**What goes to Google:**
- Search queries (YouTube Music internal API)
- Playlist and library requests (YouTube Data API v3, authenticated)
- Rating updates when you like/unlike a track
- OAuth token refresh requests

**What YTBar does NOT do:**
- No telemetry, analytics, or crash reporting
- No data sent to any server other than Google's APIs
- No cookies stored (ephemeral URL sessions with cookies disabled)
- No background network activity when idle

**Storage locations:**

| Data | Path |
|---|---|
| Config | `~/Library/Application Support/YTBar/config.json` |
| Auth tokens | `~/Library/Application Support/YTBar/com.ytbar.auth.json` |
| Audio cache | `~/Library/Application Support/YTBar/cache/` |
| Debug logs | `~/Library/Logs/YTBar/ytbar.log` |

### About the embedded API key

The source code contains a hardcoded API key (`AIzaSyC9XL...`). This is YouTube Music's **public innertube API key** -- the same key embedded in every YouTube Music web page for unauthenticated search requests. It is not a per-user credential and cannot be used to access anyone's account. See [ytmusicapi](https://github.com/sigma67/ytmusicapi) for context.

## Diagnostics

If something isn't working:

1. Go to **Settings > Diagnostics** and enable **Debug logging**
2. Reproduce the issue
3. Click **Export Debug Log** to save the log file
4. [Open an issue](../../issues) and attach the exported log

Logs are written to `~/Library/Logs/YTBar/ytbar.log` and auto-rotate at 500 KB. Logging is off by default.

## Building and development

```bash
swift build              # Debug build
swift test               # Run tests (76 tests)
swift build -c release   # Release build
```

Or open `Package.swift` in Xcode 15+ and build from there.

### Architecture

```
Sources/YTBar/
  App/       Entry point, AppDelegate, menubar + service wiring
  Auth/      Google OAuth device flow, token storage
  API/       YTMusic search, playlists, stream extraction, lyrics, parsers
  Player/    AVPlayer wrapper, queue manager, Now Playing bridge
  Views/     SwiftUI: search, library, playlist, queue, settings, lyrics, toast
  Infra/     yt-dlp lifecycle, caching, config persistence, debug logger
```

| Feature | Backend | Auth |
|---|---|---|
| Search | `music.youtube.com/youtubei/v1/search` | None (public API key) |
| Radio mix | `music.youtube.com/youtubei/v1/next` | None (public API key) |
| Playlists | `googleapis.com/youtube/v3/` | OAuth Bearer token |
| Streaming | yt-dlp extracts direct audio URL | None |
| Playback | AVPlayer with AVURLAsset | None |

### Dependencies

- **yt-dlp**: Auto-downloaded on first launch to `~/Library/Application Support/YTBar/bin/`
- No CocoaPods, SPM packages, or other external dependencies -- pure Swift + system frameworks

## License

YTBar is licensed under the [GNU General Public License v3.0](LICENSE).

You are free to use, modify, and distribute this software under the terms of the GPL v3. Any derivative work must also be distributed under the same license.
