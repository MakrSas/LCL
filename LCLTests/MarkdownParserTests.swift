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
    ///
    /// This test used to hang CI indefinitely rather than fail it — `parser.blocks(for:)` never
    /// terminated once `buffer` reached `"# Heading"`'s leading `"#"` character alone (see the
    /// fix in `MarkdownView.swift`'s paragraph branch). It also, previously, asserted nothing
    /// about the invariant its name promises: it updated `seen` whenever a block differed but
    /// never actually failed the test over it. Both are fixed here — every block that isn't the
    /// current call's last one must be byte-identical to whatever was seen for that id before.
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
            let blocks = parser.blocks(for: buffer)
            for (offset, block) in blocks.enumerated() {
                let isLast = offset == blocks.count - 1
                if let previous = seen[block.id] {
                    XCTAssertTrue(
                        isLast || previous == block,
                        "settled block \(block.id) mutated after being seen once: \(previous) -> \(block)"
                    )
                }
                seen[block.id] = block
            }
        }

        let final = parser.blocks(for: source)
        XCTAssertFalse(final.isEmpty)
        XCTAssertTrue(final.contains { if case .heading = $0 { return true } else { return false } })
        XCTAssertTrue(final.contains { if case .bulletList = $0 { return true } else { return false } })
    }

    /// A bare "#" is heading-shaped by prefix alone but fails the heading branch's own
    /// "space after the hashes" check, so it falls through to paragraph parsing — whose "a new
    /// block starts here" check must not fire on the very line that started this paragraph, or
    /// `cursor` never advances past `index` and `blocks(for:)` spins forever. This is the exact
    /// state streaming a heading token-by-token passes through on its very first character.
    func testBareHashDoesNotHang() {
        var parser = MarkdownParser()
        let blocks = parser.blocks(for: "#")
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(_, let text) = blocks.first else {
            return XCTFail("expected a bare '#' to parse as a paragraph, got \(String(describing: blocks.first))")
        }
        XCTAssertEqual(String(text.characters), "#")
    }

    /// The actively-streaming trailing block must keep one id across every flush until it
    /// settles. Without this, `MarkdownView`'s `ForEach` sees a new row every ~16ms display
    /// tick and `.appearOnce()` replays its fade-in continuously — exactly what that modifier
    /// exists to prevent, and invisible to a test that never grows a block across more than
    /// two calls.
    func testGrowingTrailingBlockKeepsStableID() {
        var parser = MarkdownParser()
        let afterH = parser.blocks(for: "H")
        let afterHe = parser.blocks(for: "He")
        let afterHel = parser.blocks(for: "Hel")

        XCTAssertEqual(afterH.count, 1)
        XCTAssertEqual(afterHe.first?.id, afterH.first?.id)
        XCTAssertEqual(afterHel.first?.id, afterH.first?.id)
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

    /// docs/PHASE_1_PLAN.md Step 4's stated done-criterion: appending 4000 tokens stays fast.
    /// Re-parsing the whole document on every token — the exact bug this renderer exists to
    /// avoid (top of file) — would still likely finish this within the generous bound below at
    /// this scale, so this is a coarse smoke test, not a tight regression guard; the specific
    /// bug-shaped tests above are what actually protect the incremental guarantee. Its real
    /// job is enforcing that Step 4's documented promise has *a* test behind it, and that a
    /// truly catastrophic regression (a hang, or something like it) fails loudly here too.
    func testAppendingFourThousandTokensStaysFast() {
        var parser = MarkdownParser()
        var buffer = ""
        let start = Date()

        for index in 0..<4000 {
            switch index % 40 {
            case 0:
                buffer += "\n\n## Section \(index)\n\n"
            case 1...5:
                buffer += "- item \(index) with a few words of text\n"
            case 6:
                buffer += "\n"
            default:
                buffer += "word\(index) "
            }
            _ = parser.blocks(for: buffer)
        }

        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, 3.0,
            "4000 tokens took \(elapsed)s — suggests the parser stopped re-parsing only the trailing block"
        )
    }
}
