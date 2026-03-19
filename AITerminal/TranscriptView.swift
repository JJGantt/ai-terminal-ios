import SwiftUI

struct TranscriptView: View {
    let messages: [[String: String]]
    var fontSize: Double = 13

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { idx, msg in
                        let isUser = msg["role"] == "user"
                        MarkdownMessage(text: msg["text"] ?? "", isUser: isUser, fontSize: fontSize)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(isUser ? Color.white.opacity(0.05) : .clear)
                            .id(idx)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
            }
            .background(.black)
            .onChange(of: messages.count) { _, _ in
                proxy.scrollTo("bottom")
            }
            .onAppear {
                proxy.scrollTo("bottom")
            }
        }
    }
}

// MARK: — Single message renderer

private struct MarkdownMessage: View {
    let text: String
    let isUser: Bool
    var fontSize: Double = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(splitCodeBlocks(text).enumerated()), id: \.offset) { _, block in
                if block.isCode {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.content)
                            .font(.system(size: fontSize - 1, design: .monospaced))
                            .foregroundStyle(Color.gray)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 6))
                } else if !block.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(attributed(block.content))
                        .font(.system(size: fontSize))
                        .foregroundStyle(isUser ? Color.white : Color.gray)
                }
            }
        }
    }

    private func attributed(_ raw: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlinesOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: raw, options: opts)) ?? AttributedString(raw)
    }
}

// MARK: — Code fence splitter

private struct Block {
    let isCode: Bool
    let content: String
}

private func splitCodeBlocks(_ text: String) -> [Block] {
    var result: [Block] = []
    var rest = text

    while let open = rest.range(of: "```") {
        let before = String(rest[..<open.lowerBound])
        if !before.isEmpty { result.append(Block(isCode: false, content: before)) }
        rest = String(rest[open.upperBound...])
        // skip optional language label on the same line
        if let nl = rest.firstIndex(of: "\n") {
            rest = String(rest[rest.index(after: nl)...])
        }
        if let close = rest.range(of: "```") {
            let code = String(rest[..<close.lowerBound])
            result.append(Block(isCode: true, content: code))
            rest = String(rest[close.upperBound...])
            if rest.hasPrefix("\n") { rest = String(rest.dropFirst()) }
        } else {
            result.append(Block(isCode: true, content: rest))
            rest = ""
        }
    }
    if !rest.isEmpty { result.append(Block(isCode: false, content: rest)) }
    return result.isEmpty ? [Block(isCode: false, content: text)] : result
}
