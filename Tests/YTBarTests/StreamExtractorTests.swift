import XCTest
@testable import YTBar

final class StreamExtractorTests: XCTestCase {
    private var mockShell: MockShellExecutor!
    private var sut: StreamExtractor!

    override func setUp() {
        super.setUp()
        mockShell = MockShellExecutor()
        sut = StreamExtractor(
            shell: mockShell,
            ytdlpPath: "/usr/local/bin/yt-dlp"
        )
    }

    // MARK: - extractStreamURL

    func testExtractsAudioURLFromOutput() async throws {
        let url = "https://rr.googlevideo.com/audio.m4a"
        mockShell.output = url + "\n"

        let result = try await sut.extractStreamURL(videoId: "abc123")
        XCTAssertEqual(result.absoluteString, url)
    }

    func testThrowsOnNonZeroExit() async {
        mockShell.error = ShellError.nonZeroExit(1, "error")

        do {
            _ = try await sut.extractStreamURL(videoId: "abc123")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is ShellError)
        }
    }

    func testThrowsOnEmptyOutput() async {
        mockShell.output = ""

        do {
            _ = try await sut.extractStreamURL(videoId: "abc123")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is StreamExtractorError)
        }
    }

    func testBuildsCorrectCommand() async throws {
        let url = "https://rr.googlevideo.com/audio.m4a"
        mockShell.output = url + "\n"

        _ = try await sut.extractStreamURL(videoId: "dQw4w9WgXcQ")

        XCTAssertEqual(mockShell.lastBinary, "/usr/local/bin/yt-dlp")
        let args = mockShell.lastArgs!
        XCTAssertTrue(args.contains("--get-url"))
        XCTAssertTrue(args.contains("-f"))
        XCTAssertTrue(
            args.contains("bestaudio[ext=m4a]/bestaudio")
        )
        XCTAssertTrue(args.contains(
            "https://music.youtube.com/watch?v=dQw4w9WgXcQ"
        ))
    }

    func testIncludesCookiesArgWhenProvided() async throws {
        let url = "https://rr.googlevideo.com/audio.m4a"
        mockShell.output = url + "\n"

        _ = try await sut.extractStreamURL(
            videoId: "abc123",
            cookiesPath: "/tmp/cookies.txt"
        )

        let args = mockShell.lastArgs!
        XCTAssertTrue(args.contains("--cookies"))
        XCTAssertTrue(args.contains("/tmp/cookies.txt"))
    }

    func testNoCookiesArgWhenNotProvided() async throws {
        let url = "https://rr.googlevideo.com/audio.m4a"
        mockShell.output = url + "\n"

        _ = try await sut.extractStreamURL(videoId: "abc123")

        let args = mockShell.lastArgs!
        XCTAssertFalse(args.contains("--cookies"))
    }

    // MARK: - extractStreamInfo

    func testParsesStreamInfoFromJSON() async throws {
        mockShell.output = makeDumpJSON(
            url: "https://rr.googlevideo.com/audio.m4a",
            format: "m4a",
            bitrate: 128000
        )

        let info = try await sut.extractStreamInfo(
            videoId: "abc123"
        )

        XCTAssertEqual(
            info.url.absoluteString,
            "https://rr.googlevideo.com/audio.m4a"
        )
        XCTAssertEqual(info.format, "m4a")
        XCTAssertEqual(info.bitrate, 128000)
    }

    func testStreamInfoUseDumpJSONFlag() async throws {
        mockShell.output = makeDumpJSON(
            url: "https://example.com/a.m4a",
            format: "m4a",
            bitrate: 256000
        )

        _ = try await sut.extractStreamInfo(videoId: "xyz")

        let args = mockShell.lastArgs!
        XCTAssertTrue(args.contains("--dump-json"))
        XCTAssertFalse(args.contains("--get-url"))
    }

    // MARK: - Helpers

    private func makeDumpJSON(
        url: String,
        format: String,
        bitrate: Int
    ) -> String {
        """
        {"url":"\(url)","ext":"\(format)","abr":\(bitrate)}
        """
    }
}

// MARK: - Mock Shell

final class MockShellExecutor: ShellExecutor, @unchecked Sendable {
    var output: String = ""
    var error: Error?
    var lastBinary: String?
    var lastArgs: [String]?

    func run(
        binary: String,
        args: [String]
    ) async throws -> String {
        lastBinary = binary
        lastArgs = args
        if let error { throw error }
        return output
    }
}
