import SwiftUI

struct TrackRowView: View {
    let track: Track
    let onPlay: () -> Void
    var onAddToQueue: (() -> Void)?
    var onStartRadio: (() -> Void)?

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 10) {
                thumbnail
                trackInfo
                Spacer()
                durationLabel
                actionButtons
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var thumbnail: some View {
        AsyncImage(url: track.thumbnailURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.secondary.opacity(0.2)
        }
        .frame(width: 36, height: 36)
        .cornerRadius(4)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var durationLabel: some View {
        Text(track.durationFormatted)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if let onStartRadio {
                Button(action: onStartRadio) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Start radio from \(track.title)")
                .help("Start radio from this track")
            }

            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Play \(track.title)")
            .help("Play")

            if let onAddToQueue {
                Button(action: onAddToQueue) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add \(track.title) to queue")
                .help("Add to queue")
            }
        }
    }

    private var accessibilityText: String {
        "\(track.title) by \(track.artist), \(track.durationFormatted)"
    }
}

struct PlaylistRowView: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            info
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(playlist.title), \(playlist.trackCount) tracks")
    }

    private var thumbnail: some View {
        AsyncImage(url: playlist.thumbnailURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Image(systemName: "music.note.list")
                .foregroundStyle(.secondary)
        }
        .frame(width: 40, height: 40)
        .cornerRadius(6)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playlist.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text("\(playlist.trackCount) tracks")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

struct LoadingView: View {
    var text: String?

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            if let text {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(text ?? "Loading")
    }
}
