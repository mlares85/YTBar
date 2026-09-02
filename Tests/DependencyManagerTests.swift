import XCTest
@testable import YTBar

final class DependencyManagerTests: XCTestCase {
    private var mockClient: MockDepHTTPClient!
    private var sut: DependencyManager!
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        mockClient = MockDepHTTPClient()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        sut = DependencyManager(
            client: mockClient,
            basePath: tempDir.path
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - isInstalled

    func testNotInstalledWhenBinaryMissing() {
        XCTAssertFalse(sut.isInstalled)
    }

    func testInstalledWhenBinaryExists() throws {
        try createFakeBinary()
        XCTAssertTrue(sut.isInstalled)
    }

    // MARK: - ytdlpPath

    func testYtdlpPathPointsToBinDirectory() {
        let expected = tempDir.path + "/bin/yt-dlp"
        XCTAssertEqual(sut.ytdlpPath, expected)
    }

    // MARK: - GitHub API URL

    func testBuildsCorrectGitHubAPIURL() {
        let url = DependencyManager.latestReleaseURL
        XCTAssertEqual(
            url.absoluteString,
            "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
        )
    }

    // MARK: - Release Parsing

    func testParsesReleaseAssetURL() async throws {
        let assetURL = "https://github.com/yt-dlp/releases/yt-dlp_macos"
        mockClient.result = makeReleaseResponse(assetURL: assetURL)

        let parsed = try DependencyManager.parseAssetURL(
            from: mockClient.result!.0
        )

        XCTAssertEqual(parsed.absoluteString, assetURL)
    }

    func testThrowsWhenAssetNotFound() {
        let json: [String: Any] = ["assets": [
            ["name": "yt-dlp_linux", "browser_download_url": "https://x"],
        ]]
        let data = try! JSONSerialization.data(
            withJSONObject: json
        )

        XCTAssertThrowsError(
            try DependencyManager.parseAssetURL(from: data)
        )
    }

    // MARK: - install

    func testInstallCreatesBinary() async throws {
        let assetURL = "https://github.com/yt-dlp/yt-dlp_macos"
        mockClient.responses = [
            makeReleaseResponse(assetURL: assetURL),
            makeBinaryResponse(),
        ]

        try await sut.install()

        XCTAssertTrue(sut.isInstalled)
        XCTAssertTrue(
            FileManager.default.isExecutableFile(
                atPath: sut.ytdlpPath
            )
        )
    }

    // MARK: - ensureInstalled

    func testEnsureInstalledSkipsIfPresent() async throws {
        try createFakeBinary()
        mockClient.responses = []

        try await sut.ensureInstalled()

        XCTAssertNil(mockClient.lastRequest)
    }

    func testEnsureInstalledInstallsIfMissing() async throws {
        let assetURL = "https://github.com/yt-dlp/yt-dlp_macos"
        mockClient.responses = [
            makeReleaseResponse(assetURL: assetURL),
            makeBinaryResponse(),
        ]

        try await sut.ensureInstalled()

        XCTAssertTrue(sut.isInstalled)
    }

    // MARK: - Version / Age

    func testDaysSinceInstallReturnsMaxWhenMissing() {
        XCTAssertEqual(sut.daysSinceInstall(), Int.max)
    }

    func testDaysSinceInstallReturnsZeroForFreshBinary() throws {
        try createFakeBinary()
        XCTAssertEqual(sut.daysSinceInstall(), 0)
    }

    func testIsOutdatedWhenBinaryMissing() {
        XCTAssertTrue(sut.isOutdated)
    }

    func testIsNotOutdatedForFreshBinary() throws {
        try createFakeBinary()
        XCTAssertFalse(sut.isOutdated)
    }

    func testIsOutdatedForOldBinary() throws {
        try createFakeBinary()
        let old = Date().addingTimeInterval(-91 * 86400)
        try FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: sut.ytdlpPath
        )
        XCTAssertTrue(sut.isOutdated)
    }

    func testEnsureUpToDateUpdatesOutdatedBinary() async throws {
        try createFakeBinary()
        let old = Date().addingTimeInterval(-91 * 86400)
        try FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: sut.ytdlpPath
        )
        let assetURL = "https://github.com/yt-dlp/yt-dlp_macos"
        mockClient.responses = [
            makeReleaseResponse(assetURL: assetURL),
            makeBinaryResponse(),
        ]

        try await sut.ensureUpToDate()

        XCTAssertFalse(sut.isOutdated)
    }

    func testEnsureUpToDateSkipsFreshBinary() async throws {
        try createFakeBinary()
        mockClient.responses = []

        try await sut.ensureUpToDate()

        XCTAssertNil(mockClient.lastRequest)
    }

    // MARK: - Helpers

    private func createFakeBinary() throws {
        let binDir = tempDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(
            at: binDir,
            withIntermediateDirectories: true
        )
        let path = binDir.appendingPathComponent("yt-dlp")
        FileManager.default.createFile(
            atPath: path.path,
            contents: Data("binary".utf8)
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: path.path
        )
    }

    private func makeReleaseResponse(
        assetURL: String
    ) -> (Data, URLResponse) {
        let json: [String: Any] = [
            "assets": [
                [
                    "name": "yt-dlp_macos",
                    "browser_download_url": assetURL,
                ],
                [
                    "name": "yt-dlp_linux",
                    "browser_download_url": "https://other",
                ],
            ]
        ]
        let data = try! JSONSerialization.data(
            withJSONObject: json
        )
        let response = HTTPURLResponse(
            url: URL(string: "https://api.github.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    private func makeBinaryResponse() -> (Data, URLResponse) {
        let data = Data("fake-yt-dlp-binary".utf8)
        let response = HTTPURLResponse(
            url: URL(string: "https://github.com/download")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

// MARK: - Mock

final class MockDepHTTPClient: HTTPClient, @unchecked Sendable {
    var result: (Data, URLResponse)?
    var responses: [(Data, URLResponse)] = []
    var lastRequest: URLRequest?
    var error: Error?
    private var callIndex = 0

    func data(
        for request: URLRequest
    ) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error { throw error }
        if !responses.isEmpty {
            let response = responses[callIndex]
            callIndex += 1
            return response
        }
        return result!
    }
}
