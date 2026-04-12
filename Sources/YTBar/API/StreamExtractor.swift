import Foundation

protocol ShellExecutor: Sendable {
    func run(
        binary: String,
        args: [String]
    ) async throws -> String
}

enum ShellError: Error {
    case nonZeroExit(Int32, String)
}

enum StreamExtractorError: Error {
    case emptyOutput
    case invalidURL(String)
    case invalidJSON
}

struct StreamInfo {
    let url: URL
    let format: String
    let bitrate: Int
}

final class StreamExtractor: @unchecked Sendable {
    private let shell: ShellExecutor
    private let ytdlpPath: String
    nonisolated(unsafe) var currentFormat: String = "bestaudio[ext=m4a]/bestaudio"

    init(shell: ShellExecutor, ytdlpPath: String) {
        self.shell = shell
        self.ytdlpPath = ytdlpPath
    }

    func extractStreamURL(
        videoId: String,
        cookiesPath: String? = nil
    ) async throws -> URL {
        let args = buildArgs(
            flags: ["--get-url"],
            videoId: videoId,
            cookiesPath: cookiesPath
        )
        let output = try await shell.run(
            binary: ytdlpPath,
            args: args
        )
        return try parseURL(from: output)
    }

    func extractStreamInfo(
        videoId: String,
        cookiesPath: String? = nil
    ) async throws -> StreamInfo {
        let args = buildArgs(
            flags: ["--dump-json"],
            videoId: videoId,
            cookiesPath: cookiesPath
        )
        let output = try await shell.run(
            binary: ytdlpPath,
            args: args
        )
        return try parseStreamInfo(from: output)
    }
}

// MARK: - Private

private extension StreamExtractor {
    func buildArgs(
        flags: [String],
        videoId: String,
        cookiesPath: String?
    ) -> [String] {
        var args = flags + ["-f", currentFormat, "--js-runtimes", "node:/opt/homebrew/bin/node"]
        if let cookiesPath {
            args += ["--cookies", cookiesPath]
        }
        args.append(videoURL(for: videoId))
        return args
    }

    func videoURL(for videoId: String) -> String {
        "https://music.youtube.com/watch?v=\(videoId)"
    }

    func parseURL(from output: String) throws -> URL {
        let trimmed = output.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            throw StreamExtractorError.emptyOutput
        }
        guard let url = URL(string: trimmed) else {
            throw StreamExtractorError.invalidURL(trimmed)
        }
        return url
    }

    func parseStreamInfo(from output: String) throws -> StreamInfo {
        let data = Data(output.utf8)
        guard let json = try JSONSerialization.jsonObject(
            with: data
        ) as? [String: Any] else {
            throw StreamExtractorError.invalidJSON
        }
        return try buildStreamInfo(from: json)
    }

    func buildStreamInfo(
        from json: [String: Any]
    ) throws -> StreamInfo {
        guard let urlStr = json["url"] as? String,
              let url = URL(string: urlStr),
              let format = json["ext"] as? String,
              let bitrate = json["abr"] as? Int
        else { throw StreamExtractorError.invalidJSON }
        return StreamInfo(
            url: url,
            format: format,
            bitrate: bitrate
        )
    }
}

// MARK: - ProcessShellExecutor

struct ProcessShellExecutor: ShellExecutor {
    func run(
        binary: String,
        args: [String]
    ) async throws -> String {
        let b = binary
        let a = args
        return try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: b)
            process.arguments = a
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            let data = stdoutPipe.fileHandleForReading
                .readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                let err = String(
                    data: stderrPipe.fileHandleForReading
                        .readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                throw ShellError.nonZeroExit(
                    process.terminationStatus, err
                )
            }
            return output
        }.value
    }
}
