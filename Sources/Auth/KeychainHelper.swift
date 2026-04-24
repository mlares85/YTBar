import Foundation

struct KeychainHelper {
    private let filePath: String

    init(service: String = "com.ytbar.auth") {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("YTBar")
        try? FileManager.default.createDirectory(
            at: appSupport,
            withIntermediateDirectories: true
        )
        filePath = appSupport
            .appendingPathComponent("\(service).json").path
    }

    func save(_ tokens: AuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }

    func retrieve() -> AuthTokens? {
        guard let data = FileManager.default.contents(
            atPath: filePath
        ) else { return nil }
        return try? JSONDecoder().decode(
            AuthTokens.self,
            from: data
        )
    }

    func delete() {
        try? FileManager.default.removeItem(atPath: filePath)
    }
}

enum KeychainError: Error {
    case saveFailed(OSStatus)
}
