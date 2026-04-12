import XCTest
@testable import YTBar

// MARK: - Mock

final class MockAVPlayerEngine: AudioPlayerEngine {
    var playCallCount = 0
    var pauseCallCount = 0
    var stopCallCount = 0
    var loadedURL: URL?
    var seekTarget: Double?
    var currentVolume: Float = 1.0
    var simulatedStatus: AudioEngineStatus = .unknown
    var onStatusChange: ((AudioEngineStatus) -> Void)?
    var onFinished: (() -> Void)?
    var onTimeUpdate: ((Double, Double) -> Void)?

    func load(url: URL) {
        loadedURL = url
        onStatusChange?(.readyToPlay)
    }

    func play() { playCallCount += 1 }
    func pause() { pauseCallCount += 1 }

    func stop() {
        stopCallCount += 1
        loadedURL = nil
    }

    func seek(to fraction: Double) {
        seekTarget = fraction
    }

    func setVolume(_ vol: Float) {
        currentVolume = vol
    }

    func simulateFinished() { onFinished?() }
}

// MARK: - Tests

final class AudioPlayerTests: XCTestCase {
    private var sut: AudioPlayer!
    private var engine: MockAVPlayerEngine!

    override func setUp() {
        super.setUp()
        engine = MockAVPlayerEngine()
        sut = AudioPlayer(engine: engine)
    }

    override func tearDown() {
        sut = nil
        engine = nil
        super.tearDown()
    }

    private var testURL: URL {
        URL(string: "https://example.com/audio.mp3")!
    }

    // MARK: - State Transitions

    func testInitialStateIsIdle() {
        XCTAssertEqual(sut.state, .idle)
    }

    func testLoadTransitionsToLoading() {
        sut.load(url: testURL)
        XCTAssertEqual(engine.loadedURL, testURL)
    }

    func testPlayUpdatesState() {
        sut.load(url: testURL)
        sut.play()

        XCTAssertEqual(sut.state, .playing)
        XCTAssertEqual(engine.playCallCount, 1)
    }

    func testPauseUpdatesState() {
        sut.load(url: testURL)
        sut.play()
        sut.pause()

        XCTAssertEqual(sut.state, .paused)
        XCTAssertEqual(engine.pauseCallCount, 1)
    }

    func testStopResetsState() {
        sut.load(url: testURL)
        sut.play()
        sut.stop()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertEqual(engine.stopCallCount, 1)
    }

    // MARK: - Volume

    func testVolumeClampedToRange() {
        sut.setVolume(1.5)
        XCTAssertEqual(sut.volume, 1.0)

        sut.setVolume(-0.5)
        XCTAssertEqual(sut.volume, 0.0)

        sut.setVolume(0.7)
        XCTAssertEqual(sut.volume, 0.7)
    }

    func testVolumeForwardedToEngine() {
        sut.setVolume(0.5)
        XCTAssertEqual(engine.currentVolume, 0.5)
    }

    // MARK: - Seek

    func testSeekForwardedToEngine() {
        sut.load(url: testURL)
        sut.play()
        sut.seek(to: 0.5)

        XCTAssertEqual(engine.seekTarget, 0.5)
    }

    // MARK: - Track Completion

    func testTrackFinishedCallbackFires() {
        let exp = expectation(description: "finished")
        sut.onTrackFinished = { exp.fulfill() }

        sut.load(url: testURL)
        sut.play()
        engine.simulateFinished()

        wait(for: [exp], timeout: 1.0)
    }

    // MARK: - Load Resets State

    func testLoadNewTrackResetsProgress() {
        sut.load(url: testURL)
        sut.play()
        sut.load(url: URL(string: "https://example.com/b.mp3")!)

        XCTAssertEqual(sut.progress, 0.0)
        XCTAssertEqual(sut.currentTime, 0.0)
    }
}
