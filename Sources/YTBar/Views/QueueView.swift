import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var vm: AppViewModel
    var onClose: (() -> Void)? = nil
    @State private var showNamePrompt = false
    @State private var playlistName = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            queueContent
        }
        .alert("Save Queue as Playlist", isPresented: $showNamePrompt) {
            TextField("Playlist name", text: $playlistName)
            Button("Save") { savePlaylist() }
            Button("Cancel", role: .cancel) { playlistName = "" }
        } message: {
            if vm.queueIsFromExistingPlaylist {
                Text("This queue was loaded from an existing playlist. Enter a name to save a copy.")
            } else {
                Text("Enter a name for the new playlist.")
            }
        }
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                Text("Up Next")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if !vm.queueTracks.isEmpty {
                    saveButton
                }
                if vm.canAppendAutoExtendedToPlaylist {
                    appendToPlaylistButton
                }
                Text("\(vm.queueTracks.count) tracks")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            centerPlaylistTitle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var appendToPlaylistButton: some View {
        Button { vm.appendAutoExtendedToSourcePlaylist() } label: {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .disabled(vm.isAppendingToPlaylist)
        .accessibilityLabel("Add new radio tracks to source playlist")
        .help(appendButtonTooltip)
    }

    private var appendButtonTooltip: String {
        let count = vm.autoExtendedTracks.count
        let name = vm.queueSourcePlaylistTitle ?? "playlist"
        return "Add \(count) auto-added track\(count == 1 ? "" : "s") to \(name)"
    }

    @ViewBuilder
    private var centerPlaylistTitle: some View {
        if let title = vm.queueSourcePlaylistTitle, !title.isEmpty {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200)
                .allowsHitTesting(false)
                .accessibilityLabel("Playing from \(title)")
        }
    }

    private var saveButton: some View {
        Button { showNamePrompt = true } label: {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 11))
        }
        .buttonStyle(.borderless)
        .disabled(!vm.isAuthenticated || vm.isSavingPlaylist)
        .accessibilityLabel("Save queue as playlist")
        .help(saveButtonTooltip)
    }

    private var saveButtonTooltip: String {
        if vm.queueIsFromExistingPlaylist {
            return "Queue is from an existing playlist"
        }
        return "Save queue as a new playlist"
    }

    @ViewBuilder
    private var queueContent: some View {
        if vm.queueTracks.isEmpty {
            emptyQueue
        } else {
            queueList
        }
    }

    private var emptyQueue: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Queue is empty")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queueList: some View {
        List {
            ForEach(Array(0..<originalSectionEnd), id: \.self) { idx in
                trackRow(idx: idx, track: vm.queueTracks[idx])
            }
            .onMove(perform: moveOriginalSection)

            if hasRadioSection {
                radioDividerRow
                ForEach(Array(radioSectionStart..<vm.queueTracks.count), id: \.self) { idx in
                    trackRow(idx: idx, track: vm.queueTracks[idx])
                }
                .onMove(perform: moveRadioSection)
            }
        }
        .listStyle(.plain)
    }

    private var originalSectionEnd: Int {
        vm.autoExtendStartIndex ?? vm.queueTracks.count
    }

    private var radioSectionStart: Int {
        vm.autoExtendStartIndex ?? vm.queueTracks.count
    }

    private var hasRadioSection: Bool {
        guard let d = vm.autoExtendStartIndex else { return false }
        return d < vm.queueTracks.count
    }

    private func moveOriginalSection(from source: IndexSet, to destination: Int) {
        // Offsets are already absolute (section starts at 0).
        vm.moveQueueItems(from: source, to: destination)
    }

    private func moveRadioSection(from source: IndexSet, to destination: Int) {
        let offset = radioSectionStart
        let absSource = IndexSet(source.map { $0 + offset })
        let absDest = destination + offset
        vm.moveQueueItems(from: absSource, to: absDest)
    }

    private func trackRow(idx: Int, track: Track) -> some View {
        HStack(spacing: 6) {
            grabHandle
            indexColumn(idx: idx)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 12, weight: idx == vm.queueIndex ? .semibold : .regular))
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(track.durationFormatted)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            vm.playFromQueue(at: idx)
        }
    }

    private var grabHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 12)
            .accessibilityHidden(true)
            .help("Drag to reorder")
    }

    private var radioDividerRow: some View {
        HStack(spacing: 6) {
            VStack { Divider() }
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text("Radio mix")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Start of auto-added radio tracks")
            VStack { Divider() }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func indexColumn(idx: Int) -> some View {
        if idx == vm.queueIndex {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
                .frame(width: 16)
        } else {
            Text("\(idx + 1)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 16)
        }
    }

    private func savePlaylist() {
        let name = playlistName.trimmingCharacters(in: .whitespaces)
        playlistName = ""
        guard !name.isEmpty else { return }
        vm.saveQueueAsPlaylist(name: name)
    }
}
