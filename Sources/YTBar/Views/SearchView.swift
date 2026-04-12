import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultsContent
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            // Bind directly to the view model so the query (and its results)
            // survive navigating away from the Search tab. Without this the
            // query was local @State and got wiped every time SwiftUI
            // unmounted SearchView.
            TextField("Search YouTube Music", text: $vm.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .accessibilityLabel("Search")
                .onChange(of: vm.searchQuery) { _, newValue in
                    vm.search(newValue)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var resultsContent: some View {
        if vm.isSearching {
            LoadingView(text: "Searching...")
        } else if vm.searchQuery.isEmpty {
            emptyState
        } else if vm.searchResults.isEmpty {
            noResultsState
        } else {
            resultsList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Search YouTube Music")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Search YouTube Music to find tracks")
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No results found")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultsList: some View {
        List(vm.searchResults) { track in
            TrackRowView(
                track: track,
                onPlay: { vm.playWithRadio(track) },
                onAddToQueue: { vm.addToQueue(track) },
                onStartRadio: { vm.startRadio(from: track) }
            )
            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        }
        .listStyle(.plain)
    }
}
