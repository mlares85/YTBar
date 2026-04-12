import Foundation

final class DebugLogger: @unchecked Sendable {
    static let shared = DebugLogger()

    var isEnabled = false

    private let queue = DispatchQueue(label: "com.ytbar.debug-logger")
    private let logDir: URL
    private let logFile: URL

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        logDir = home.appendingPathComponent("Library/Logs/YTBar")
        logFile = logDir.appendingPathComponent("ytbar.log")
        ensureDirectory()
        rotateIfNeeded()
    }

    func log(_ message: String) {
        guard isEnabled else { return }
        write(message)
    }

    func logAlways(_ message: String) {
        write(message)
    }

    var logFilePath: String { logFile.path }

    var logFileExists: Bool {
        FileManager.default.fileExists(atPath: logFile.path)
    }

    func readLogContents() -> String? {
        try? String(contentsOf: logFile, encoding: .utf8)
    }
}

// MARK: - Private

private extension DebugLogger {
    func write(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"
        queue.async { [logFile] in
            Self.appendLine(line, to: logFile)
        }
    }

    static func appendLine(_ line: String, to file: URL) {
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: file)
        }
    }

    func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: logDir, withIntermediateDirectories: true
        )
    }

    func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: logFile.path
        ) else { return }
        let size = (attrs[.size] as? Int64) ?? 0
        guard size > 500_000 else { return }
        truncateToLastLines(5000)
    }

    func truncateToLastLines(_ count: Int) {
        guard let content = try? String(
            contentsOf: logFile, encoding: .utf8
        ) else { return }
        let lines = content.components(separatedBy: "\n")
        let kept = lines.suffix(count).joined(separator: "\n")
        try? kept.write(to: logFile, atomically: true, encoding: .utf8)
    }
}
