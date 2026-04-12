import Foundation

final class AudioFileCache {
    private let cacheDir: URL
    private let metadata: CacheMetadata
    private let shell: ShellExecutor
    private let ytdlpPath: String
    var maxSizeBytes: Int64
    var downloadQuality: DownloadQuality
    private var activeDownloads: Set<String> = []

    init(
        metadata: CacheMetadata,
        shell: ShellExecutor,
        ytdlpPath: String,
        maxSizeBytes: Int64,
        downloadQuality: DownloadQuality = .high
    ) {
        self.metadata = metadata
        self.shell = shell
        self.ytdlpPath = ytdlpPath
        self.maxSizeBytes = maxSizeBytes
        self.downloadQuality = downloadQuality
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("YTBar/cache")
        self.cacheDir = base
        try? FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true
        )
    }

    func localFileURL(for videoId: String) -> URL? {
        let path = filePath(for: videoId)
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }
        return path
    }

    func downloadInBackground(
        videoId: String,
        playCount: Int,
        threshold: Int
    ) {
        guard playCount >= threshold else { return }
        guard !activeDownloads.contains(videoId) else { return }
        guard localFileURL(for: videoId) == nil else { return }
        activeDownloads.insert(videoId)
        let cache = self
        Task.detached { await cache.performDownload(videoId: videoId) }
    }

    var cacheDirURL: URL { cacheDir }

    func clearAll() throws {
        try FileManager.default.removeItem(at: cacheDir)
        try FileManager.default.createDirectory(
            at: cacheDir, withIntermediateDirectories: true
        )
        for candidate in metadata.evictionCandidates() {
            metadata.markEvicted(videoId: candidate.videoId)
        }
        metadata.save()
    }

    func downloadAll(videoIds: [String]) {
        for id in videoIds {
            guard !activeDownloads.contains(id) else { continue }
            guard localFileURL(for: id) == nil else { continue }
            activeDownloads.insert(id)
            let cache = self
            Task.detached { await cache.performDownload(videoId: id) }
        }
    }

    func cachedCount(of videoIds: [String]) -> Int {
        videoIds.filter { localFileURL(for: $0) != nil }.count
    }

    func currentUsage() -> Int64 {
        metadata.totalCacheSize()
    }
}

// MARK: - Download

private extension AudioFileCache {
    func performDownload(videoId: String) async {
        defer { activeDownloads.remove(videoId) }
        let tmpPath = filePath(for: videoId)
            .appendingPathExtension("tmp")
        let finalPath = filePath(for: videoId)
        do {
            try evictIfNeeded(reserveBytes: 10_000_000)
            let args = buildDownloadArgs(
                videoId: videoId, output: tmpPath.path
            )
            _ = try await shell.run(binary: ytdlpPath, args: args)
            try FileManager.default.moveItem(
                at: tmpPath, to: finalPath
            )
            let size = fileSize(at: finalPath)
            metadata.markCached(videoId: videoId, fileSize: size)
            metadata.save()
            logDebug("Cached \(videoId) (\(size / 1024)KB)")
        } catch {
            try? FileManager.default.removeItem(at: tmpPath)
            logDebug("Cache download failed \(videoId): \(error)")
        }
    }

    func buildDownloadArgs(
        videoId: String,
        output: String
    ) -> [String] {
        let url = "https://music.youtube.com/watch?v=\(videoId)"
        return [
            "-f", downloadQuality.ytdlpFormat,
            "--js-runtimes", "node:/opt/homebrew/bin/node",
            "-o", output, url
        ]
    }
}

// MARK: - Eviction

private extension AudioFileCache {
    func evictIfNeeded(reserveBytes: Int64) throws {
        var usage = metadata.totalCacheSize()
        let budget = maxSizeBytes
        guard usage + reserveBytes > budget else { return }
        for candidate in metadata.evictionCandidates() {
            let path = filePath(for: candidate.videoId)
            let lyricsPath = lyricsFilePath(for: candidate.videoId)
            try? FileManager.default.removeItem(at: path)
            try? FileManager.default.removeItem(at: lyricsPath)
            let freed = candidate.fileSize + candidate.lyricsFileSize
            metadata.markEvicted(videoId: candidate.videoId)
            usage -= freed
            if usage + reserveBytes <= budget { break }
        }
        metadata.save()
    }
}

// MARK: - Helpers

private extension AudioFileCache {
    func filePath(for videoId: String) -> URL {
        cacheDir.appendingPathComponent("\(videoId).m4a")
    }

    func lyricsFilePath(for videoId: String) -> URL {
        cacheDir.appendingPathComponent("\(videoId).lyrics.json")
    }

    func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return (attrs?[.size] as? Int64) ?? 0
    }

    func logDebug(_ msg: String) {
        DebugLogger.shared.log("[CACHE] \(msg)")
    }
}
