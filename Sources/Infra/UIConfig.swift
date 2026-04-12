import Foundation

struct UIConfig: Codable {
    var windowOpacity: Double
    var streamQuality: AudioQuality = .normal
    var previousRestartEnabled: Bool = true
    var previousRestartThreshold: Double = 5.0
    var autoHideBrowsePanel: Bool = true
    var autoExtendQueueWithRadio: Bool = true
    var debugLoggingEnabled: Bool = false
    var volume: Double = 0.7

    static let `default` = UIConfig(windowOpacity: 1.0)

    static var filePath: String {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("YTBar")
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir.appendingPathComponent("ui-config.json").path
    }

    static func load() -> UIConfig {
        guard let data = FileManager.default.contents(
            atPath: filePath
        ) else { return .default }
        return (try? JSONDecoder().decode(
            UIConfig.self, from: data
        )) ?? .default
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: URL(fileURLWithPath: Self.filePath))
    }
}

// MARK: - Forward-compatible decoding
//
// Custom init(from:) lets us add new fields without losing existing user
// settings from older ui-config.json files. Placed in an extension so the
// memberwise initializer is still synthesized.
extension UIConfig {
    enum CodingKeys: String, CodingKey {
        case windowOpacity
        case streamQuality
        case previousRestartEnabled
        case previousRestartThreshold
        case autoHideBrowsePanel
        case autoExtendQueueWithRadio
        case debugLoggingEnabled
        case volume
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            windowOpacity: (try? c.decode(Double.self, forKey: .windowOpacity)) ?? 1.0,
            streamQuality: (try? c.decode(AudioQuality.self, forKey: .streamQuality)) ?? .normal,
            previousRestartEnabled: (try? c.decode(Bool.self, forKey: .previousRestartEnabled)) ?? true,
            previousRestartThreshold: (try? c.decode(Double.self, forKey: .previousRestartThreshold)) ?? 5.0,
            autoHideBrowsePanel: (try? c.decode(Bool.self, forKey: .autoHideBrowsePanel)) ?? true,
            autoExtendQueueWithRadio: (try? c.decode(Bool.self, forKey: .autoExtendQueueWithRadio)) ?? true,
            debugLoggingEnabled: (try? c.decode(Bool.self, forKey: .debugLoggingEnabled)) ?? false,
            volume: (try? c.decode(Double.self, forKey: .volume)) ?? 0.7
        )
    }
}
