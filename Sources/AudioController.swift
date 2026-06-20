import AVFoundation

/// Plays a single complete audio file with full transport control:
/// play/pause, scrub, and skip ±5s. (Long text is synthesized into one file
/// before playback so seeking works across the whole narration.)
final class AudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var hasAudio = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// Playback speed multiplier (0.5–2.0). Persisted and applied live.
    @Published var rate: Float = UserDefaults.standard.object(forKey: "playbackRate") as? Float ?? 1.0 {
        didSet {
            UserDefaults.standard.set(rate, forKey: "playbackRate")
            player?.rate = rate
            if streaming, (queue?.rate ?? 0) != 0 { queue?.rate = rate }
        }
    }
    /// True while playing a streamed (chunk-by-chunk) narration.
    @Published private(set) var streaming = false

    /// Called when playback reaches the natural end (single-file or a fully
    /// streamed narration). Used to advance the reading queue.
    var onFinished: (() -> Void)?

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    // Streaming (queue) mode plumbing.
    private var queue: AVQueuePlayer?
    private var queueTimeObserver: Any?
    private var endObservers: [NSObjectProtocol] = []
    private var finishedDuration: TimeInterval = 0   // durations of finished items
    private var enqueuedTotal: TimeInterval = 0      // sum of all enqueued durations
    private var streamSealed = false                 // no more chunks coming

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
        p.rate = rate
        player = p
        duration = p.duration
        currentTime = 0
        hasAudio = true
        if autoplay { play() }
    }

    func play() {
        if streaming {
            queue?.rate = rate
            isPlaying = true
            return
        }
        guard let player else { return }
        player.play()
        isPlaying = true
        startTicker()
    }

    func pause() {
        if streaming {
            queue?.pause()
            isPlaying = false
            return
        }
        player?.pause()
        isPlaying = false
        stopTicker()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func stop() {
        if streaming { teardownQueue() }
        player?.stop()
        player = nil
        isPlaying = false
        hasAudio = false
        currentTime = 0
        duration = 0
        stopTicker()
    }

    /// Jump to an absolute time (clamped to the file). No-op while streaming
    /// (cross-chunk seeking isn't supported in that mode).
    func seek(to time: TimeInterval) {
        guard !streaming, let player else { return }
        let clamped = min(max(0, time), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    /// Skip relative to the current position, e.g. -5 / +5 seconds.
    func skip(by seconds: TimeInterval) {
        guard !streaming, let player else { return }
        seek(to: player.currentTime + seconds)
    }

    // MARK: Streaming mode

    /// Begin a streamed narration: playback starts as soon as the first chunk is
    /// enqueued, while later chunks are still being synthesized.
    func beginStreaming() {
        stop()
        let q = AVQueuePlayer()
        q.actionAtItemEnd = .advance
        queue = q
        streaming = true
        streamSealed = false
        hasAudio = true
        isPlaying = true
        currentTime = 0
        duration = 0
        finishedDuration = 0
        enqueuedTotal = 0

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        queueTimeObserver = q.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            guard let self, let q = self.queue else { return }
            let cur = q.currentItem.map { CMTimeGetSeconds($0.currentTime()) } ?? 0
            let t = self.finishedDuration + (cur.isFinite ? cur : 0)
            if self.currentTime != t { self.currentTime = t }
            let playing = q.rate != 0 && q.currentItem != nil
            if self.isPlaying != playing { self.isPlaying = playing }

            // All chunks enqueued and the queue has drained → the narration is
            // done. (Before sealing, an empty queue just means we're waiting on
            // the next chunk to synthesize.)
            if self.streamSealed, q.currentItem == nil {
                let callback = self.onFinished
                self.teardownQueue()
                self.isPlaying = false
                self.hasAudio = false
                self.currentTime = self.duration
                callback?()
            }
        }
    }

    /// Signals that every chunk has been enqueued; once the queue drains the
    /// narration is considered finished.
    func sealStreaming() {
        streamSealed = true
    }

    /// Append a freshly-synthesized chunk (written to `url`) to the stream.
    func enqueueStreaming(url: URL) {
        guard streaming, let q = queue else { return }
        let item = AVPlayerItem(url: url)
        let dur = CMTimeGetSeconds(item.asset.duration)
        if dur.isFinite, dur > 0 {
            enqueuedTotal += dur
            duration = enqueuedTotal
        }
        let observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            guard let self else { return }
            if dur.isFinite, dur > 0 { self.finishedDuration += dur }
        }
        endObservers.append(observer)

        q.insert(item, after: q.items().last)
        if q.rate == 0 {        // first chunk — start playing
            q.rate = rate
            isPlaying = true
        }
    }

    private func teardownQueue() {
        if let obs = queueTimeObserver { queue?.removeTimeObserver(obs); queueTimeObserver = nil }
        for o in endObservers { NotificationCenter.default.removeObserver(o) }
        endObservers.removeAll()
        queue?.removeAllItems()
        queue = nil
        streaming = false
        streamSealed = false
        finishedDuration = 0
        enqueuedTotal = 0
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
            self.onFinished?()
        }
    }
}
