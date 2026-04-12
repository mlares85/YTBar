import XCTest
@testable import YTBar

final class QueueManagerTests: XCTestCase {
    private var sut: QueueManager!

    override func setUp() {
        super.setUp()
        sut = QueueManager()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTrack(_ id: String = "1") -> Track {
        Track(
            id: id, title: "Track \(id)", artist: "Artist",
            album: nil, durationSeconds: 180, thumbnailURL: nil
        )
    }

    private func makeTracks(_ count: Int) -> [Track] {
        (1...count).map { makeTrack("\($0)") }
    }

    // MARK: - Add Tracks

    func testAddTrackAppendsToQueue() {
        sut.add(makeTrack("1"))
        sut.add(makeTrack("2"))

        XCTAssertEqual(sut.tracks.count, 2)
        XCTAssertEqual(sut.tracks[0].id, "1")
        XCTAssertEqual(sut.tracks[1].id, "2")
    }

    func testAddNextInsertsAfterCurrent() {
        sut.setPlaylist(makeTracks(3), startAt: 0)
        sut.addNext(makeTrack("99"))

        XCTAssertEqual(sut.tracks[1].id, "99")
        XCTAssertEqual(sut.tracks.count, 4)
    }

    func testAddNextOnEmptyQueueAddsFirst() {
        sut.addNext(makeTrack("1"))

        XCTAssertEqual(sut.tracks.count, 1)
        XCTAssertEqual(sut.tracks[0].id, "1")
    }

    // MARK: - Navigation

    func testNextTrackAdvances() {
        sut.setPlaylist(makeTracks(3), startAt: 0)
        let next = sut.next()

        XCTAssertEqual(next?.id, "2")
        XCTAssertEqual(sut.currentIndex, 1)
    }

    func testPreviousTrackGoesBack() {
        sut.setPlaylist(makeTracks(3), startAt: 2)
        let prev = sut.previous()

        XCTAssertEqual(prev?.id, "2")
        XCTAssertEqual(sut.currentIndex, 1)
    }

    func testNextOnEmptyQueueReturnsNil() {
        XCTAssertNil(sut.next())
    }

    func testPreviousOnEmptyQueueReturnsNil() {
        XCTAssertNil(sut.previous())
    }

    func testPreviousAtStartReturnsNil() {
        sut.setPlaylist(makeTracks(3), startAt: 0)
        XCTAssertNil(sut.previous())
    }

    // MARK: - Current Track

    func testCurrentTrackReturnsCorrectTrack() {
        sut.setPlaylist(makeTracks(3), startAt: 1)
        XCTAssertEqual(sut.currentTrack?.id, "2")
    }

    func testCurrentTrackNilWhenEmpty() {
        XCTAssertNil(sut.currentTrack)
    }

    // MARK: - Repeat Off

    func testRepeatOffStopsAtEnd() {
        sut.setPlaylist(makeTracks(2), startAt: 1)
        sut.repeatMode = .off

        XCTAssertNil(sut.next())
        XCTAssertEqual(sut.currentIndex, 1)
    }

    // MARK: - Repeat All

    func testRepeatAllLoopsToBeginning() {
        sut.setPlaylist(makeTracks(3), startAt: 2)
        sut.repeatMode = .all
        let next = sut.next()

        XCTAssertEqual(next?.id, "1")
        XCTAssertEqual(sut.currentIndex, 0)
    }

    func testRepeatAllPreviousLoopsToEnd() {
        sut.setPlaylist(makeTracks(3), startAt: 0)
        sut.repeatMode = .all
        let prev = sut.previous()

        XCTAssertEqual(prev?.id, "3")
        XCTAssertEqual(sut.currentIndex, 2)
    }

    // MARK: - Repeat One

    func testRepeatOneReplaysSameTrack() {
        sut.setPlaylist(makeTracks(3), startAt: 1)
        sut.repeatMode = .one
        let next = sut.next()

        XCTAssertEqual(next?.id, "2")
        XCTAssertEqual(sut.currentIndex, 1)
    }

    // MARK: - Shuffle

    func testShuffleCreatesShuffleOrder() {
        sut.setPlaylist(makeTracks(10), startAt: 0)
        sut.toggleShuffle()

        XCTAssertTrue(sut.isShuffled)
    }

    func testUnshuffleRestoresOriginalOrder() {
        let tracks = makeTracks(5)
        sut.setPlaylist(tracks, startAt: 0)
        sut.toggleShuffle()
        sut.toggleShuffle()

        XCTAssertFalse(sut.isShuffled)
        XCTAssertEqual(sut.tracks, tracks)
    }

    func testShuffledNextUsesShuffleOrder() {
        sut.setPlaylist(makeTracks(20), startAt: 0)
        sut.toggleShuffle()

        var ids: [String] = [sut.currentTrack!.id]
        for _ in 0..<19 {
            guard let t = sut.next() else { break }
            ids.append(t.id)
        }
        let sequential = (1...20).map { "\($0)" }
        // Shuffle should produce a different order (with high probability)
        XCTAssertNotEqual(ids, sequential)
    }

    // MARK: - Clear

    func testClearRemovesAllTracks() {
        sut.setPlaylist(makeTracks(5), startAt: 2)
        sut.clear()

        XCTAssertTrue(sut.tracks.isEmpty)
        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertNil(sut.currentTrack)
    }

    // MARK: - Remove

    func testRemoveTrackFromQueue() {
        sut.setPlaylist(makeTracks(3), startAt: 0)
        sut.remove(at: 1)

        XCTAssertEqual(sut.tracks.count, 2)
        XCTAssertEqual(sut.tracks[1].id, "3")
    }

    func testRemoveBeforeCurrentAdjustsIndex() {
        sut.setPlaylist(makeTracks(3), startAt: 2)
        sut.remove(at: 0)

        XCTAssertEqual(sut.currentIndex, 1)
        XCTAssertEqual(sut.currentTrack?.id, "3")
    }

    func testRemoveCurrentTrackKeepsIndex() {
        sut.setPlaylist(makeTracks(3), startAt: 1)
        sut.remove(at: 1)

        XCTAssertEqual(sut.currentIndex, 1)
        XCTAssertEqual(sut.currentTrack?.id, "3")
    }

    func testRemoveLastWhenCurrentClampsIndex() {
        sut.setPlaylist(makeTracks(2), startAt: 1)
        sut.remove(at: 1)

        XCTAssertEqual(sut.currentIndex, 0)
        XCTAssertEqual(sut.currentTrack?.id, "1")
    }

    func testRemoveInvalidIndexDoesNothing() {
        sut.setPlaylist(makeTracks(2), startAt: 0)
        sut.remove(at: 5)

        XCTAssertEqual(sut.tracks.count, 2)
    }

    // MARK: - SetPlaylist

    func testSetPlaylistReplacesQueue() {
        sut.add(makeTrack("old"))
        let newTracks = makeTracks(3)
        sut.setPlaylist(newTracks, startAt: 1)

        XCTAssertEqual(sut.tracks, newTracks)
        XCTAssertEqual(sut.currentIndex, 1)
    }

    func testSetPlaylistClampsStartIndex() {
        sut.setPlaylist(makeTracks(3), startAt: 10)
        XCTAssertEqual(sut.currentIndex, 2)
    }
}
