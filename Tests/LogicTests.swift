import XCTest
import CoreGraphics
@testable import Narrateify

/// Unit tests for the pure-logic helpers. These don't touch the UI or network.
final class LogicTests: XCTestCase {

    // MARK: TextChunker

    func testChunkerReturnsEmptyForBlank() {
        XCTAssertTrue(TextChunker.chunk("").isEmpty)
        XCTAssertTrue(TextChunker.chunk("   \n  ").isEmpty)
    }

    func testChunkerKeepsShortTextWhole() {
        let text = "Hello there. This is short."
        let chunks = TextChunker.chunk(text)
        XCTAssertEqual(chunks, [text])
    }

    func testChunkerSplitsLongTextUnderLimit() {
        let sentence = "This is a sentence. "
        let text = String(repeating: sentence, count: 400)   // ~8000 chars
        let chunks = TextChunker.chunk(text, maxLength: 2500)
        XCTAssertGreaterThan(chunks.count, 1)
        for c in chunks {
            XCTAssertLessThanOrEqual(c.count, 2500)
        }
    }

    func testChunkerHardSplitsAnOverlongSentence() {
        // A single "sentence" with no ". " boundary, longer than the limit.
        let text = String(repeating: "a", count: 6000)
        let chunks = TextChunker.chunk(text, maxLength: 2500)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined().count, 6000)
    }

    // MARK: Pricing

    func testPricingFullRateModel() {
        // Non-flash model bills 1 credit per character.
        XCTAssertEqual(Pricing.credits(characters: 1000, modelId: "eleven_multilingual_v2"), 1000)
    }

    func testPricingFlashIsHalf() {
        XCTAssertEqual(Pricing.credits(characters: 1000, modelId: "eleven_flash_v2_5"), 500)
        XCTAssertEqual(Pricing.credits(characters: 200, modelId: "eleven_turbo_v2"), 100)
    }

    func testPricingCost() {
        XCTAssertEqual(Pricing.cost(credits: 1000, pricePerThousand: 0.30), 0.30, accuracy: 1e-9)
        XCTAssertEqual(Pricing.cost(credits: 500, pricePerThousand: 0.30), 0.15, accuracy: 1e-9)
    }

    // MARK: UpdateChecker version comparison

    func testIsNewerBasic() {
        XCTAssertTrue(UpdateChecker.isNewer("1.1", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9", than: "1.0"))
    }

    func testIsNewerNumericNotLexical() {
        // "1.10" must beat "1.9" numerically.
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9"))
    }

    func testIsNewerStripsLeadingV() {
        XCTAssertTrue(UpdateChecker.isNewer("v2.0", than: "1.5"))
        XCTAssertEqual(UpdateChecker.normalize("v1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.normalize("  V3 "), "3")
    }

    func testIsNewerDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("1.0.1", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0", than: "1.0.1"))
    }

    // MARK: Keychain round-trip (best-effort; skips if Keychain is unavailable)

    func testKeychainRoundTrip() throws {
        let account = "unit-test-\(UUID().uuidString)"
        defer { Keychain.delete(account: account) }

        Keychain.set("s3cr3t", account: account)
        guard let read = Keychain.get(account: account) else {
            throw XCTSkip("Keychain not available in this test environment")
        }
        XCTAssertEqual(read, "s3cr3t")

        // Setting empty clears it.
        Keychain.set("", account: account)
        XCTAssertNil(Keychain.get(account: account))
    }

    // MARK: AppleTTSClient helpers

    func testAppleDisplayNameFallsBackToIdentifier() {
        // An identifier that doesn't resolve returns itself.
        XCTAssertEqual(AppleTTSClient.displayName(for: "not.a.real.voice"), "not.a.real.voice")
    }

    func testAppleDefaultVoiceIsResolvable() {
        // On a normal macOS install there's at least one system voice; on a
        // barebones CI image there may be none, so only assert when some exist.
        guard !AppleTTSClient.installedVoices().isEmpty else { return }
        XCTAssertFalse(AppleTTSClient.defaultVoiceIdentifier().isEmpty)
    }

    // MARK: TextPreprocessor

    func testPreprocessorStripsMarkdown() {
        let p = TextPreprocessor()
        let out = p.process("This is **bold** and _italic_ and a [link](https://example.com).")
        XCTAssertFalse(out.contains("*"))
        XCTAssertFalse(out.contains("_"))
        XCTAssertTrue(out.contains("bold"))
        XCTAssertTrue(out.contains("link"))
        XCTAssertFalse(out.contains("https://"))
    }

    func testPreprocessorExpandsAbbreviations() {
        let p = TextPreprocessor()
        let out = p.process("Use a fast model, e.g. Flash.")
        XCTAssertTrue(out.contains("for example"))
        XCTAssertFalse(out.contains("e.g."))
    }

    func testPreprocessorSimplifiesURLs() {
        XCTAssertEqual(TextPreprocessor.simplifyURLs(in: "see https://www.example.com/a/b?x=1 now"),
                       "see example.com now")
    }

    func testPreprocessorCanDisableStages() {
        // With cleanup off, markdown is left intact (only whitespace tidied).
        let p = TextPreprocessor(stripMarkdown: false, expandAbbreviations: false,
                                 simplifyURLs: false)
        XCTAssertEqual(p.process("**keep** me"), "**keep** me")
    }

    func testPronunciationRuleWholeWord() {
        let rule = PronunciationRule(from: "AI", to: "A.I.", wholeWord: true)
        XCTAssertEqual(rule.apply(to: "AI and rain"), "A.I. and rain")  // "rain" untouched
    }

    func testPronunciationRulePartialMatch() {
        let rule = PronunciationRule(from: "cat", to: "dog", wholeWord: false)
        XCTAssertEqual(rule.apply(to: "category"), "dogegory")
    }

    // MARK: LanguageDetector

    func testLanguageDetectionEnglishAndGerman() {
        XCTAssertEqual(LanguageDetector.detectBaseCode("The quick brown fox jumps over the lazy dog."), "en")
        XCTAssertEqual(LanguageDetector.detectBaseCode("Der schnelle braune Fuchs springt über den faulen Hund."), "de")
    }

    func testLanguageDetectionTooShortIsNil() {
        XCTAssertNil(LanguageDetector.detectBaseCode("hi"))
    }

    // MARK: AudioJoiner

    func testJoinSingleChunkReturnsItself() {
        let data = Data([1, 2, 3])
        XCTAssertEqual(AudioJoiner.join([data], fileExtension: "mp3"), data)
    }

    func testJoinMP3Concatenates() {
        let a = Data([1, 2]); let b = Data([3, 4])
        XCTAssertEqual(AudioJoiner.join([a, b], fileExtension: "mp3"), Data([1, 2, 3, 4]))
    }

    // MARK: Citation cleanup (scientific papers)

    func testSmartRemovesNumericCitations() {
        let out = TextPreprocessor.cleanCitations(
            "The result [65] was confirmed [66, 67] and extended [70–72].", mode: .smart)
        XCTAssertFalse(out.contains("["))
        XCTAssertFalse(out.contains("]"))
        XCTAssertTrue(out.contains("The result was confirmed and extended."))
    }

    func testSmartRemovesChainedCitations() {
        let out = TextPreprocessor.cleanCitations("Prior work [65][66][67] shows this.", mode: .smart)
        XCTAssertEqual(out, "Prior work shows this.")
    }

    func testSmartDeHyphenates() {
        let out = TextPreprocessor.cleanCitations("infor-\nmation flow", mode: .smart)
        XCTAssertTrue(out.contains("information flow"))
    }

    func testSmartExpandsReferenceAbbreviations() {
        let out = TextPreprocessor.cleanCitations("As shown in Fig. 3 and Eq. 2.", mode: .smart)
        XCTAssertTrue(out.contains("Figure 3"))
        XCTAssertTrue(out.contains("Equation 2"))
    }

    func testSmartKeepsAuthorYear() {
        // Smart mode must NOT touch author-year citations.
        let out = TextPreprocessor.cleanCitations("As argued (Smith et al., 2020).", mode: .smart)
        XCTAssertTrue(out.contains("Smith"))
        XCTAssertTrue(out.contains("2020"))
    }

    func testAggressiveRemovesAuthorYear() {
        let out = TextPreprocessor.cleanCitations(
            "This holds (Smith et al., 2020; Jones 2019) generally.", mode: .aggressive)
        XCTAssertFalse(out.contains("Smith"))
        XCTAssertFalse(out.contains("2020"))
        XCTAssertTrue(out.contains("This holds generally."))
    }

    func testAggressiveTrimsReferences() {
        let text = "Body text here.\n\nReferences\n[1] A. Author, A paper, 2020."
        let out = TextPreprocessor.cleanCitations(text, mode: .aggressive)
        XCTAssertTrue(out.hasPrefix("Body text here."))
        XCTAssertFalse(out.contains("A. Author"))
    }

    func testNoneLeavesTextUnchanged() {
        let text = "Keep [65] this (Smith, 2020) intact."
        XCTAssertEqual(TextPreprocessor.cleanCitations(text, mode: .none), text)
    }

    // MARK: OCR reading order

    private func ocrLine(_ text: String, _ x: CGFloat, _ y: CGFloat,
                         _ w: CGFloat = 0.3, conf: Float = 0.9) -> OCRLayout.Line {
        OCRLayout.Line(text: text, box: CGRect(x: x, y: y, width: w, height: 0.04), confidence: conf)
    }

    func testOCRTwoColumnReadingOrder() {
        // Left column (midX 0.25) should be read fully before the right (0.75).
        let lines = [
            ocrLine("right1", 0.6, 0.80), ocrLine("left1", 0.1, 0.80),
            ocrLine("right2", 0.6, 0.70), ocrLine("left2", 0.1, 0.70),
            ocrLine("right3", 0.6, 0.60), ocrLine("left3", 0.1, 0.60),
        ]
        let out = OCRLayout.orderedText(from: lines)
        XCTAssertEqual(out, "left1\nleft2\nleft3\nright1\nright2\nright3")
    }

    func testOCRDropsLowConfidenceAndMarginNumbers() {
        let lines = [
            ocrLine("real text", 0.1, 0.8),
            ocrLine("42", 0.02, 0.7),                 // margin line number
            ocrLine("garbage", 0.1, 0.6, conf: 0.1),  // low confidence
        ]
        XCTAssertEqual(OCRLayout.orderedText(from: lines), "real text")
    }

    func testOCRSingleColumnTopToBottom() {
        let lines = [
            ocrLine("third", 0.1, 0.5), ocrLine("first", 0.1, 0.8), ocrLine("second", 0.1, 0.65),
        ]
        XCTAssertEqual(OCRLayout.orderedText(from: lines), "first\nsecond\nthird")
    }

    // MARK: Translator

    func testTranslationLanguageCodesMatchVoiceBase() {
        // Codes are the 2-letter base used by voice matching.
        XCTAssertEqual(TranslationLanguage.german.rawValue, "de")
        XCTAssertEqual(TranslationLanguage.turkish.rawValue, "tr")
        XCTAssertEqual(TranslationLanguage.chinese.rawValue, "zh")
        // Every case has a non-empty English name for the prompt.
        for lang in TranslationLanguage.allCases {
            XCTAssertFalse(lang.englishName.isEmpty)
            XCTAssertFalse(lang.rawValue.isEmpty)
        }
    }

    func testTranslatorSystemPromptNamesTarget() {
        let prompt = Translator.systemPrompt(targetLanguageName: "Spanish")
        XCTAssertTrue(prompt.contains("Spanish"))
        XCTAssertTrue(prompt.lowercased().contains("only"))   // output-only instruction
    }

    func testTranslatorBlankTextReturnsUnchanged() async throws {
        // Blank input short-circuits before any network/key check.
        let t = Translator(apiKey: "", target: .french)
        let out = try await t.translate("   \n  ")
        XCTAssertEqual(out, "   \n  ")
    }

    func testTranslatorMissingKeyThrows() async {
        let t = Translator(apiKey: "", target: .german)
        do {
            _ = try await t.translate("Hello world")
            XCTFail("Expected missingKey error")
        } catch let error as Translator.TranslateError {
            if case .missingKey = error { } else { XCTFail("Wrong error: \(error)") }
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: AppState URL detection

    func testBareURLDetection() {
        XCTAssertNotNil(AppState.bareURL(in: "https://example.com/article"))
        XCTAssertNotNil(AppState.bareURL(in: "  http://example.com  "))
        XCTAssertNil(AppState.bareURL(in: "read this https://example.com please"))
        XCTAssertNil(AppState.bareURL(in: "just some text"))
        XCTAssertNil(AppState.bareURL(in: "ftp://example.com"))
    }
}
