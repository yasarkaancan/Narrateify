import AVFoundation

/// Combines several synthesized audio chunks into a single playable file.
///
/// MP3 chunks (ElevenLabs / OpenAI) concatenate cleanly — the format has no
/// central header, so appended frames just play on. WAV chunks (Apple / Kokoro /
/// Chatterbox) each carry their own RIFF header whose data-length field only
/// describes that one chunk; naively appending them yields a file that players
/// stop reading after the first chunk. For WAV we therefore decode each chunk's
/// PCM and write one combined file so the whole narration plays and scrubs.
enum AudioJoiner {
    private enum JoinError: Error { case formatMismatch, empty }

    /// Returns combined bytes for `chunks`. `fileExtension` is the per-chunk
    /// container ("wav" / "mp3"). WAV is PCM-merged; everything else (MP3) is
    /// concatenated. Falls back to concatenation if a PCM merge isn't possible.
    static func join(_ chunks: [Data], fileExtension: String) -> Data {
        guard chunks.count > 1 else { return chunks.first ?? Data() }
        if fileExtension.lowercased() == "wav", let merged = try? mergeWAV(chunks) {
            return merged
        }
        var out = Data()
        for c in chunks { out.append(c) }
        return out
    }

    /// Decodes each WAV chunk and writes their PCM, in order, into one WAV file.
    /// All chunks come from the same engine/voice/settings, so they share a
    /// format; if a later chunk's format differs we throw and the caller falls
    /// back to raw concatenation.
    private static func mergeWAV(_ chunks: [Data]) throws -> Data {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Narrateify-Join-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var inputs: [AVAudioFile] = []
        for (i, data) in chunks.enumerated() {
            let url = tmp.appendingPathComponent("in-\(i).wav")
            try data.write(to: url)
            inputs.append(try AVAudioFile(forReading: url))
        }
        guard let first = inputs.first else { throw JoinError.empty }

        // Mirror the format-preserving writer pattern used in AppleTTS.swift.
        let fmt = first.processingFormat
        let outURL = tmp.appendingPathComponent("out.wav")
        let out = try AVAudioFile(forWriting: outURL,
                                  settings: fmt.settings,
                                  commonFormat: fmt.commonFormat,
                                  interleaved: fmt.isInterleaved)
        for f in inputs {
            guard f.processingFormat == fmt else { throw JoinError.formatMismatch }
            let frames = AVAudioFrameCount(f.length)
            guard frames > 0,
                  let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { continue }
            try f.read(into: buf)
            try out.write(from: buf)
        }
        return try Data(contentsOf: outURL)
    }
}
