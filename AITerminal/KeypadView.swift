import SwiftUI

struct KeypadView: View {
    let onKey: (String) -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Arrow cluster
            VStack(spacing: 6) {
                arrowButton("↑", seq: "\u{1b}[A")
                HStack(spacing: 6) {
                    arrowButton("←", seq: "\u{1b}[D")
                    arrowButton("↓", seq: "\u{1b}[B")
                    arrowButton("→", seq: "\u{1b}[C")
                }
            }

            Divider().frame(height: 70)

            // Extra keys
            VStack(spacing: 6) {
                keyButton("Esc", seq: "\u{1b}")
                keyButton("Tab", seq: "\t")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }

    @ViewBuilder
    func arrowButton(_ label: String, seq: String) -> some View {
        Button { onKey(seq) } label: {
            Text(label)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 44, height: 38)
                .background(Color(uiColor: .systemGray4), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func keyButton(_ label: String, seq: String) -> some View {
        Button { onKey(seq) } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 52, height: 38)
                .background(Color(uiColor: .systemGray4), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}
