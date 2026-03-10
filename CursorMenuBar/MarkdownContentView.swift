import SwiftUI

// MARK: - Block-level markdown parser & renderer
//
// SwiftUI's `Text(AttributedString(markdown:))` handles inline formatting (bold,
// italic, code, links) but does NOT visually render block-level structure (paragraphs,
// lists, headings, code fences). This view parses markdown into blocks and renders
// each as a separate SwiftUI view with proper spacing and styling.

// MARK: - Block model

private enum BlockKind: Equatable {
    case paragraph
    case heading(level: Int)
    case bulletList
    case numberedList
    case codeBlock(language: String)
    case blockquote
    case horizontalRule
}

private struct Block: Identifiable {
    let id: Int
    let kind: BlockKind
    let content: String
    var items: [String]

    init(id: Int, kind: BlockKind, content: String, items: [String] = []) {
        self.id = id
        self.kind = kind
        self.content = content
        self.items = items
    }
}

// MARK: - Parser

private func parseBlocks(_ text: String) -> [Block] {
    let lines = text.components(separatedBy: "\n")
    var blocks: [Block] = []
    var idx = 0
    var blockID = 0

    func nextID() -> Int { defer { blockID += 1 }; return blockID }

    while idx < lines.count {
        let line = lines[idx]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty { idx += 1; continue }

        // --- Code fence ---
        if trimmed.hasPrefix("```") {
            let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var codeLines: [String] = []
            idx += 1
            while idx < lines.count {
                if lines[idx].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    idx += 1; break
                }
                codeLines.append(lines[idx])
                idx += 1
            }
            blocks.append(Block(id: nextID(), kind: .codeBlock(language: lang), content: codeLines.joined(separator: "\n")))
            continue
        }

        // --- Horizontal rule ---
        if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" || $0 == " " }),
           trimmed.filter({ $0 != " " }).count >= 3,
           Set(trimmed.filter { $0 != " " }).count == 1 {
            blocks.append(Block(id: nextID(), kind: .horizontalRule, content: ""))
            idx += 1; continue
        }

        // --- Heading ---
        if let m = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
            let level = trimmed[m].filter { $0 == "#" }.count
            let content = String(trimmed[m.upperBound...])
            blocks.append(Block(id: nextID(), kind: .heading(level: level), content: content))
            idx += 1; continue
        }

        // --- Bullet list ---
        if isBulletLine(trimmed) {
            var items: [String] = []
            while idx < lines.count {
                let l = lines[idx].trimmingCharacters(in: .whitespaces)
                if l.isEmpty { break }
                if isBulletLine(l) {
                    items.append(stripBulletPrefix(l))
                } else if !items.isEmpty {
                    items[items.count - 1] += " " + l
                } else { break }
                idx += 1
            }
            blocks.append(Block(id: nextID(), kind: .bulletList, content: "", items: items))
            continue
        }

        // --- Numbered list ---
        if isNumberedLine(trimmed) {
            var items: [String] = []
            while idx < lines.count {
                let l = lines[idx].trimmingCharacters(in: .whitespaces)
                if l.isEmpty { break }
                if isNumberedLine(l) {
                    items.append(stripNumberPrefix(l))
                } else if !items.isEmpty {
                    items[items.count - 1] += " " + l
                } else { break }
                idx += 1
            }
            blocks.append(Block(id: nextID(), kind: .numberedList, content: "", items: items))
            continue
        }

        // --- Blockquote ---
        if trimmed.hasPrefix(">") {
            var quoteLines: [String] = []
            while idx < lines.count {
                let l = lines[idx].trimmingCharacters(in: .whitespaces)
                if l.isEmpty { break }
                if l.hasPrefix(">") {
                    var stripped = String(l.dropFirst())
                    if stripped.hasPrefix(" ") { stripped = String(stripped.dropFirst()) }
                    quoteLines.append(stripped)
                } else {
                    quoteLines.append(l)
                }
                idx += 1
            }
            blocks.append(Block(id: nextID(), kind: .blockquote, content: quoteLines.joined(separator: " ")))
            continue
        }

        // --- Paragraph: collect lines until blank or block-start ---
        var paraLines: [String] = []
        while idx < lines.count {
            let l = lines[idx]
            let tl = l.trimmingCharacters(in: .whitespaces)
            if tl.isEmpty { break }
            if !paraLines.isEmpty && isBlockStart(tl) { break }
            paraLines.append(l)
            idx += 1
        }
        let joined = paraLines.joined(separator: " ")
        if !joined.trimmingCharacters(in: .whitespaces).isEmpty {
            blocks.append(Block(id: nextID(), kind: .paragraph, content: joined))
        }
    }

    return blocks
}

private func isBulletLine(_ line: String) -> Bool {
    line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
}

private func stripBulletPrefix(_ line: String) -> String {
    if line.hasPrefix("- ") { return String(line.dropFirst(2)) }
    if line.hasPrefix("* ") { return String(line.dropFirst(2)) }
    if line.hasPrefix("• ") { return String(line.dropFirst(2)) }
    return line
}

private func isNumberedLine(_ line: String) -> Bool {
    line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil
}

private func stripNumberPrefix(_ line: String) -> String {
    guard let m = line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) else { return line }
    return String(line[m.upperBound...])
}

private func isBlockStart(_ line: String) -> Bool {
    line.hasPrefix("```") ||
    line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) != nil ||
    isBulletLine(line) ||
    isNumberedLine(line) ||
    line.hasPrefix(">")
}

// MARK: - Inline markdown helper

private func inlineMarkdown(_ text: String) -> AttributedString {
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
}

// MARK: - View

struct MarkdownContentView: View {
    let text: String
    let baseFontSize: CGFloat

    init(_ text: String, fontSize: CGFloat = 14) {
        self.text = text
        self.baseFontSize = fontSize
    }

    private var blocks: [Block] { parseBlocks(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(inlineMarkdown(block.content))
                .font(.system(size: headingSize(level), weight: .semibold))
                .foregroundStyle(CursorTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

        case .paragraph:
            Text(inlineMarkdown(block.content))
                .font(.system(size: baseFontSize))
                .foregroundStyle(CursorTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

        case .bulletList:
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.system(size: baseFontSize))
                            .foregroundStyle(CursorTheme.textSecondary)
                        Text(inlineMarkdown(item))
                            .font(.system(size: baseFontSize))
                            .foregroundStyle(CursorTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 6)

        case .numberedList:
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(index + 1).")
                            .font(.system(size: baseFontSize, weight: .medium, design: .monospaced))
                            .foregroundStyle(CursorTheme.textSecondary)
                            .frame(width: 26, alignment: .trailing)
                        Text(inlineMarkdown(item))
                            .font(.system(size: baseFontSize))
                            .foregroundStyle(CursorTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 4)

        case .codeBlock(let language):
            VStack(alignment: .leading, spacing: 0) {
                if !language.isEmpty {
                    Text(language)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CursorTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                }
                Text(block.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CursorTheme.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CursorTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(CursorTheme.border, lineWidth: 1)
            )

        case .blockquote:
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(CursorTheme.textTertiary.opacity(0.5))
                    .frame(width: 3)
                Text(inlineMarkdown(block.content))
                    .font(.system(size: baseFontSize))
                    .foregroundStyle(CursorTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 10)
            }
            .padding(.leading, 4)

        case .horizontalRule:
            Rectangle()
                .fill(CursorTheme.border)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return baseFontSize + 6
        case 2: return baseFontSize + 4
        case 3: return baseFontSize + 2
        default: return baseFontSize + 1
        }
    }
}
