import SwiftUI

// MARK: - 色

enum Palette {
    static let accent = Color.accentColor
    static let ok = Color.green
    static let ng = Color.red
    static let codeBackground = Color(.secondarySystemBackground)
    static let keyword = Color.purple
    static let string = Color(red: 0.18, green: 0.55, blue: 0.27)
    static let comment = Color.secondary
}

// MARK: - インライン Markdown（`code` と **太字**）

func md(_ s: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: s, options: options)) ?? AttributedString(s)
}

// MARK: - Java のシンタックスハイライト（キーワード・文字列・コメント）

enum JavaHighlighter {
    static let keywords: Set<String> = [
        "abstract", "boolean", "break", "byte", "case", "catch", "char", "class", "continue",
        "default", "do", "double", "else", "enum", "extends", "final", "finally", "float", "for",
        "if", "implements", "import", "instanceof", "int", "interface", "long", "new", "non",
        "null", "package", "permits", "private", "protected", "public", "record", "return",
        "sealed", "short", "static", "super", "switch", "this", "throw", "throws", "true",
        "false", "try", "var", "void", "when", "while", "yield"
    ]

    static func highlight(_ code: String) -> AttributedString {
        let chars = Array(code)
        var out = AttributedString()
        var i = 0

        func add(_ s: String, _ color: Color? = nil, bold: Bool = false) {
            var a = AttributedString(s)
            if let color { a.foregroundColor = color }
            if bold { a.font = Font.system(.footnote, design: .monospaced).weight(.semibold) }
            out += a
        }

        while i < chars.count {
            let c = chars[i]
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                var j = i
                while j < chars.count, chars[j] != "\n" { j += 1 }
                add(String(chars[i..<j]), Palette.comment)
                i = j
            } else if c == "\"" || c == "'" {
                var j = i + 1
                while j < chars.count, chars[j] != c, chars[j] != "\n" {
                    j += chars[j] == "\\" ? 2 : 1
                }
                j = min(j + 1, chars.count)
                add(String(chars[i..<j]), Palette.string)
                i = j
            } else if c.isLetter || c == "_" {
                var j = i
                while j < chars.count, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                let word = String(chars[i..<j])
                if keywords.contains(word) {
                    add(word, Palette.keyword, bold: true)
                } else {
                    add(word)
                }
                i = j
            } else {
                var j = i
                while j < chars.count {
                    let d = chars[j]
                    if d.isLetter || d == "_" || d == "\"" || d == "'" { break }
                    if d == "/", j + 1 < chars.count, chars[j + 1] == "/" { break }
                    j += 1
                }
                add(String(chars[i..<j]))
                i = j
            }
        }
        return out
    }
}

// MARK: - 本文ブロック

struct CodeBlockView: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(JavaHighlighter.highlight(code))
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: true, vertical: true)
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.codeBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct BlockView: View {
    let block: Block

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(md(text))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Palette.accent)
                        Text(md(item)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .table(let header, let rows):
            TableBlockView(header: header, rows: rows)
        case .code(let code):
            CodeBlockView(code: code)
        }
    }
}

struct TableBlockView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    ForEach(header.indices, id: \.self) { i in
                        Text(md(header[i])).font(.caption.bold()).foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(rows.indices, id: \.self) { r in
                    GridRow {
                        ForEach(rows[r].indices, id: \.self) { c in
                            Text(md(rows[r][c]))
                                .font(.subheadline)
                                .frame(maxWidth: 240, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if r < rows.count - 1 { Divider().opacity(0.5) }
                }
            }
            .padding(12)
        }
        .background(Palette.codeBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 進捗リング

struct ProgressRing: View {
    let value: Double
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(.title3, design: .rounded).bold())
                .monospacedDigit()
        }
    }
}

// MARK: - 横並びで折り返すレイアウト（タグ用）

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

struct TagView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35)))
    }
}
