import Foundation

/// A user-defined "say X as Y" substitution applied before synthesis — useful
/// for names, acronyms, and product spellings a voice mangles.
struct PronunciationRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var from: String
    var to: String
    /// Match only whole words (so "AI" doesn't rewrite "rain").
    var wholeWord: Bool = true

    func apply(to text: String) -> String {
        let needle = from.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: needle)
        let pattern = wholeWord ? "\\b\(escaped)\\b" : escaped
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate:
            NSRegularExpression.escapedTemplate(for: to))
    }
}

/// How aggressively to clean academic citation/reference noise. Scientific
/// papers (especially via screenshot OCR) are full of `[65]`, `(Smith et al.,
/// 2020)`, hyphenated line breaks, and trailing reference lists that turn
/// narration into noise.
enum CitationCleanupMode: String, CaseIterable, Identifiable {
    case none, smart, aggressive
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none:       return "Off"
        case .smart:      return "Smart"
        case .aggressive: return "Aggressive"
        }
    }
}

/// Cleans captured text before synthesis so voices stop reading literal markdown
/// and raw URLs. Every stage is conservative — the goal is fewer "asterisk
/// asterisk" and "h-t-t-p-colon-slash-slash" moments, not rewriting the user's
/// words.
struct TextPreprocessor {
    var stripMarkdown = true
    var expandAbbreviations = true
    var simplifyURLs = true
    var citationMode: CitationCleanupMode = .none
    var pronunciations: [PronunciationRule] = []

