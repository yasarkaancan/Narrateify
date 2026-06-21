import NaturalLanguage

/// Detects the dominant language of captured text so narration can switch to a
/// matching voice automatically. Returns a two-letter base code ("en", "de",
/// "zh") or nil when it isn't reasonably confident.
enum LanguageDetector {
    static func detectBaseCode(_ text: String) -> String? {
        let sample = String(text.prefix(400))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.count >= 12 else { return nil }   // too short to trust
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let lang = recognizer.dominantLanguage else { return nil }
        // Only act when fairly confident, so a stray foreign word doesn't switch.
        if let confidence = recognizer.languageHypotheses(withMaximum: 1)[lang],
           confidence < 0.55 {
            return nil
        }
        return String(lang.rawValue.prefix(2))   // "zh-Hans" → "zh"
    }
}
