import XCTest
@testable import YTBar

final class KeychainHelperTests: XCTestCase {
    private var sut: KeychainHelper!

    override func setUp() {
        super.setUp()
        sut = KeychainHelper(service: "com.ytbar.auth.test")
        sut.delete()
    }

    override func tearDown() {
        sut.delete()
        super.tearDown()
    }

    func testRetrieveReturnsNilWhenEmpty() {
        XCTAssertNil(sut.retrieve())
    }

    func testSaveAndRetrieveTokens() throws {
        let tokens = makeTokens()
        try sut.save(tokens)

        let retrieved = sut.retrieve()
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.accessToken, tokens.accessToken)
        XCTAssertEqual(retrieved?.refreshToken, tokens.refreshToken)
    }

    func testDeleteRemovesTokens() throws {
        try sut.save(makeTokens())
        sut.delete()
        XCTAssertNil(sut.retrieve())
    }

    func testOverwriteExistingTokens() throws {
        try sut.save(makeTokens())

        let updated = makeTokens(
            access: "new-access",
            refresh: "new-refresh"
        )
        try sut.save(updated)

        let retrieved = sut.retrieve()
        XCTAssertEqual(retrieved?.accessToken, "new-access")
        XCTAssertEqual(retrieved?.refreshToken, "new-refresh")
    }

    func testDeleteWhenEmptyDoesNotThrow() {
        sut.delete()
        sut.delete()
    }

    // MARK: - Helpers

    private func makeTokens(
        access: String = "test-access",
        refresh: String = "test-refresh"
    ) -> AuthTokens {
        AuthTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(3600)
        )
    }
}
