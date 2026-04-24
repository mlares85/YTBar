import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail
            VStack(spacing: 4) {
                trackLabels
                progressSection
                controlsRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .keyboardShortcuts()
    }

    private var thumbnail: some View {
        AsyncImage(url: vm.currentTrack?.thumbnailURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.secondary.opacity(0.2)
        }
        .frame(width: 100, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityHidden(true)
    }

    private var trackLabels: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(vm.currentTrack?.title ?? "Not Playing")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(vm.currentTrack?.artist ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var progressSection: some View {
        VStack(spacing: 2) {
            ProgressSlider(value: $vm.progress, max: vm.duration) { vm.seek(to: $0) }
            timeLabels
        }
    }

    private var timeLabels: some View {
        HStack {
            Text(vm.progressFormatted)
            Spacer()
            Text(vm.durationFormatted)
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            previousButton
            playPauseButton
            nextButton
            Spacer(minLength: 4)
            repeatButton
            shuffleButton
            likeButton
            radioButton
            lyricsButton
            volumeSlider
        }
    }

    private var lyricsButton: some View {
        Button { vm.toggleLyrics() } label: {
            Image(systemName: "text.quote")
                .font(.system(size: 12))
                .foregroundStyle(vm.showLyrics ? Color.accentColor : .primary)
        }
        .buttonStyle(.borderless)
        .disabled(vm.currentTrack == nil)
        .accessibilityLabel(vm.showLyrics ? "Hide lyrics" : "Show lyrics")
        .help(vm.showLyrics ? "Hide lyrics" : "Show lyrics")
    }

    private var likeButton: some View {
        Button { vm.toggleLike() } label: {
            Image(systemName: vm.isLiked ? "heart.fill" : "heart")
                .font(.system(size: 12))
                .foregroundStyle(vm.isLiked ? Color.red : .primary)
        }
        .buttonStyle(.borderless)
        .disabled(vm.currentTrack == nil || !vm.isAuthenticated || vm.isTogglingLike)
        .accessibilityLabel(vm.isLiked ? "Unlike song" : "Like song")
        .help(vm.isLiked ? "Unlike song" : "Like song")
    }

    private var radioButton: some View {
        Button {
            guard let track = vm.currentTrack else { return }
            vm.startRadio(from: track)
        } label: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 12))
        }
        .buttonStyle(.borderless)
        .disabled(vm.currentTrack == nil)
        .accessibilityLabel("Start radio from current track")
        .help("Start radio from current track")
    }

    private var shuffleButton: some View {
        Button(action: vm.toggleShuffle) {
            Image(systemName: "shuffle")
                .font(.system(size: 11))
                .foregroundStyle(vm.isShuffled ? Color.accentColor : .primary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(vm.isShuffled ? "Shuffle on" : "Shuffle off")
        .help(vm.isShuffled ? "Turn off shuffle" : "Turn on shuffle")
    }

    private var previousButton: some View {
        Button(action: vm.previous) {
            Image(systemName: "backward.fill")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Previous track")
        .help("Previous track (⌘←)")
    }

    private var playPauseButton: some View {
        Button(action: vm.togglePlayPause) {
            Image(systemName: playPauseIcon)
                .font(.system(size: 18))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(playPauseLabel)
        .help("\(playPauseLabel) (Space)")
    }

    private var nextButton: some View {
        Button(action: vm.next) {
            Image(systemName: "forward.fill")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Next track")
        .help("Next track (⌘→)")
    }

    private var repeatButton: some View {
        Button(action: vm.cycleRepeatMode) {
            Image(systemName: repeatIcon)
                .font(.system(size: 11))
                .foregroundStyle(vm.repeatMode != .off ? Color.accentColor : .primary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(repeatLabel)
        .help(repeatLabel)
    }

    private var repeatIcon: String {
        switch vm.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private var repeatLabel: String {
        switch vm.repeatMode {
        case .off: return "Repeat off"
        case .all: return "Repeat all"
        case .one: return "Repeat one"
        }
    }

    private var volumeSlider: some View {
        HStack(spacing: 4) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Slider(value: $vm.volume, in: 0...1)
                .frame(width: 54)
                .accessibilityLabel("Volume")
                .help("Volume")
                .onChange(of: vm.volume) { _, val in vm.setVolume(val) }
        }
    }

    private var playPauseIcon: String {
        vm.playerState == .playing ? "pause.fill" : "play.fill"
    }

    private var playPauseLabel: String {
        vm.playerState == .playing ? "Pause" : "Play"
    }
}

private struct ProgressSlider: View {
    @Binding var value: Double
    let max: Double
    let onSeek: (Double) -> Void

    var body: some View {
        Slider(value: $value, in: 0...Swift.max(max, 1)) { editing in
            if !editing { onSeek(value) }
        }
        .controlSize(.mini)
        .accessibilityLabel("Playback progress")
    }
}

private extension View {
    func keyboardShortcuts() -> some View {
        self
            .background(KeyboardShortcutHandlers())
    }
}

private struct KeyboardShortcutHandlers: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        Group {
            Button("", action: vm.togglePlayPause)
                .keyboardShortcut(.space, modifiers: [])
            Button("", action: vm.next)
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("", action: vm.previous)
                .keyboardShortcut(.leftArrow, modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
