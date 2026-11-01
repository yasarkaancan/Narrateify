import XCTest
@testable import Narrateify

final class BufferedTextChunkerTests: XCTestCase {
    func testPreservesTextWithBoundedChunks() {
        let inputs = ["", "Short sentence.", "Dr. Smith paid $3.50. Really? Yes!",
                      "你好世界。这是一个测试。مرحبا بالعالم", "| Name | Value |\n| Apples | 42 |",
                      String(repeating: "A long sentence without punctuation ", count: 100),
                      String(repeating: "x", count: 3000)]
        for input in inputs {
            let chunks = BufferedTextChunker.chunk(input)
            XCTAssertEqual(chunks.joined().filter { !$0.isWhitespace }, input.filter { !$0.isWhitespace })
            for (index, chunk) in chunks.enumerated() {
                XCTAssertLessThanOrEqual(chunk.count, index == 0 ? 350 : 650)
            }
        }
    }
    func testKeepsOrdinarySentencesTogether() {
        let sentence = "This is a complete sentence with a natural stopping point."
        let chunks = BufferedTextChunker.chunk(Array(repeating: sentence, count: 40).joined(separator: " "))
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.hasSuffix(".") })
    }
}
