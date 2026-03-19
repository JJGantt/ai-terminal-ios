import Foundation

/// Manages a single WebSocket connection to one host (Mac or Pi).
/// Reconnects automatically, rotating through the provided host list on failure.
class HostConnection: ObservableObject {
    let hostId: String       // "mac" or "pi"
    private let hosts: [String]
    private let port = 27183

    @Published var connected = false
    @Published var tabs: [TabInfo] = []
    @Published var historySessions: [HistorySession] = []

    /// Called with (tabId, chunk) when PTY data arrives.
    var onData: ((String, String) -> Void)?
    /// Called with tabId when a phone-initiated tab is created.
    var onTabCreated: ((String) -> Void)?
    /// Called when connection is (re)established — used to re-subscribe active tab.
    var onConnected: (() -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)
    private var hostIndex = 0
    private var activeTabId: String?
    private var retryWork: DispatchWorkItem?

    init(hostId: String, hosts: [String]) {
        self.hostId = hostId
        self.hosts  = hosts
    }

    // MARK: - Connection

    func connect() {
        // Cancel any pending retry
        retryWork?.cancel()
        retryWork = nil
        // Close stale socket
        webSocket?.cancel(with: .goingAway, reason: nil)

        let host = hosts[hostIndex]
        guard let url = URL(string: "ws://\(host):\(port)") else { return }
        print("[\(hostId)] connecting to \(url)")
        webSocket = urlSession.webSocketTask(with: url)
        webSocket?.resume()
        receive()
    }

    /// Immediately reconnect if not already connected (e.g. returning from background).
    func reconnectIfNeeded() {
        guard !connected else { return }
        print("[\(hostId)] reconnectIfNeeded: forcing immediate reconnect")
        connect()
    }

    private func scheduleRetry() {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hostIndex = (self.hostIndex + 1) % self.hosts.count
            self.connect()
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func receive() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handleMessage(text) }
                self.receive()
            case .failure(let error):
                print("[\(self.hostId)] error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.connected = false
                    self.scheduleRetry()
                }
            }
        }
    }

    // MARK: - Message handling

    private func handleMessage(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        DispatchQueue.main.async {
            switch type {
            case "sessions":
                guard let rawTabs = json["tabs"] as? [[String: Any]] else { return }
                let parsed = rawTabs.compactMap { dict -> TabInfo? in
                    guard let id   = dict["id"]   as? String,
                          let name = dict["name"] as? String else { return nil }
                    return TabInfo(id: id, name: name,
                                   working: dict["working"] as? Bool ?? false,
                                   host: self.hostId)
                }
                let oldIds = self.tabs.map(\.id)
                let newIds = parsed.map(\.id)
                print("[\(self.hostId)] sessions: \(oldIds.count) → \(newIds.count), old=\(oldIds.map { String($0.prefix(8)) }), new=\(newIds.map { String($0.prefix(8)) })")
                let wasConnected = self.connected
                self.tabs = parsed
                self.connected = true
                // Re-subscribe after reconnect
                if !wasConnected {
                    self.onConnected?()
                }

            case "scrollback", "data":
                guard let tabId = json["tabId"] as? String,
                      let chunk = json["data"]  as? String else { return }
                self.onData?(tabId, chunk)

            case "tab_created":
                guard let tabId = json["tabId"] as? String else {
                    print("[\(self.hostId)] tab_created: missing tabId")
                    return
                }
                print("[\(self.hostId)] tab_created received: \(tabId), onTabCreated=\(self.onTabCreated != nil)")
                self.onTabCreated?(tabId)

            case "history":
                guard let raw = json["sessions"] as? [[String: Any]] else { return }
                self.historySessions = raw.compactMap { dict -> HistorySession? in
                    guard let id        = dict["id"]        as? String,
                          let title     = dict["title"]     as? String,
                          let timestamp = dict["timestamp"] as? String else { return nil }
                    let source = dict["source"] as? String ?? ""
                    let host = source.contains("pi") ? "pi" : "mac"
                    return HistorySession(id: id, title: title, timestamp: timestamp, host: host)
                }

            default: break
            }
        }
    }

    // MARK: - Outbound actions

    func subscribe(to tabId: String) {
        activeTabId = tabId
        send(["type": "subscribe", "tabId": tabId])
    }

    func sendInput(_ text: String, tabId: String) {
        send(["type": "input", "tabId": tabId, "data": text])
    }

    func stopActive(tabId: String) {
        send(["type": "input", "tabId": tabId, "data": "\u{03}"])
    }

    func resize(tabId: String, cols: Int, rows: Int) {
        send(["type": "resize", "tabId": tabId, "cols": cols, "rows": rows])
    }

    func sendVoice(audioData: Data, durationS: Double, tabId: String) {
        let base64 = audioData.base64EncodedString()
        send(["type": "voice_audio", "tabId": tabId, "data": base64, "durationS": durationS])
    }

    func killTab(_ tabId: String) {
        print("[\(hostId)] killTab: \(tabId)")
        send(["type": "kill_tab", "tabId": tabId])
    }

    func newTab(cols: Int = 0, rows: Int = 0) {
        print("[\(hostId)] newTab called, connected=\(connected), ws=\(webSocket != nil), \(cols)x\(rows)")
        var msg: [String: Any] = ["type": "new_tab"]
        if cols > 0 && rows > 0 { msg["cols"] = cols; msg["rows"] = rows }
        send(msg)
    }
    func resumeTab(sessionId: String, cols: Int = 0, rows: Int = 0) {
        var msg: [String: Any] = ["type": "resume_tab", "sessionId": sessionId]
        if cols > 0 && rows > 0 { msg["cols"] = cols; msg["rows"] = rows }
        send(msg)
    }
    func requestHistory()                { send(["type": "history_request"]) }
    func regenerateName(sessionId: String) { send(["type": "regenerate_name", "sessionId": sessionId]) }

    func send(_ dict: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let text = String(data: data, encoding: .utf8)
        else {
            print("[\(hostId)] send: serialization failed for \(dict)")
            return
        }
        guard let ws = webSocket else {
            print("[\(hostId)] send: webSocket is nil, dropping \(dict["type"] ?? "?")")
            return
        }
        print("[\(hostId)] sending: \(text.prefix(120))")
        ws.send(.string(text)) { error in
            if let error { print("[\(self.hostId)] send error: \(error)") }
        }
    }
}
