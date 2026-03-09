import Foundation
import Combine

struct TabInfo: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var working: Bool
}

class SessionManager: ObservableObject {
    @Published var tabs: [TabInfo] = []
    @Published var activeTabId: String?
    @Published var connected = false

    // Callbacks from TerminalHostView instances — fed when data arrives
    var onData: [String: (String) -> Void] = [:]
    // Called to focus the active terminal (show keyboard)
    var focusTerminal: (() -> Void)?

    private var webSocket: URLSessionWebSocketTask?
    private let urlSession = URLSession(configuration: .default)

    // Try local first (fast, same network), fall back to Tailscale (remote)
    private let hosts = ["Jareds-MacBook-Air.local", "100.106.101.57"]
    private var hostIndex = 0
    let wsPort = 27183

    func connect() {
        let host = hosts[hostIndex]
        guard let url = URL(string: "ws://\(host):\(wsPort)") else { return }
        print("[SessionManager] connecting to \(url)")
        webSocket = urlSession.webSocketTask(with: url)
        webSocket?.resume()
        receive()
    }

    private func receive() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    print("[SessionManager] message: \(text.prefix(120))")
                    self.handleMessage(text)
                }
                self.receive()
            case .failure(let error):
                print("[SessionManager] connection error: \(error)")
                DispatchQueue.main.async { self.connected = false }
                // Rotate through hosts on failure
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.hostIndex = (self.hostIndex + 1) % self.hosts.count
                    print("[SessionManager] reconnecting via \(self.hosts[self.hostIndex])...")
                    self.connect()
                }
            }
        }
    }

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
                let newTabs = rawTabs.compactMap { dict -> TabInfo? in
                    guard let id = dict["id"] as? String, let name = dict["name"] as? String else { return nil }
                    return TabInfo(id: id, name: name, working: dict["working"] as? Bool ?? false)
                }
                // Preserve active selection if still present
                self.tabs = newTabs
                if let active = self.activeTabId, !newTabs.contains(where: { $0.id == active }) {
                    self.activeTabId = newTabs.first?.id
                } else if self.activeTabId == nil {
                    if let first = newTabs.first {
                        self.subscribe(to: first.id)
                    }
                }
                self.connected = true

            case "scrollback", "data":
                guard
                    let tabId = json["tabId"] as? String,
                    let chunk = json["data"] as? String
                else { return }
                self.onData[tabId]?(chunk)

            default:
                break
            }
        }
    }

    func subscribe(to tabId: String) {
        activeTabId = tabId
        send(["type": "subscribe", "tabId": tabId])
    }

    func sendInput(_ text: String) {
        guard let tabId = activeTabId else { return }
        send(["type": "input", "tabId": tabId, "data": text])
    }

    func stopActive() {
        guard let tabId = activeTabId else { return }
        // Ctrl+C
        send(["type": "input", "tabId": tabId, "data": "\u{03}"])
    }

    func switchTab(delta: Int) {
        guard !tabs.isEmpty, let activeId = activeTabId,
              let currentIndex = tabs.firstIndex(where: { $0.id == activeId }) else { return }
        let newIndex = (currentIndex + delta + tabs.count) % tabs.count
        subscribe(to: tabs[newIndex].id)
    }

    func resize(tabId: String, cols: Int, rows: Int) {
        send(["type": "resize", "tabId": tabId, "cols": cols, "rows": rows])
    }

    func sendVoice(audioData: Data, durationS: Double) {
        guard let tabId = activeTabId else { return }
        let base64 = audioData.base64EncodedString()
        print("[SessionManager] sending voice audio \(String(format: "%.1f", durationS))s to tab \(tabId)")
        send(["type": "voice_audio", "tabId": tabId, "data": base64, "durationS": durationS])
    }

    private func send(_ dict: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let text = String(data: data, encoding: .utf8)
        else { return }
        webSocket?.send(.string(text)) { _ in }
    }
}
