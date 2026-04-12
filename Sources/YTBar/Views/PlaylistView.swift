import SwiftUI

struct PlaylistView: View {
    let playlist: Playlist
    let onBack: () -> Void

    @EnvironmentObject private var vm: AppViewModel
    @State private var tracks: [Track] = []
    @State private var isLoading = true
    @State private var isDownloading = false
    @State private var nextPageToken: String?
    @State private var isLoadingMore = false
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            trackListContent
        }
        .task { await loadTracks() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            headerNav
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var headerNav: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12))
                    Text("Library")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Back to library")
            .help("Back to library")
            Spacer()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Text(playlist.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Spacer()
            refreshButton
            keepOfflineButton
            playAllButton
            shuffleButton
        }
    }

    private var refreshButton: some View {
        Button { refreshPlaylist() } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16))
                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                .animation(
                    isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: isRefreshing
                )
        }
        .buttonStyle(.borderless)
        .disabled(isRefreshing)
        .accessibilityLabel("Refresh playlist")
        .help("Refresh playlist")
    }

    private var playAllButton: some View {
        Button { playAll(shuffled: false) } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 16))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Play all")
        .help("Play all")
    }

    private var shuffleButton: some View {
        Button { playAll(shuffled: true) } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 16))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Shuffle play")
        .help("Shuffle play")
    }

    private var keepOfflineButton: some View {
        Button { startOfflineDownload() } label: {
            Image(systemName: offlineIcon)
                .font(.system(size: 16))
                .foregroundStyle(offlineColor)
        }
        .buttonStyle(.borderless)
        .disabled(tracks.isEmpty || isDownloading)
        .accessibilityLabel("Keep playlist offline")
        .help("Download tracks for offline play")
    }

    private var offlineIcon: String {
        let cached = vm.cachedCount(tracks: tracks)
        if cached == tracks.count && !tracks.isEmpty {
            return "arrow.down.circle.fill"
        }
        return isDownloading
            ? "arrow.down.circle.dotted"
            : "arrow.down.circle"
    }

    private var offlineColor: Color {
        let cached = vm.cachedCount(tracks: tracks)
        if cached == tracks.count && !tracks.isEmpty {
            return .green
        }
        return .primary
    }

    private func startOfflineDownload() {
        isDownloading = true
        vm.keepOffline(tracks: tracks)
    }

    @ViewBuilder
    private var trackListContent: some View {
        if isLoading {
            LoadingView(text: "Loading tracks...")
        } else {
            trackList
        }
    }

    private var trackList: some View {
        List {
            ForEach(tracks) { track in
                TrackRowView(
                    track: track,
                    onPlay: {
                        vm.playFromList(
                            track,
                            in: tracks,
                            playlistId: playlist.id,
                            playlistTitle: playlist.title
                        )
                    },
                    onStartRadio: { vm.startRadio(from: track) }
                )
                .listRowInsets(EdgeInsets(
                    top: 2, leading: 8, bottom: 2, trailing: 8
                ))
                .onAppear { maybeLoadMore(currentTrack: track) }
            }
            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private func loadTracks() async {
        defer { isLoading = false }
        guard let page = try? await vm.onFetchPlaylistPage?(playlist.id, nil) else {
            return
        }
        tracks = page.0
        nextPageToken = page.1
    }

    private func maybeLoadMore(currentTrack: Track) {
        guard !isLoadingMore, let token = nextPageToken else { return }
        let threshold = max(0, tracks.count - 10)
        guard let idx = tracks.firstIndex(of: currentTrack), idx >= threshold else { return }
        isLoadingMore = true
        Task { await loadMore(token: token) }
    }

    private func loadMore(token: String) async {
        defer { isLoadingMore = false }
        guard let page = try? await vm.onFetchPlaylistPage?(playlist.id, token) else {
            return
        }
        tracks.append(contentsOf: page.0)
        nextPageToken = page.1
    }

    private func refreshPlaylist() {
        isRefreshing = true
        tracks = []
        nextPageToken = nil
        Task {
            defer { isRefreshing = false }
            await loadTracks()
        }
    }

    private func playAll(shuffled: Bool) {
        let ordered = shuffled ? tracks.shuffled() : tracks
        guard let first = ordered.first else { return }
        vm.playFromList(
            first,
            in: ordered,
            playlistId: playlist.id,
            playlistTitle: playlist.title
        )
    }
}
