import SwiftUI
import SwiftTerm

/// A read-only terminal view that displays stripped scrollback content.
/// Used for scroll lock — shows a scrollable snapshot of past terminal output.
struct FrozenTerminalView: UIViewRepresentable {
    let content: String
    let onScrolledToBottom: () -> Void
    @EnvironmentObject var sessionManager: SessionManager

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.backgroundColor = .black

        // Match the live terminal's font size
        let savedSize = UserDefaults.standard.double(forKey: "terminalFontSize")
        if savedSize > 0 {
            view.font = UIFont.monospacedSystemFont(ofSize: savedSize, weight: .regular)
        }

        // Feed the stripped scrollback — renders in normal buffer with scrollback
        view.feed(text: content)

        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScrolledToBottom: onScrolledToBottom)
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        let onScrolledToBottom: () -> Void

        init(onScrolledToBottom: @escaping () -> Void) {
            self.onScrolledToBottom = onScrolledToBottom
        }

        func scrolled(source: TerminalView, position: Double) {
            // position 1.0 = scrolled to the very bottom
            if position >= 0.99 {
                DispatchQueue.main.async {
                    self.onScrolledToBottom()
                }
            }
        }

        // No-op delegates — this is read-only
        func send(source: TerminalView, data: ArraySlice<UInt8>) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String:String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
