import SwiftUI
import SwiftTerm

struct TerminalHostView: UIViewRepresentable {
    let tabId: String
    @EnvironmentObject var sessionManager: SessionManager

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.backgroundColor = .black

        // Register data callback — feeds incoming PTY data into this view
        sessionManager.onData[tabId] = { [weak view] chunk in
            DispatchQueue.main.async {
                view?.feed(text: chunk)
            }
        }

        // Register focus callback — lets ContentView bring up the keyboard
        sessionManager.focusTerminal = { [weak view] in
            view?.becomeFirstResponder()
        }

        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.sessionManager.onData.removeValue(forKey: coordinator.tabId)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tabId: tabId, sessionManager: sessionManager)
    }

    class Coordinator: NSObject, TerminalViewDelegate {
        let tabId: String
        let sessionManager: SessionManager

        init(tabId: String, sessionManager: SessionManager) {
            self.tabId = tabId
            self.sessionManager = sessionManager
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let str = String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
            sessionManager.sendInput(str)
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            sessionManager.resize(tabId: tabId, cols: newCols, rows: newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func scrolled(source: TerminalView, position: Double) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String:String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
