import SwiftUI

struct TranscriptView: View {
    let messages: [[String: String]]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { idx, msg in
                        let isUser = msg["role"] == "user"
                        Text(msg["text"] ?? "")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(isUser ? .white : Color(.systemGray))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
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
