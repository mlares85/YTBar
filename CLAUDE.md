# YTBar

Native Swift/SwiftUI macOS menubar app for streaming YouTube Music.
Swift Package Manager project, no Xcode project.

## Build

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run tests
```

## Release DMG

After a release build, assemble the .app bundle and create the DMG:

```bash
# 1. Build release binary
swift build -c release

# 2. Assemble app bundle in a temp directory
TMPDIR="/tmp/YTBar-dmg-build"
APP="$TMPDIR/YTMusicBar.app"
rm -rf "$TMPDIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 3. Copy binary (rename to match CFBundleExecutable)
cp .build/release/YTBar "$APP/Contents/MacOS/YTMusicBar"

# 4. Copy icon and resource bundle
cp /Applications/YTMusicBar.app/Contents/Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R .build/release/YTBar_YTBar.bundle "$APP/Contents/Resources/"

# 5. Write Info.plist (update CFBundleVersion and CFBundleShortVersionString)
# See existing /Applications/YTMusicBar.app/Contents/Info.plist for template

# 6. Create DMG
hdiutil create -volname "YTBar" -srcfolder "$TMPDIR" -ov -format UDZO "YTBar-<version>.dmg"
```

The DMG is gitignored. Upload it to GitHub Releases manually or via `gh release create`.

## Architecture

- Search: YTM internal API (music.youtube.com/youtubei/v1/search), NO auth
- Playlists/Library: YouTube Data API v3, OAuth Bearer token
- Streaming: yt-dlp extracts audio URLs, AVPlayer plays them
- Auth: Google OAuth device flow

**Critical**: Bearer tokens DO NOT work with YTM internal API (causes 400). Search must be unauthenticated.

## Key Conventions

- All config/token files stored in `~/Library/Application Support/YTBar/`
- Config files use atomic writes (`.atomic` option)
- File-based token storage (not Keychain) to avoid password prompts from unsigned builds
- Ephemeral URLSession with no cookies for music API
- `playGeneration` counter prevents race conditions on rapid song changes
- Timer-based UI sync: 0.1s for playback progress, 0.5s for queue state

## Public Repo

- Remote `public` -> github.com/mlares85/YTBar (GPL v3)
- Default branch: main
- Push via: `git push public public-release:main`
- Bundle ID: com.ytmusicbar.app, LSUIElement: true (menubar-only)
- Unsigned — users must right-click > Open on first launch
