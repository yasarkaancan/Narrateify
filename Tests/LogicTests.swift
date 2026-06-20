import XCTest
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
}
