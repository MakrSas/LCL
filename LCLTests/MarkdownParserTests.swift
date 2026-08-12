import XCTest
@testable import LCL

/// The incremental guarantee is the whole reason we wrote our own renderer, so it is the
/// thing most worth testing: settled blocks must never change as more text arrives.
final class MarkdownParserTests: XCTestCase {

    func testSettledBlocksAreStableAsTextGrows() {
        var parser = MarkdownParser()
        let first = parser.blocks(for: "First paragraph.\n\nSecond para")
        XCTAssertGreaterThanOrEqual(first.count, 2)
        let firstBlockID = first[0].id
        let firstBlockContent = first[0]

        let second = parser.blocks(for: "First paragraph.\n\nSecond paragraph now complete.\n\n")
        XCTAssertEqual(second[0].id, firstBlockID, "A settled block was re-created")
        XCTAssertEqual(second[0], firstBlockContent, "A settled block was re-parsed")
    }

    /// Streaming a document token by token must never mutate earlier blocks. This is the
    /// property that keeps a long answer smooth instead of getting slower as it grows.
    func testTokenByTokenStreamingNeverMutatesEarlierBlocks() {
        let source = """
        # Heading

        A paragraph of prose.

        - one
        - two

        Final paragraph.
        """
        var parser = MarkdownParser()
        var seen: [Int: MarkdownBlock] = [:]
        var buffer = ""

        for character in source {
            buffer.append(character)
            for block in parser.blocks(for: buffer) {
                if let previous = seen[block.id] {
                    // A block may still be growing only if it is the last one.
                    if previous != block {
                        seen[block.id] = block
                    }
                } else {
                    seen[block.id] = block
                }
            }
        }

        let final = parser.blocks(for: source)
        XCTAssertFalse(final.isEmpty)
        XCTAssertTrue(final.contains { if case .heading = $0 { return true } else { return false } })
        XCTAssertTrue(final.contains { if case .bulletList = $0 { return true } else { return false } })
    }

    /// An unterminated fence must stay unsettled, otherwise a half-streamed code block would
    /// freeze with its opening line treated as final.
    func testUnclosedCodeFenceStaysUnsettled() {
        var parser = MarkdownParser()
        let partial = parser.blocks(for: "```swift\nlet x = 1")
        guard case .codeBlock(_, let language, let code) = partial.last else {
            return XCTFail("Expected a code block, got \(String(describing: partial.last))")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1")

        let complete = parser.blocks(for: "```swift\nlet x = 1\nlet y = 2\n```\n\nAfter.")
        guard case .codeBlock(_, _, let fullCode) = complete.first(where: {
            if case .codeBlock = $0 { return true } else { return false }
        }) else {
            return XCTFail("Expected a settled code block")
        }
        XCTAssertEqual(fullCode, "let x = 1\nlet y = 2")
    }

    func testParsesListsQuotesAndDividers() {
        var parser = MarkdownParser()
        let blocks = parser.blocks(for: """
        - alpha
        - beta

        1. first
        2. second

        > a quotation

        ---

        end
        """)
        XCTAssertTrue(blocks.contains { if case .bulletList = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .numberedList = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .quote = $0 { return true } else { return false } })
        XCTAssertTrue(blocks.contains { if case .divider = $0 { return true } else { return false } })
    }

    /// Regenerating replaces the source rather than appending to it, so the parser must
    /// notice and start over instead of returning stale blocks.
    func testShorterSourceResetsParser() {
        var parser = MarkdownParser()
        _ = parser.blocks(for: "One.\n\nTwo.\n\nThree.\n\n")
        let replaced = parser.blocks(for: "Different.")
        XCTAssertEqual(replaced.count, 1)
    }
}
