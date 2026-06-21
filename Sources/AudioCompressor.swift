import AVFoundation

/// Transcodes uncompressed WAV audio (from the Apple/Kokoro/Chatterbox engines)
/// into compressed AAC `.m4a`, so saved recordings take a fraction of the disk.
/// MP3 engines (ElevenLabs/OpenAI) are already compressed and skip this.
enum AudioCompressor {
    /// Returns AAC `.m4a` bytes for the given WAV data, or nil if export fails
    /// (the caller then keeps the original WAV).
    static func aacM4A(from wavData: Data) async -> Data? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Narrateify-Compress-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let inURL = dir.appendingPathComponent("in.wav")
        let outURL = dir.appendingPathComponent("out.m4a")
        guard (try? wavData.write(to: inURL)) != nil else { return nil }

        let asset = AVURLAsset(url: inURL)
        guard let export = AVAssetExportSession(asset: asset,
                                                presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }
        export.outputURL = outURL
        export.outputFileType = .m4a

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }

        guard export.status == .completed else { return nil }
        return try? Data(contentsOf: outURL)
    }
}
