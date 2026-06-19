import AVFoundation

/// Plays a single complete audio file with full transport control:
/// play/pause, scrub, and skip ±5s. (Long text is synthesized into one file
/// before playback so seeking works across the whole narration.)
final class AudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var hasAudio = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    /// Load a finished audio file and (optionally) start playing.
    func load(url: URL, autoplay: Bool = true) {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        configure(p, autoplay: autoplay)
    }

    /// Load finished audio bytes and (optionally) start playing.
    func load(data: Data, autoplay: Bool = true) {
        stop()
        guard let p = try? AVAudioPlayer(data: data) else { return }
        configure(p, autoplay: autoplay)
    }

    private func configure(_ p: AVAudioPlayer, autoplay: Bool) {
        p.delegate = self
        p.enableRate = true
        p.prepareToPlay()
        player = p
        duration = p.duration
        currentTime = 0
        hasAudio = true
        if autoplay { play() }
    }

    func play() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTicker()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        hasAudio = false
        currentTime = 0
        duration = 0
        stopTicker()
    }

    /// Jump to an absolute time (clamped to the file).
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    /// Skip relative to the current position, e.g. -5 / +5 seconds.
    func skip(by seconds: TimeInterval) {
        guard let player else { return }
        seek(to: player.currentTime + seconds)
    }

    // MARK: Position ticker

    private func startTicker() {
        stopTicker()
        // `.common` mode keeps the scrubber advancing during UI tracking, but it
        // means the timer can fire *inside* a SwiftUI view update. Assigning a
        // @Published value there triggers "Publishing changes from within view
        // updates." Defer the write to a clean main-queue turn (and skip no-ops)
        // so the publish never lands mid-update.
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            let time = player.currentTime
            DispatchQueue.main.async {
                if self.currentTime != time { self.currentTime = time }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    // MARK: AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopTicker()
        }
    }
}
