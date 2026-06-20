import Foundation
import MediaPlayer

/// Bridges narration playback to macOS's **Now Playing** system: the F7/F8 media
/// keys, Control Center, and the Now Playing widget can control play/pause/skip,
/// and the current narration shows up there. Commands call back into the audio
/// controller via the handlers supplied to `activate`.
@MainActor
final class NowPlayingController {
    static let shared = NowPlayingController()

    private var activated = false

    /// Wire the remote-command targets once. The closures are invoked when the
    /// user presses a media key or uses Control Center.
    func activate(play: @escaping () -> Void,
                  pause: @escaping () -> Void,
                  toggle: @escaping () -> Void,
                  skipBy: @escaping (Double) -> Void,
                  seekTo: @escaping (Double) -> Void) {
        guard !activated else { return }
        activated = true

        let c = MPRemoteCommandCenter.shared()

        c.playCommand.addTarget { _ in play(); return .success }
        c.pauseCommand.addTarget { _ in pause(); return .success }
        c.togglePlayPauseCommand.addTarget { _ in toggle(); return .success }
        c.stopCommand.addTarget { _ in pause(); return .success }

        c.skipForwardCommand.preferredIntervals = [5]
        c.skipBackwardCommand.preferredIntervals = [5]
        c.skipForwardCommand.addTarget { event in
            let by = (event as? MPSkipIntervalCommandEvent)?.interval ?? 5
            skipBy(by); return .success
        }
        c.skipBackwardCommand.addTarget { event in
            let by = (event as? MPSkipIntervalCommandEvent)?.interval ?? 5
            skipBy(-by); return .success
        }
        // No real "tracks", so map next/previous onto skip too.
        c.nextTrackCommand.isEnabled = false
        c.previousTrackCommand.isEnabled = false

        c.changePlaybackPositionCommand.addTarget { event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            seekTo(e.positionTime); return .success
        }
    }

    /// Start a new "track" (a narration) in Now Playing.
    func setTrack(title: String, duration: TimeInterval) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title.isEmpty ? "Narration" : title,
            MPMediaItemPropertyArtist: "Narrateify",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = .playing
    }

    /// Refresh elapsed time / rate / state (call on play, pause, seek). The
    /// duration is refreshed too, since a streamed narration's total grows as
    /// chunks arrive.
    func updatePlayback(elapsed: TimeInterval, rate: Float, isPlaying: Bool,
                        duration: TimeInterval? = nil) {
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0.0
        if let duration, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
