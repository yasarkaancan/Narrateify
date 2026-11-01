import Foundation
@main struct Test {
 static func main() throws {
  let cases = ["", "One short sentence.", "Dr. Smith paid $3.50. This is the next sentence! Really? Yes.", "你好世界。这是一个测试。مرحبا بالعالم", "| Name | Value |\n| --- | --- |\n| Apples | 42 |", String(repeating: "A very long sentence without full stops and with words ",count:100), String(repeating:"x",count:3000)]
  for text in cases {
   let chunks=BufferedTextChunker.chunk(text)
   func stripped(_ s:String)->String { String(s.filter { !$0.isWhitespace }) }
   precondition(stripped(chunks.joined()) == stripped(text), "Dropped text")
   precondition(chunks.enumerated().allSatisfy { $0.element.count <= ($0.offset == 0 ? 350 : 650) })
  }
  print("PASS chunking: blank, short prose, abbreviations, multilingual, table, long sentence, unbroken token; no dropped characters.")
 }
}
