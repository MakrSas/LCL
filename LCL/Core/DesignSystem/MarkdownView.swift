import SwiftUI

// A block-incremental Markdown renderer.
//
// Why not an off-the-shelf library: every one of them re-parses the whole document on
// change, and during streaming that means re-parsing a growing document on every token.
// That is the exact performance bug docs/PRODUCT_SPEC.md §4 forbids.
//
// The property that makes streaming cheap: a block is *settled* once its terminator has
// been seen (a blank line, or a closing fence). Settled blocks are immutable and never
// re-parsed. Only the trailing block is re-parsed as tokens arrive.

// MARK: - Model

enum MarkdownBlock: Identifiable, Equatable {
    case paragraph(id: Int, text: AttributedString)
    case heading(id: Int, level: Int, text: AttributedString)
    case bulletList(id: Int, items: [AttributedString])
    case numberedList(id: Int, items: [AttributedString])
    case codeBlock(id: Int, language: String?, code: String)
    case quote(id: Int, text: AttributedString)
    case divider(id: Int)

    var id: Int {
        switch self {
        case .paragraph(let id, _), .heading(let id, _, _), .bulletList(let id, _),
             .numberedList(let id, _), .codeBlock(let id, _, _), .quote(let id, _),
             .divider(let id):
            return id
        }
    }
}

// MARK: - Incremental parser

struct MarkdownParser {
    private var settled: [MarkdownBlock] = []
    /// Index of the first line not yet folded into a settled block.
    private var settledLineIndex = 0
    private var nextBlockID = 0
    /// The id of the block currently occupying the unsettled tail (an unclosed fence, or the
    /// still-growing/not-yet-final trailing paragraph), if any — reused by `nextID()` instead
    /// of minting a fresh one. Without this, every call re-derives the tail from scratch and
    /// hands it a brand-new id, so the actively-streaming block's identity changes on every
    /// flush: `MarkdownView`'s `ForEach` sees it as a new row each time, and `.appearOnce()`
    /// replays its fade-in on every ~16ms tick instead of staying stable like the doc comment
    /// on that modifier promises. Cleared the moment that block is actually folded into
    /// `settled` — see `nextID()`.
    private var pendingBlockID: Int?

    /// Reuses `pendingBlockID` when set (and clears it — a given reuse is one-shot); mints and
    /// advances `nextBlockID` otherwise. Callers that construct a block which might still be
    /// unsettled when this call returns (the fence and paragraph branches) are responsible for
    /// re-arming `pendingBlockID` with the id this returns if that block is, in fact, still
    /// unsettled — see those call sites.
    private mutating func nextID() -> Int {
        if let pending = pendingBlockID {
            pendingBlockID = nil
            return pending
        }
        defer { nextBlockID += 1 }
        return nextBlockID
    }

    /// Returns the blocks for `source`, re-parsing only the unsettled tail.
    mutating func blocks(for source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: "\n")
        guard settledLineIndex <= lines.count else {
            // Source was replaced rather than appended (regenerate). Start over.
            reset()
            return blocks(for: source)
        }

