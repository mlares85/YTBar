import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var selectedPlaylist: Playlist?
    @State private var hasFetched = false

    var body: some View {
        Group {
            if let playlist = selectedPlaylist {
                PlaylistView(playlist: playlist) {
                    selectedPlaylist = nil
                }
            } else {
                libraryContent
            }
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if !vm.isAuthenticated {
            signInPrompt
        } else if vm.isLoadingLibrary {
            LoadingView(text: "Loading library...")
        } else if vm.playlists.isEmpty && !hasFetched {
            LoadingView(text: "Loading library...")
                .onAppear {
                    hasFetched = true
                    vm.fetchLibrary()
                }
        } else if vm.playlists.isEmpty {
            emptyLibrary
        } else {
            playlistList
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Sign in to see your library")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text("Go to Settings to sign in")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyLibrary: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No playlists yet")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playlistList: some View {
        List(vm.playlists) { playlist in
            Button { selectedPlaylist = playlist } label: {
                PlaylistRowView(playlist: playlist)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        }
        .listStyle(.plain)
        .refreshable { vm.fetchLibrary() }
    }
}
