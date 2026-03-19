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

        // Vertical pan = scroll within TUI (sends mouse wheel events to Claude Code)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

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
        private var panAccumulator: CGFloat = 0
        private let scrollThreshold: CGFloat = 20  // pixels per scroll line

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

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            let translation = pan.translation(in: pan.view)

            switch pan.state {
            case .began:
                panAccumulator = 0
            case .changed:
                panAccumulator += translation.y
                pan.setTranslation(.zero, in: pan.view)

                // Send scroll events for each threshold crossed
                while panAccumulator > scrollThreshold {
                    panAccumulator -= scrollThreshold
                    // Scroll down (finger moves down = content scrolls up = mouse wheel down)
                    // SGR mouse protocol: button 65 = scroll down
                    sessionManager.sendInput("\u{1b}[<65;1;1M")
                }
                while panAccumulator < -scrollThreshold {
                    panAccumulator += scrollThreshold
                    // Scroll up (finger moves up = content scrolls down = mouse wheel up)
                    // SGR mouse protocol: button 64 = scroll up
                    sessionManager.sendInput("\u{1b}[<64;1;1M")
                }
            default:
                panAccumulator = 0
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
