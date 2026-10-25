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

    static let maxAgeDays = 90

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

    /// Days since the yt-dlp binary was last modified (installed/updated).
    func daysSinceInstall() -> Int {
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: ytdlpPath
        ),
              let modified = attrs[.modificationDate] as? Date
        else { return Int.max }
        let days = Calendar.current.dateComponents(
            [.day], from: modified, to: Date()
        ).day ?? Int.max
        return max(days, 0)
    }

    var isOutdated: Bool {
        daysSinceInstall() > Self.maxAgeDays
    }

    func version() async -> String? {
        guard isInstalled else { return nil }
        let path = ytdlpPath
        return await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["--version"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            guard (try? proc.run()) != nil else { return nil }
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

    /// Installs if missing, updates if older than maxAgeDays.
    func ensureUpToDate() async throws {
        if !isInstalled {
            try await install()
        } else if isOutdated {
            try await update()
        }
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

    static func parseTagName(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any] else { return nil }
        return json["tag_name"] as? String
    }

    func latestVersion() async -> String? {
        let request = URLRequest(url: Self.latestReleaseURL)
        guard let (data, _) = try? await client.data(for: request)
        else { return nil }
        return Self.parseTagName(from: data)
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
