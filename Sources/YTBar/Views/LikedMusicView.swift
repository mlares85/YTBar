import SwiftUI

struct LikedMusicView: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .onAppear { vm.loadLikedIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text("Liked Music")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            refreshLikedButton
            if !vm.likedTracks.isEmpty {
                playAllButton
                shuffleButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var refreshLikedButton: some View {
        Button { vm.refreshLiked() } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11))
                .rotationEffect(.degrees(vm.isLoadingLiked ? 360 : 0))
                .animation(
                    vm.isLoadingLiked ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                    value: vm.isLoadingLiked
                )
        }
        .buttonStyle(.borderless)
        .disabled(vm.isLoadingLiked || !vm.isAuthenticated)
        .accessibilityLabel("Refresh liked music")
        .help("Refresh liked music")
    }

    private var playAllButton: some View {
        Button { playAll(shuffled: false) } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Play all liked music")
        .help("Play all liked music")
    }

    private var shuffleButton: some View {
        Button { playAll(shuffled: true) } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Shuffle liked music")
        .help("Shuffle liked music")
    }

    @ViewBuilder
    private var content: some View {
        if !vm.isAuthenticated {
            signInPrompt
        } else if vm.isLoadingLiked && vm.likedTracks.isEmpty {
            LoadingView(text: "Loading liked music...")
        } else if vm.likedTracks.isEmpty {
            emptyState
        } else {
            trackList
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.slash")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Sign in to see liked music")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Go to Settings to sign in")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "heart")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No liked songs yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var trackList: some View {
        List {
            ForEach(vm.likedTracks) { track in
                TrackRowView(
                    track: track,
                    onPlay: {
                        vm.playFromList(
                            track,
                            in: vm.likedTracks,
                            playlistId: "LM",
                            playlistTitle: "Liked Music"
                        )
                    },
                    onStartRadio: { vm.startRadio(from: track) }
                )
                .listRowInsets(EdgeInsets(
                    top: 2, leading: 8, bottom: 2, trailing: 8
                ))
                .onAppear { maybeLoadMore(currentTrack: track) }
            }
            if vm.isLoadingMoreLiked {
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

    private func maybeLoadMore(currentTrack: Track) {
        guard !vm.isLoadingMoreLiked, vm.likedNextPageToken != nil else { return }
        let threshold = max(0, vm.likedTracks.count - 10)
        guard let idx = vm.likedTracks.firstIndex(of: currentTrack),
              idx >= threshold else { return }
        vm.loadMoreLiked()
    }

    private func playAll(shuffled: Bool) {
        let ordered = shuffled ? vm.likedTracks.shuffled() : vm.likedTracks
        guard let first = ordered.first else { return }
        vm.playFromList(
            first,
            in: ordered,
            playlistId: "LM",
            playlistTitle: "Liked Music"
        )
    }
}
