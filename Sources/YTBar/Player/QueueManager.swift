import Foundation
import Combine

final class QueueManager: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var repeatMode: RepeatMode = .off
    @Published var isShuffled: Bool = false
    /// Index of the first track that was auto-appended by the radio-extend
    /// workflow. Tracks before this index are the "original" queue; tracks
    /// from this index onward are auto-added. nil when the queue has not
    /// been extended (or after the user merges the extensions into a
    /// playlist).
    @Published var autoExtendStartIndex: Int?

    private var shuffleOrder: [Int] = []
    private var shufflePosition: Int = 0
    private var originalTracks: [Track] = []

    var currentTrack: Track? {
        guard !tracks.isEmpty, currentIndex < tracks.count else { return nil }
        return isShuffled ? tracks[shuffleOrder[shufflePosition]] : tracks[currentIndex]
    }

    func add(_ track: Track) {
        tracks.append(track)
    }

    func addNext(_ track: Track) {
        let insertAt = tracks.isEmpty ? 0 : currentIndex + 1
        tracks.insert(track, at: insertAt)
        if let divider = autoExtendStartIndex, insertAt <= divider {
            autoExtendStartIndex = divider + 1
        }
    }

    /// Appends tracks returned by the radio-extend workflow. If this is the
    /// first extension, records the boundary index so the queue view can
    /// render a divider between the original queue and the new tracks.
    func appendAutoExtended(_ newTracks: [Track]) {
        guard !newTracks.isEmpty else { return }
        if autoExtendStartIndex == nil {
            autoExtendStartIndex = tracks.count
        }
        tracks.append(contentsOf: newTracks)
    }

    /// Clears the divider. Called after the user appends the auto-extended
    /// tracks to the source playlist — the tracks then merge conceptually
    /// into the "original" section.
    func clearAutoExtendDivider() {
        autoExtendStartIndex = nil
    }

    /// Reorders tracks in the queue. The currently-playing index is
    /// updated to follow the current track to its new position (matched
    /// by track id; first match wins on duplicates).
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard !source.isEmpty else { return }
        let currentId = currentTrack?.id
        tracks.move(fromOffsets: source, toOffset: destination)
        if let id = currentId,
           let newIdx = tracks.firstIndex(where: { $0.id == id }) {
            currentIndex = newIdx
        }
    }

    func next() -> Track? {
        guard !tracks.isEmpty else { return nil }
        if repeatMode == .one { return currentTrack }
        if isShuffled { return nextShuffled() }
        return nextSequential()
    }

    func previous() -> Track? {
        guard !tracks.isEmpty else { return nil }
        if repeatMode == .one { return currentTrack }
        if isShuffled { return previousShuffled() }
        return previousSequential()
    }

    func clear() {
        tracks = []
        currentIndex = 0
        shuffleOrder = []
        shufflePosition = 0
        isShuffled = false
        autoExtendStartIndex = nil
    }

    func remove(at index: Int) {
        guard index >= 0, index < tracks.count else { return }
        tracks.remove(at: index)
        adjustIndexAfterRemoval(removedIndex: index)
        adjustDividerAfterRemoval(removedIndex: index)
    }

    func setPlaylist(_ newTracks: [Track], startAt: Int) {
        tracks = newTracks
        currentIndex = min(startAt, max(newTracks.count - 1, 0))
        isShuffled = false
        shuffleOrder = []
        autoExtendStartIndex = nil
    }

    func toggleShuffle() {
        if isShuffled {
            unshuffle()
        } else {
            shuffle()
        }
        // The divider is meaningless in shuffled order; drop it either way.
        autoExtendStartIndex = nil
    }
}

// MARK: - Sequential Navigation

private extension QueueManager {
    func nextSequential() -> Track? {
        if currentIndex + 1 < tracks.count {
            currentIndex += 1
            return tracks[currentIndex]
        }
        guard repeatMode == .all else { return nil }
        currentIndex = 0
        return tracks[currentIndex]
    }

    func previousSequential() -> Track? {
        if currentIndex - 1 >= 0 {
            currentIndex -= 1
            return tracks[currentIndex]
        }
        guard repeatMode == .all else { return nil }
        currentIndex = tracks.count - 1
        return tracks[currentIndex]
    }
}

// MARK: - Shuffle Navigation

private extension QueueManager {
    func shuffle() {
        originalTracks = tracks
        shuffleOrder = Array(0..<tracks.count).shuffled()
        shufflePosition = shuffleOrder.firstIndex(of: currentIndex) ?? 0
        isShuffled = true
    }

    func unshuffle() {
        let current = currentTrack
        tracks = originalTracks
        isShuffled = false
        if let c = current { currentIndex = tracks.firstIndex(of: c) ?? 0 }
    }

    func nextShuffled() -> Track? {
        if shufflePosition + 1 < shuffleOrder.count {
            shufflePosition += 1
            return tracks[shuffleOrder[shufflePosition]]
        }
        guard repeatMode == .all else { return nil }
        shufflePosition = 0
        return tracks[shuffleOrder[shufflePosition]]
    }

    func previousShuffled() -> Track? {
        if shufflePosition - 1 >= 0 {
            shufflePosition -= 1
            return tracks[shuffleOrder[shufflePosition]]
        }
        guard repeatMode == .all else { return nil }
        shufflePosition = shuffleOrder.count - 1
        return tracks[shuffleOrder[shufflePosition]]
    }
}

// MARK: - Index Adjustment

private extension QueueManager {
    func adjustIndexAfterRemoval(removedIndex: Int) {
        guard !tracks.isEmpty else { currentIndex = 0; return }
        if removedIndex < currentIndex {
            currentIndex -= 1
        } else if currentIndex >= tracks.count {
            currentIndex = tracks.count - 1
        }
    }

    func adjustDividerAfterRemoval(removedIndex: Int) {
        guard let divider = autoExtendStartIndex else { return }
        if removedIndex < divider {
            autoExtendStartIndex = divider - 1
        }
        // If the removal left no auto-extended tracks, drop the divider.
        if let d = autoExtendStartIndex, d >= tracks.count {
            autoExtendStartIndex = nil
        }
    }
}
