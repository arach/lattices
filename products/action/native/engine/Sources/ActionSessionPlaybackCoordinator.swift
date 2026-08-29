import AVFoundation
import Foundation

final class ActionSessionPlaybackCoordinator: ObservableObject, @unchecked Sendable {
    let player: AVPlayer

    @Published private(set) var currentTimeSeconds: Double = 0
    @Published private(set) var durationSeconds: Double = 0
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var playbackRate: Double = 1

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    init(url: URL) {
        self.player = AVPlayer(url: url)
        installTimeObserver()
        installEndObserver()
        refreshDuration()
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func load(url: URL) {
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        currentTimeSeconds = 0
        isPlaying = false
        installEndObserver()
        refreshDuration()
    }

    func play() {
        if durationSeconds > 0, currentTimeSeconds >= durationSeconds {
            seek(to: 0)
        }
        player.playImmediately(atRate: Float(playbackRate))
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        pause()
        seek(to: 0)
    }

    func skip(by seconds: Double) {
        seek(to: currentTimeSeconds + seconds)
    }

    func setPlaybackRate(_ rate: Double) {
        let clamped = max(0.25, min(rate, 4))
        playbackRate = clamped
        if isPlaying {
            player.rate = Float(clamped)
        }
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, durationSeconds > 0 ? durationSeconds : seconds))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTimeSeconds = target
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else {
                return
            }
            let seconds = time.seconds
            if seconds.isFinite {
                if abs(currentTimeSeconds - seconds) >= 0.02 {
                    currentTimeSeconds = seconds
                }
            }
            if durationSeconds <= 0 {
                refreshDuration()
            }
        }
    }

    private func installEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        guard let item = player.currentItem else {
            endObserver = nil
            return
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
        }
    }

    private func refreshDuration() {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite else {
            return
        }
        durationSeconds = duration
    }
}
