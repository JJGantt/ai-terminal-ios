import Foundation
import Combine

struct TabInfo: Identifiable, Equatable {
    let id: String
    var name: String
    var working: Bool
    var host: String   // "mac" or "pi"
}

struct HistorySession: Identifiable {
    let id: String
    let title: String
    let timestamp: String
    let host: String   // "mac" or "pi"
}

class SessionManager: ObservableObject {
    let mac = HostConnection(hostId: "mac", hosts: ["Jareds-MacBook-Air.local", "100.106.101.57"])
    let pi  = HostConnection(hostId: "pi",  hosts: ["raspberrypi.local", "100.104.197.58"])

    @Published var tabs: [TabInfo] = []
    @Published var activeTabId: String?
    @Published var historySessions: [HistorySession] = []
    @Published var macConnected = false
    @Published var piConnected  = false

    var connected: Bool { macConnected || piConnected }

    /// Registered by TerminalHostView instances to receive PTY output.
    var onData: [String: (String) -> Void] = [:]
    /// Called to focus the active terminal (show keyboard).
    var focusTerminal: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()

    /// Maintains stable tab order — new tabs appended, removed tabs pruned.
    private var tabOrder: [String] = []

    init() {
        // Merge tabs from both connections, preserving creation order
        mac.$tabs.combineLatest(pi.$tabs)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] macTabs, piTabs in
                guard let self else { return }
                let incoming = macTabs + piTabs
                let incomingIds = Set(incoming.map(\.id))
                // Remove tabs that no longer exist
                self.tabOrder.removeAll { !incomingIds.contains($0) }
                // Append any new tabs at the end
                for tab in incoming where !self.tabOrder.contains(tab.id) {
                    self.tabOrder.append(tab.id)
                }
                // Build ordered list
                let lookup = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                self.tabs = self.tabOrder.compactMap { lookup[$0] }

                if let active = self.activeTabId, !incomingIds.contains(active) {
                    self.activeTabId = self.tabs.first?.id
                } else if self.activeTabId == nil, let first = self.tabs.first {
                    self.subscribe(to: first.id)
                }
            }
            .store(in: &cancellables)

        // Merge history, sorted newest-first
        mac.$historySessions.combineLatest(pi.$historySessions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] macH, piH in
                self?.historySessions = (macH + piH).sorted { $0.timestamp > $1.timestamp }
            }
            .store(in: &cancellables)

        // Mirror connected state
        mac.$connected.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.macConnected = $0 }.store(in: &cancellables)
        pi.$connected.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.piConnected  = $0 }.store(in: &cancellables)

        // Route PTY data to TerminalHostView callbacks
        mac.onData = { [weak self] tabId, chunk in self?.onData[tabId]?(chunk) }
        pi.onData  = { [weak self] tabId, chunk in self?.onData[tabId]?(chunk) }

        // Auto-subscribe when phone creates a new tab.
        // Use the connection directly — don't go through connection(for:) because
        // the tab won't be in .tabs yet when tab_created fires (sessions broadcast
        // arrives after).
        mac.onTabCreated = { [weak self] (tabId: String) in
            print("[SessionManager] mac onTabCreated: \(tabId)")
            self?.activeTabId = tabId
            self?.mac.subscribe(to: tabId)
        }
        pi.onTabCreated = { [weak self] (tabId: String) in
            print("[SessionManager] pi onTabCreated: \(tabId)")
            self?.activeTabId = tabId
            self?.pi.subscribe(to: tabId)
        }

        mac.connect()
        pi.connect()
    }

    // MARK: - Routing

    func connection(for tabId: String) -> HostConnection? {
        if mac.tabs.contains(where: { $0.id == tabId }) { return mac }
        if pi.tabs.contains(where:  { $0.id == tabId }) { return pi  }
        return nil
    }

    func connection(forHost hostId: String) -> HostConnection {
        hostId == "pi" ? pi : mac
    }

    // MARK: - Actions

    func subscribe(to tabId: String) {
        activeTabId = tabId
        connection(for: tabId)?.subscribe(to: tabId)
    }

    func sendInput(_ text: String) {
        guard let tabId = activeTabId else { return }
        connection(for: tabId)?.sendInput(text, tabId: tabId)
    }

    func stopActive() {
        guard let tabId = activeTabId else { return }
        connection(for: tabId)?.stopActive(tabId: tabId)
    }

    func switchTab(delta: Int) {
        guard !tabs.isEmpty,
              let activeId = activeTabId,
              let idx = tabs.firstIndex(where: { $0.id == activeId }) else { return }
        subscribe(to: tabs[(idx + delta + tabs.count) % tabs.count].id)
    }

    func resize(tabId: String, cols: Int, rows: Int) {
        connection(for: tabId)?.resize(tabId: tabId, cols: cols, rows: rows)
    }

    func sendVoice(audioData: Data, durationS: Double) {
        guard let tabId = activeTabId else { return }
        print("[SessionManager] sending voice \(String(format: "%.1f", durationS))s → tab \(tabId)")
        connection(for: tabId)?.sendVoice(audioData: audioData, durationS: durationS, tabId: tabId)
    }

    func newTab(on hostId: String = "mac") {
        let conn = connection(forHost: hostId)
        print("[SessionManager] newTab on \(hostId), conn.hostId=\(conn.hostId), conn.connected=\(conn.connected)")
        conn.newTab()
    }

    func resumeTab(sessionId: String, host: String) {
        connection(forHost: host).resumeTab(sessionId: sessionId)
    }

    func requestHistory() {
        mac.requestHistory()
        pi.requestHistory()
    }
}
