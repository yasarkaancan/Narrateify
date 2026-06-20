import Foundation
import AVFoundation

/// Synthesizes speech with Apple's built-in on-device engine
/// (`AVSpeechSynthesizer`) — free, offline, and no API key. Captures the
/// generated audio into WAV bytes so it flows through the same play/save/share
/// pipeline as every other provider.
struct AppleTTSClient: TTSProvider {
    /// An `AVSpeechSynthesisVoice` identifier (e.g. "com.apple.voice.compact.en-US.Samantha").
    let voiceIdentifier: String
    /// Our shared 0.7–1.2 "speed" multiplier; mapped onto Apple's rate scale.
    let speed: Double

    enum AppleTTSError: LocalizedError {
        case synthesisFailed
        case empty

        var errorDescription: String? {
            switch self {
            case .synthesisFailed: return "Apple speech synthesis failed."
            case .empty:           return "Apple TTS produced no audio."
            }
        }
    }

    func synthesize(text: String) async throws -> Data {
        // Keep the synthesizer alive for the whole call: it's referenced inside
        // the buffer callback, which the suspended continuation retains until the
        // final (empty) buffer arrives.
        let synth = AVSpeechSynthesizer()

        let utterance = AVSpeechUtterance(string: text)
        if let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        }
        // Map our 0.7–1.2 speed onto Apple's rate range around its default.
        let scaled = AVSpeechUtteranceDefaultSpeechRate * Float(speed)
        utterance.rate = min(max(scaled, AVSpeechUtteranceMinimumSpeechRate),
                             AVSpeechUtteranceMaximumSpeechRate)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("narrateify-apple-\(UUID().uuidString).wav")

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            var file: AVAudioFile?
            var finished = false

            func finish(_ result: Result<Data, Error>) {
                guard !finished else { return }
                finished = true
                file = nil   // flush + close the file
                try? FileManager.default.removeItem(at: url)
                cont.resume(with: result)
            }

            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                // The synthesizer signals completion with a zero-length buffer.
                guard pcm.frameLength > 0 else {
                    do {
                        file = nil   // ensure the WAV is fully written before reading
                        let data = try Data(contentsOf: url)
                        finish(data.isEmpty ? .failure(AppleTTSError.empty) : .success(data))
                    } catch {
                        finish(.failure(error))
                    }
                    return
                }
                do {
                    if file == nil {
                        file = try AVAudioFile(forWriting: url,
                                               settings: pcm.format.settings,
                                               commonFormat: pcm.format.commonFormat,
                                               interleaved: pcm.format.isInterleaved)
                    }
                    try file?.write(from: pcm)
                } catch {
                    finish(.failure(error))
                }
            }
        }
    }

    /// A single voice entry for the picker.
    struct Voice: Identifiable, Hashable {
        let id: String       // AVSpeechSynthesisVoice.identifier
        let name: String
        let language: String
        let premium: Bool
    }

    /// All installed system voices, grouped-friendly (sorted by language then
    /// name). The user can add more in System Settings → Accessibility → Spoken
    /// Content → System Voice → Manage Voices.
    static func installedVoices() -> [Voice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { v in
                Voice(id: v.identifier,
                      name: v.name,
                      language: v.language,
                      premium: v.quality == .premium || v.quality == .enhanced)
            }
            .sorted {
                $0.language == $1.language
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : $0.language < $1.language
            }
    }

    /// A sensible default voice identifier for the current locale.
    static func defaultVoiceIdentifier() -> String {
        if let v = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode()) {
            return v.identifier
        }
        return installedVoices().first?.id ?? ""
    }

    /// Human-readable label for a voice identifier, for display.
    static func displayName(for identifier: String) -> String {
        guard let v = AVSpeechSynthesisVoice(identifier: identifier) else { return identifier }
        return "\(v.name) (\(v.language))"
    }
}
