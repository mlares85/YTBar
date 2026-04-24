import Foundation

struct AppConfig: Codable {
    var clientID: String
    var clientSecret: String

    var isConfigured: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty
    }

    static let `default` = AppConfig(clientID: "", clientSecret: "")

    static var filePath: String {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("YTBar")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("config.json").path
    }

    static func load() -> AppConfig {
        guard let data = FileManager.default.contents(
            atPath: filePath
        ) else { return .default }
        return (try? JSONDecoder().decode(AppConfig.self, from: data))
            ?? .default
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: URL(fileURLWithPath: Self.filePath), options: .atomic)
    }
}
