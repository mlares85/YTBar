import Foundation

enum DependencyManagerError: Error {
    case assetNotFound
    case invalidResponse
    case downloadFailed
}

final class DependencyManager: Sendable {
    private let client: HTTPClient
    private let basePath: String

    var ytdlpPath: String { basePath + "/bin/yt-dlp" }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: ytdlpPath)
    }

    init(
        client: HTTPClient = URLSession.shared,
        basePath: String? = nil
    ) {
        self.client = client
        self.basePath = basePath ?? Self.defaultBasePath
    }

    func ensureInstalled() async throws {
        guard !isInstalled else { return }
        try await install()
    }

    func install() async throws {
        let assetURL = try await fetchAssetURL()
        let binary = try await downloadBinary(from: assetURL)
        try writeBinary(binary)
    }

    func update() async throws {
        try await install()
    }
}

// MARK: - Static Helpers

extension DependencyManager {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest"
    )!

    static func parseAssetURL(from data: Data) throws -> URL {
        guard let json = try JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any] else {
            throw DependencyManagerError.invalidResponse
        }
        return try findMacOSAsset(in: json)
    }
}

// MARK: - Private

private extension DependencyManager {
    static var defaultBasePath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("YTBar").path
    }

    func fetchAssetURL() async throws -> URL {
        let request = URLRequest(url: Self.latestReleaseURL)
        let (data, _) = try await client.data(for: request)
        return try Self.parseAssetURL(from: data)
    }

    func downloadBinary(from url: URL) async throws -> Data {
        let request = URLRequest(url: url)
        let (data, _) = try await client.data(for: request)
        guard !data.isEmpty else {
            throw DependencyManagerError.downloadFailed
        }
        return data
    }

    func writeBinary(_ data: Data) throws {
        let binDir = basePath + "/bin"
        try FileManager.default.createDirectory(
            atPath: binDir,
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: ytdlpPath,
            contents: data
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: ytdlpPath
        )
    }

    static func findMacOSAsset(
        in json: [String: Any]
    ) throws -> URL {
        guard let assets = json["assets"] as? [[String: Any]]
        else { throw DependencyManagerError.invalidResponse }
        guard let asset = assets.first(
            where: { ($0["name"] as? String) == "yt-dlp_macos" }
        ) else { throw DependencyManagerError.assetNotFound }
        guard let urlStr = asset["browser_download_url"] as? String,
              let url = URL(string: urlStr)
        else { throw DependencyManagerError.invalidResponse }
        return url
    }
}
