import AVFoundation
import Combine

// MARK: - Engine Protocol

enum AudioEngineStatus {
    case unknown, readyToPlay, failed
}

protocol AudioPlayerEngine: AnyObject {
    func load(url: URL)
    func play()
    func pause()
    func stop()
    func seek(to fraction: Double)
    func setVolume(_ vol: Float)
    var onStatusChange: ((AudioEngineStatus) -> Void)? { get set }
    var onFinished: (() -> Void)? { get set }
    var onTimeUpdate: ((Double, Double) -> Void)? { get set }
}

// MARK: - AudioPlayer

final class AudioPlayer: ObservableObject {
    @Published var state: PlayerState = .idle
    @Published var progress: Double = 0.0
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var volume: Float = 1.0

    var onTrackFinished: (() -> Void)?
    var realDuration: TimeInterval = 0
    private var didFireFinished = false
    private let engine: AudioPlayerEngine

    init(engine: AudioPlayerEngine) {
        self.engine = engine
        bindEngine()
    }

    convenience init() {
        self.init(engine: AVPlayerEngine())
    }

    func load(url: URL) {
        resetPlayback()
        state = .loading
        engine.load(url: url)
    }

    func play() {
        state = .playing
        engine.play()
    }

    func pause() {
        state = .paused
        engine.pause()
    }

    func stop() {
        state = .idle
        resetPlayback()
        engine.stop()
    }

    func seek(to fraction: Double) {
        progress = fraction
        engine.seek(to: fraction)
    }

    func setVolume(_ vol: Float) {
        volume = min(max(vol, 0.0), 1.0)
        engine.setVolume(volume)
    }
}

// MARK: - Private

private extension AudioPlayer {
    func bindEngine() {
        engine.onStatusChange = { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.state = .playing
                case .failed:
                    self.state = .error("Failed to load")
                case .unknown: break
                }
            }
        }
        engine.onTimeUpdate = { [weak self] current, dur in
            DispatchQueue.main.async {
                guard let self else { return }
                self.currentTime = current
                self.duration = dur
                self.progress = dur > 0 ? current / dur : 0
                self.checkRealEnd(current: current)
            }
        }
        engine.onFinished = { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.didFireFinished else { return }
                self.didFireFinished = true
                self.state = .idle
                self.onTrackFinished?()
            }
        }
    }

    func resetPlayback() {
        progress = 0.0
        currentTime = 0.0
        duration = 0.0
        didFireFinished = false
    }

    func checkRealEnd(current: TimeInterval) {
        guard !didFireFinished else { return }
        let effectiveDur = realDuration > 0
            ? realDuration
            : (duration > 0 ? duration / 2 : 0)
        guard effectiveDur > 0 else { return }
        if current >= effectiveDur - 1.5 {
            didFireFinished = true
            engine.stop()
            state = .idle
            onTrackFinished?()
        }
    }
}

// MARK: - AVPlayer Engine

final class AVPlayerEngine: AudioPlayerEngine {
    var onStatusChange: ((AudioEngineStatus) -> Void)?
    var onFinished: (() -> Void)?
    var onTimeUpdate: ((Double, Double) -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        cleanup()
        let asset: AVURLAsset
        if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            let headers = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"]
            asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        }
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player?.volume = 1.0
        observeStatus(item: item)
        observeEnd(item: item)
        addTimeObserver()
    }

    func play() { player?.play() }
    func pause() { player?.pause() }

    func stop() {
        cleanup()
        player = nil
    }

    func seek(to fraction: Double) {
        guard let duration = player?.currentItem?.duration else { return }
        let target = CMTimeMultiplyByFloat64(duration, multiplier: fraction)
        player?.seek(to: target)
    }

    func setVolume(_ vol: Float) { player?.volume = vol }

    deinit { cleanup() }
}

// MARK: - AVPlayer Observers

private extension AVPlayerEngine {
    func observeStatus(item: AVPlayerItem) {
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                self?.onStatusChange?(.readyToPlay)
                self?.player?.play()
            case .failed:
                let err = item.error?.localizedDescription ?? "unknown"
                Self.logDebug("AVPlayer failed: \(err)")
                self?.onStatusChange?(.failed)
            default:
                self?.onStatusChange?(.unknown)
            }
        }
    }

    static func logDebug(_ msg: String) {
        DebugLogger.shared.log("[AUDIO] \(msg)")
    }

    func observeEnd(item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in self?.onFinished?() }
    }

    func addTimeObserver() {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
            guard let self, let item = self.player?.currentItem else { return }
            let current = CMTimeGetSeconds(time)
            let duration = CMTimeGetSeconds(item.duration)
            guard duration.isFinite, duration > 0 else { return }
            self.onTimeUpdate?(current, duration)
        }
    }

    func cleanup() {
        if let t = timeObserver { player?.removeTimeObserver(t) }
        if let e = endObserver { NotificationCenter.default.removeObserver(e) }
        timeObserver = nil
        statusObserver = nil
        endObserver = nil
    }
}