        var result = settled
        var index = settledLineIndex
        var newlySettledIndex = settledLineIndex
        var newlySettled: [MarkdownBlock] = []

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                newlySettledIndex = index
                continue
            }

            // Fenced code block. Settled only once the closing fence arrives, so a
            // half-streamed block keeps re-parsing until it is complete.
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                var cursor = index + 1
                var closed = false
                while cursor < lines.count {
                    if lines[cursor].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        closed = true
                        break
                    }
                    code.append(lines[cursor])
                    cursor += 1
                }
                let id = nextID()
                let block = MarkdownBlock.codeBlock(
                    id: id,
                    language: language.isEmpty ? nil : language,
                    code: code.joined(separator: "\n")
                )
                if closed {
                    newlySettled.append(block)
                    index = cursor + 1
                    newlySettledIndex = index
                } else {
                    // Still open: this exact id must survive to the next call, or the fence's
                    // identity churns every flush while it streams in.
                    pendingBlockID = id
                    result.append(contentsOf: newlySettled)
                    result.append(block)
                    settled.append(contentsOf: newlySettled)
                    settledLineIndex = newlySettledIndex
                    return result
                }
                continue
            }

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if hashes <= 6, trimmed.dropFirst(hashes).hasPrefix(" ") {
                    let text = String(trimmed.dropFirst(hashes + 1))
                    newlySettled.append(.heading(id: nextBlockID, level: hashes, text: Self.inline(text)))
                    nextBlockID += 1
                    index += 1
                    newlySettledIndex = index
                    continue
                }
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                newlySettled.append(.divider(id: nextBlockID))
                nextBlockID += 1
                index += 1
                newlySettledIndex = index
                continue
            }

            if Self.isBullet(trimmed) {
                var items: [AttributedString] = []
                var cursor = index
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard Self.isBullet(candidate) else { break }
                    items.append(Self.inline(String(candidate.dropFirst(2))))
                    cursor += 1
                }
                newlySettled.append(.bulletList(id: nextBlockID, items: items))
                nextBlockID += 1
                index = cursor
                newlySettledIndex = index
                continue
            }

            if let _ = Self.numberedPrefix(trimmed) {
                var items: [AttributedString] = []
                var cursor = index
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard let dropped = Self.numberedPrefix(candidate) else { break }
                    items.append(Self.inline(dropped))
                    cursor += 1
                }
                newlySettled.append(.numberedList(id: nextBlockID, items: items))
                nextBlockID += 1
                index = cursor
                newlySettledIndex = index
                continue
            }

            if trimmed.hasPrefix("> ") {
                var parts: [String] = []
                var cursor = index
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix("> ") else { break }
                    parts.append(String(candidate.dropFirst(2)))
                    cursor += 1
                }
                newlySettled.append(.quote(id: nextBlockID, text: Self.inline(parts.joined(separator: " "))))
                nextBlockID += 1
                index = cursor
                newlySettledIndex = index
                continue
            }

            // Paragraph: runs until a blank line or a line that starts another block. The
            // first line always belongs to this paragraph regardless of its own shape — it
            // already failed every other classifier above, including the heading check just
            // above: a bare "#", or any hash run with nothing (or no space) after it, starts
            // with "#" but isn't a *valid* heading, so it falls through to here. Excluding
            // `cursor == index` from the break is what makes that safe: without it, that same
            // line would immediately "end" a zero-line paragraph, `cursor` would equal `index`
            // going into the branch below, and the outer `while index < lines.count` loop
            // would re-evaluate the identical line forever. This was a real, deterministic CI
            // hang (docs/RESEARCH_LOG.md), not a hypothetical.
            var parts: [String] = []
            var cursor = index
            while cursor < lines.count {
                let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                if cursor > index,
                    candidate.isEmpty || candidate.hasPrefix("```") || candidate.hasPrefix("#")
                    || candidate.hasPrefix("> ") || Self.isBullet(candidate)
                    || Self.numberedPrefix(candidate) != nil {
                    break
                }
                parts.append(candidate)
                cursor += 1
            }
            let id = nextID()
            let paragraph = MarkdownBlock.paragraph(
                id: id,
                text: Self.inline(parts.joined(separator: " "))
            )

            // A paragraph at the very end of the source may still be growing, so it is not
            // settled until a following line proves it finished.
            if cursor < lines.count {
                // A following line already proved this paragraph finished, so it is about to
                // be folded into `settled` (via `newlySettled` at whichever return below this
                // call hits) — `id` is now permanent, nothing to re-arm.
                newlySettled.append(paragraph)
                index = cursor
                newlySettledIndex = index
            } else {
                // Still the last thing in the source: this exact id must survive to the next
                // call, or the actively-streaming paragraph's identity churns every flush.
                pendingBlockID = id
                result.append(contentsOf: newlySettled)
                result.append(paragraph)
                settled.append(contentsOf: newlySettled)
                settledLineIndex = newlySettledIndex
                return result
            }
        }

        settled.append(contentsOf: newlySettled)
        settledLineIndex = newlySettledIndex
        return settled
    }

    mutating func reset() {
        settled = []
        settledLineIndex = 0
        nextBlockID = 0
        pendingBlockID = nil
    }

    // MARK: Helpers

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func numberedPrefix(_ line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return String(rest.dropFirst(2))
    }

    /// Inline formatting — bold, italic, inline code, links — via the system parser.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - View

struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.tight + 2) {
            ForEach(blocks) { block in
                blockView(block)
                    // Each block fades in once, when it first appears. Because block ids are
                    // stable, a block already on screen never re-animates as the stream
                    // grows — and the text inside is never animated per token, which would
                    // look cheap and cost a layout pass each time.
                    .appearOnce()
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        Group {
            switch block {
                case .paragraph(_, let text):
                    Text(text)
                        .assistantProse()
                        .textSelection(.enabled)

                case .heading(_, let level, let text):
                    Text(text)
                        .font(headingFont(level))
                        .fontWeight(.semibold)
                        .padding(.top, Space.tight)
                        .textSelection(.enabled)
                        // Lets VoiceOver's heading rotor jump straight to this block, matching
                        // what it visually already is.
                        .accessibilityAddTraits(.isHeader)

                case .bulletList(_, let items):
                    VStack(alignment: .leading, spacing: Space.hair + 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline, spacing: Space.tight) {
                                // Hidden from accessibility: purely decorative, and reading
                                // order already conveys "this is a list item" without it.
                                Text("•")
                                    .foregroundStyle(Palette.textTertiary)
                                    .accessibilityHidden(true)
                                Text(item).textSelection(.enabled)
                            }
                            // One VoiceOver stop per item instead of two ("•", then the text).
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .font(.body)

                case .numberedList(_, let items):
                    VStack(alignment: .leading, spacing: Space.hair + 2) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: Space.tight) {
                                Text("\(index + 1).")
                                    .monospacedDigit()
                                    .foregroundStyle(Palette.textTertiary)
                                Text(item).textSelection(.enabled)
                            }
                            // Unlike the bullet, the numeral is real information (position),
                            // so it stays audible — just combined into one stop per item.
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .font(.body)

                case .codeBlock(_, let language, let code):
                    CodeBlockView(language: language, code: code)

                case .quote(_, let text):
                    HStack(alignment: .top, spacing: Space.base) {
                        Rectangle()
                            .fill(Palette.separator)
                            .frame(width: 2)
                        Text(text)
                            .font(.body)
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                    }

                case .divider:
                    Rectangle()
                        .fill(Palette.separator)
                        .frame(height: 0.5)
                        .padding(.vertical, Space.tight)
                }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        default: return .headline
        }
    }
}

