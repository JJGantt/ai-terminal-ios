import SwiftUI
import SwiftTerm

struct TerminalHostView: UIViewRepresentable {
    let tabId: String
    let voiceRecorder: VoiceRecorder
    @EnvironmentObject var sessionManager: SessionManager

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = context.coordinator
        view.backgroundColor = .black

        // Feed cached scrollback immediately (survives background/foreground)
        if let cached = sessionManager.getCachedScrollback(for: tabId) {
            view.feed(text: cached)
        }

        // Register data callback
        sessionManager.onData[tabId] = { [weak view] chunk in
            DispatchQueue.main.async { view?.feed(text: chunk) }
        }

        // Register focus callback for keyboard button
        sessionManager.focusTerminal = { [weak view] in
            view?.becomeFirstResponder()
        }

        // Tap = start/stop recording (also prevents terminal auto-focus)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = true
        view.addGestureRecognizer(tap)

        // Swipe left/right = switch tabs
        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)

        // Pinch to zoom = change font size
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        // Apply saved font size
        let savedSize = UserDefaults.standard.double(forKey: "terminalFontSize")
        if savedSize > 0 {
            view.font = UIFont.monospacedSystemFont(ofSize: savedSize, weight: .regular)
        }

        // Send initial resize once layout is known
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak view] in
            guard let view else { return }
            let cols = view.getTerminal().cols
            let rows = view.getTerminal().rows
            if cols > 0 && rows > 0 {
                sessionManager.resize(tabId: tabId, cols: cols, rows: rows)
            }
        }

        // Re-send resize when app becomes active (returning from background or app switcher)
        context.coordinator.foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak view] _ in
            guard let view else { return }
            let cols = view.getTerminal().cols
            let rows = view.getTerminal().rows
            if cols > 0 && rows > 0 {
                sessionManager.resize(tabId: tabId, cols: cols, rows: rows)
            }
        }

        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.sessionManager.onData.removeValue(forKey: coordinator.tabId)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(tabId: tabId, sessionManager: sessionManager, voiceRecorder: voiceRecorder)
    }

    class Coordinator: NSObject, TerminalViewDelegate, UIGestureRecognizerDelegate {
        let tabId: String
        let sessionManager: SessionManager
        let voiceRecorder: VoiceRecorder
        var foregroundObserver: NSObjectProtocol?
        private var pinchBaseFontSize: CGFloat = 0

        init(tabId: String, sessionManager: SessionManager, voiceRecorder: VoiceRecorder) {
            self.tabId = tabId
            self.sessionManager = sessionManager
            self.voiceRecorder = voiceRecorder
        }

        // Allow pan + swipe to coexist
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        deinit {
            if let observer = foregroundObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        @objc func handleTap() {
            switch voiceRecorder.state {
            case .idle:        voiceRecorder.start()
            case .recording:   voiceRecorder.stop()
            case .transcribing: break
            }
        }

        @objc func handleSwipeLeft()  { sessionManager.switchTab(delta: 1) }
        @objc func handleSwipeRight() { sessionManager.switchTab(delta: -1) }

        @objc func handlePinch(_ pinch: UIPinchGestureRecognizer) {
            guard let view = pinch.view as? TerminalView else { return }
            switch pinch.state {
            case .began:
                pinchBaseFontSize = view.font.pointSize
            case .changed:
                let newSize = min(max(pinchBaseFontSize * pinch.scale, 6), 32)
                view.font = UIFont.monospacedSystemFont(ofSize: newSize, weight: .regular)
            case .ended, .cancelled:
                let finalSize = view.font.pointSize
                UserDefaults.standard.set(finalSize, forKey: "terminalFontSize")
                // sizeChanged delegate fires automatically → sends resize to server
            default: break
            }
        }

        // MARK: — TerminalViewDelegate

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