    func process(_ text: String) -> String {
        var s = text
        // User pronunciation rules run on the raw text first.
        for rule in pronunciations { s = rule.apply(to: s) }
        // Academic cleanup runs while line breaks are still present (needed for
        // de-hyphenation) and before markdown/URL handling.
        if citationMode != .none { s = Self.cleanCitations(s, mode: citationMode) }
        if simplifyURLs { s = Self.simplifyURLs(in: s) }
        if stripMarkdown { s = Self.stripMarkdown(from: s) }
        if expandAbbreviations { s = Self.expandAbbreviations(in: s) }
        // Collapse runs of whitespace left behind by the substitutions.
        s = Self.replace("[ \\t]{2,}", in: s, with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Academic / citation cleanup

    /// Removes in-text citation noise. `smart` handles the always-safe cases;
    /// `aggressive` additionally strips author-year citations, rewrites "et al.",
    /// and trims a trailing reference list.
    static func cleanCitations(_ text: String, mode: CitationCleanupMode) -> String {
        guard mode != .none else { return text }
        var s = text

        // Re-join words split across a line break ("infor-\nmation").
        s = replace("([\\p{L}])-\\n[ \\t]*([\\p{L}])", in: s, with: "$1$2")

        // Numeric bracket citations: [65], [65, 66], [65–68], and chains [65][66].
        s = replace("[ \\t]*\\[\\s*\\d+(?:\\s*[–—-]\\s*\\d+)?(?:\\s*,\\s*\\d+(?:\\s*[–—-]\\s*\\d+)?)*\\s*\\]",
                    in: s, with: "")

        // Spell out reference abbreviations so they read naturally.
        let abbreviations: [(String, String)] = [
            ("\\bFigs?\\.", "Figure"), ("\\bEqs?\\.", "Equation"),
            ("\\bTabs?\\.", "Table"), ("\\bSecs?\\.", "Section"),
            ("\\bRefs?\\.", "Reference"), ("\\bApp\\.", "Appendix")
        ]
        for (pattern, replacement) in abbreviations {
            s = replace(pattern, in: s, with: replacement, caseInsensitive: true)
        }

        // Strip DOIs (bare URLs are handled by the URL stage).
        s = replace("\\bdoi:\\s*\\S+", in: s, with: "", caseInsensitive: true)

        if mode == .aggressive {
            // Parenthetical author-year citations: (Smith et al., 2020; Jones 2019).
            s = replace("\\s*\\((?:see |e\\.g\\.,? |cf\\.,? )?[A-Z][\\p{L}.'’&-]+[^()]*?(?:19|20)\\d{2}[a-z]?\\)",
                        in: s, with: "")
            // A bare trailing year reference, e.g. after "Smith et al. (2020)".
            s = replace("\\s*\\((?:19|20)\\d{2}[a-z]?\\)", in: s, with: "")
            // Read "et al." naturally.
            s = replace("\\bet al\\.?", in: s, with: "and colleagues", caseInsensitive: true)
            // Drop a trailing References / Bibliography section if captured.
            s = trimReferencesTail(s)
        }

        return repairPunctuation(s)
    }

    /// Tidies punctuation/spacing left behind when citations are removed
    /// ("results [12]." → "results ." → "results.").
    static func repairPunctuation(_ text: String) -> String {
        var s = text
        s = replace("[ \\t]+([,.;:!?])", in: s, with: "$1")   // space before punctuation
        s = replace("\\(\\s+", in: s, with: "(")               // "( foo"
        s = replace("\\s+\\)", in: s, with: ")")               // "foo )"
        s = replace("\\(\\s*\\)", in: s, with: "")             // empty "()"
        s = replace("([,;:])\\1+", in: s, with: "$1")          // doubled "," ";" ":"
        s = replace("[ \\t]{2,}", in: s, with: " ")
        return s
    }

    /// Removes everything from the last "References"/"Bibliography" heading on.
    static func trimReferencesTail(_ text: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: "(?im)^[\\t ]*(references|bibliography|works cited)[\\t ]*:?[\\t ]*$") else {
            return text
        }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last else { return text }
        return ns.substring(to: last.range.location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Stages

    /// Turns `[label](url)` into `label`, drops emphasis/heading/quote/list
    /// markers and code fences, and removes horizontal rules.
    static func stripMarkdown(from text: String) -> String {
        var s = text
        s = replace("!\\[[^\\]]*\\]\\([^)]*\\)", in: s, with: "")          // images
        s = replace("\\[([^\\]]+)\\]\\([^)]*\\)", in: s, with: "$1")        // links → label
        s = replace("`{1,3}", in: s, with: "")                              // code fences/spans
        s = replace("(?m)^\\s{0,3}#{1,6}\\s*", in: s, with: "")             // ATX headings
        s = replace("(?m)^\\s*>\\s?", in: s, with: "")                      // block quotes
        s = replace("(?m)^\\s*[-*+]\\s+", in: s, with: "")                  // bullet markers
        s = replace("(?m)^\\s*([-*_])(?:\\s*\\1){2,}\\s*$", in: s, with: "") // horizontal rules
        s = replace("(\\*\\*|__)(.+?)\\1", in: s, with: "$2")              // bold
        s = replace("(\\*|_)(.+?)\\1", in: s, with: "$2")                  // italics
        return s
    }

    /// Replaces a handful of abbreviations that voices spell out awkwardly.
    static func expandAbbreviations(in text: String) -> String {
        var s = text
        let map: [(String, String)] = [
            ("\\be\\.g\\.", "for example"),
            ("\\bi\\.e\\.", "that is"),
            ("\\betc\\.", "et cetera"),
            ("\\bvs\\.?", "versus"),
            ("\\bapprox\\.", "approximately"),
            ("\\bw/", "with"),
            ("\\s&\\s", " and ")
        ]
        for (pattern, replacement) in map {
            s = replace(pattern, in: s, with: replacement, caseInsensitive: true)
        }
        return s
    }

    /// Replaces bare URLs with just their host (e.g. "example.com"), which reads
    /// far better than the full path. Markdown links are handled separately.
    static func simplifyURLs(in text: String) -> String {
        replace("https?://(?:www\\.)?([^/\\s]+)\\S*", in: text, with: "$1", caseInsensitive: true)
    }

    // MARK: Helpers

    private static func replace(_ pattern: String, in text: String,
                                with template: String, caseInsensitive: Bool = false) -> String {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