// MARK: - Code block

struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: Space.tight)
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.quiet)
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, Space.tight + 2)
            .padding(.top, Space.hair)

            // Horizontal scroll rather than wrapping: wrapped code is unreadable, and this
            // keeps indentation meaningful.
            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.tight + 2)
                    .padding(.vertical, Space.tight)
            }
        }
        // No glass here — a code block contains content, not chrome.
        .background(
            Palette.canvasRaised,
            in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Palette.separator.opacity(0.5), lineWidth: 0.5)
        )
        .haptic(.selection, trigger: copied)
    }
}

// MARK: - Syntax highlighting

/// A deliberately small highlighter: comments, strings, numbers and keywords. Enough to make
/// code readable, small enough not to justify a dependency (docs/DEPENDENCIES.md).
enum SyntaxHighlighter {
    private static let keywords: [String: Set<String>] = [
        "swift": ["func", "let", "var", "if", "else", "guard", "return", "struct", "class",
                  "enum", "protocol", "extension", "import", "for", "in", "while", "switch",
                  "case", "default", "async", "await", "throws", "try", "self", "init",
                  "private", "public", "static", "some", "any", "nil", "true", "false"],
        "python": ["def", "class", "if", "elif", "else", "return", "import", "from", "for",
                   "in", "while", "with", "as", "try", "except", "raise", "lambda", "None",
                   "True", "False", "async", "await", "yield", "pass"],
        "javascript": ["function", "const", "let", "var", "if", "else", "return", "class",
                       "import", "export", "from", "for", "while", "switch", "case", "async",
                       "await", "try", "catch", "throw", "new", "this", "null", "true", "false"],
        "json": ["true", "false", "null"],
        "bash": ["if", "then", "else", "fi", "for", "in", "do", "done", "while", "case",
                 "esac", "function", "echo", "export", "local", "return"],
        "yaml": ["true", "false", "null"],
    ]

    static func highlight(_ code: String, language: String?) -> AttributedString {
        var output = AttributedString(code)
        output.foregroundColor = Palette.textPrimary

        let key = (language ?? "").lowercased()
        let set = keywords[key]
            ?? keywords[alias(for: key) ?? ""]
            ?? keywords["swift"]!

        for line in code.components(separatedBy: "\n") {
            // Comments win over everything else on the line.
            if let commentRange = commentRange(in: line, language: key) {
                apply(Palette.textTertiary, to: String(line[commentRange...]), in: &output)
                continue
            }
            for token in line.split(whereSeparator: { !$0.isLetter && $0 != "_" }) {
                if set.contains(String(token)) {
                    apply(Color.accentColor, to: String(token), in: &output, wholeWord: true)
                }
            }
        }
        return output
    }

    private static func alias(for language: String) -> String? {
        switch language {
        case "js", "ts", "typescript", "tsx", "jsx": return "javascript"
        case "py": return "python"
        case "sh", "zsh", "shell": return "bash"
        case "yml": return "yaml"
        default: return nil
        }
    }

    private static func commentRange(in line: String, language: String) -> String.Index? {
        let markers = ["python", "bash", "yaml", "yml", "sh"].contains(language) ? ["#"] : ["//"]
        for marker in markers {
            if let range = line.range(of: marker) { return range.lowerBound }
        }
        return nil
    }

    private static func apply(
        _ color: Color,
        to token: String,
        in output: inout AttributedString,
        wholeWord: Bool = false
    ) {
        guard !token.isEmpty else { return }
        var searchStart = output.startIndex
        while let range = output[searchStart...].range(of: token) {
            if !wholeWord || isWholeWord(range, in: output) {
                output[range].foregroundColor = color
            }
            searchStart = range.upperBound
            if searchStart >= output.endIndex { break }
        }
    }

    private static func isWholeWord(
        _ range: Range<AttributedString.Index>,
        in text: AttributedString
    ) -> Bool {
        let characters = text.characters
        let before: Character? = range.lowerBound > text.startIndex
            ? characters[characters.index(before: range.lowerBound)]
            : nil
        let after: Character? = range.upperBound < text.endIndex
            ? characters[range.upperBound]
            : nil
        func isWordChar(_ c: Character?) -> Bool {
            guard let c else { return false }
            return c.isLetter || c.isNumber || c == "_"
        }
        return !isWordChar(before) && !isWordChar(after)
    }
}
