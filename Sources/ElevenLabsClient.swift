import Foundation

/// Minimal ElevenLabs Text-to-Speech client.
/// POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id}  ->  MP3 bytes
struct ElevenLabsClient {
    let apiKey: String
    let voiceId: String
    let modelId: String
    var settings: VoiceSettings = .init()

    /// Tunable synthesis parameters sent as `voice_settings`.
    struct VoiceSettings {
        var stability: Double = 0.5
        var similarityBoost: Double = 0.75
        var speed: Double = 1.0   // ElevenLabs accepts 0.7…1.2 (1.0 = normal)
    }

    /// A voice as returned by `GET /v1/voices`.
    struct Voice: Codable, Identifiable, Hashable {
        let voiceId: String
        let name: String
        let category: String?
        /// A short hosted sample of the voice (used for free in-app previews).
        let previewURL: URL?

        var id: String { voiceId }

        enum CodingKeys: String, CodingKey {
            case voiceId = "voice_id"
            case name
            case category
            case previewURL = "preview_url"
        }
    }

    enum ClientError: LocalizedError {
        case missingConfig
        case http(Int, String)
        case empty

        var errorDescription: String? {
            switch self {
            case .missingConfig: return "Set your API key and voice ID in Settings."
            case .http(let code, let body):
                let detail = body.isEmpty ? "" : " – \(body.prefix(160))"
                return "ElevenLabs error \(code)\(detail)"
            case .empty: return "No audio was returned."
            }
        }
    }

    func synthesize(text: String) async throws -> Data {
        guard !apiKey.isEmpty, !voiceId.isEmpty else { throw ClientError.missingConfig }

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": [
                "stability": settings.stability,
                "similarity_boost": settings.similarityBoost,
                "speed": settings.speed
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else { throw ClientError.empty }
        return data
    }

    /// Fetches the account's available voices so the user can pick one in Settings.
    static func fetchVoices(apiKey: String) async throws -> [Voice] {
        guard !apiKey.isEmpty else { throw ClientError.missingConfig }

        let url = URL(string: "https://api.elevenlabs.io/v1/voices")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.empty }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        struct VoicesResponse: Codable { let voices: [Voice] }
        return try JSONDecoder().decode(VoicesResponse.self, from: data).voices
    }
}

/// Splits long text into request-sized chunks at sentence boundaries.
/// ElevenLabs caps a single request at 5,000 characters; we stay well under.
enum TextChunker {
    static func chunk(_ text: String, maxLength: Int = 2500) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > maxLength else { return [trimmed] }

        var chunks: [String] = []
        var current = ""

        // Naive sentence split; good enough for narration.
        let normalized = trimmed.replacingOccurrences(of: "\n", with: " ")
        let sentences = normalized.components(separatedBy: ". ")

        for (i, sentence) in sentences.enumerated() {
            let piece = (i < sentences.count - 1) ? sentence + ". " : sentence

            if current.count + piece.count > maxLength {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }
                if piece.count > maxLength {
                    // A single sentence longer than the limit: hard-split it.
                    chunks.append(contentsOf: hardSplit(piece, maxLength: maxLength))
                } else {
                    current = piece
                }
            } else {
                current += piece
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func hardSplit(_ s: String, maxLength: Int) -> [String] {
        var result: [String] = []
        var start = s.startIndex
        while start < s.endIndex {
            let end = s.index(start, offsetBy: maxLength, limitedBy: s.endIndex) ?? s.endIndex
            result.append(String(s[start..<end]))
            start = end
        }
        return result
    }
}
