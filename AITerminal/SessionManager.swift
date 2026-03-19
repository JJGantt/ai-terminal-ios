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
    let parsedDate: Date

    init(id: String, title: String, timestamp: String, host: String) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.host = host
        // Parse various timestamp formats to a Date for sorting
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: timestamp) { self.parsedDate = d; return }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: timestamp) { self.parsedDate = d; return }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        df.timeZone = .current
        self.parsedDate = df.date(from: timestamp) ?? .distantPast
    }
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

    /// Last known terminal dimensions (from any resize), sent with new tab requests.
    private(set) var lastCols = 0
    private(set) var lastRows = 0

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

        // Merge history, deduplicate by session ID, sorted newest-first
        mac.$historySessions.combineLatest(pi.$historySessions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (macH: [HistorySession], piH: [HistorySession]) in
                var seen = Set<String>()
                var merged: [HistorySession] = []
                for session in (macH + piH).sorted(by: { $0.parsedDate > $1.parsedDate }) {
                    if seen.insert(session.id).inserted {
                        merged.append(session)
                    }
                }
                self?.historySessions = merged
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

    /// Send a slash command: clears the line, then types the command after a brief delay.
    func sendSlashCommand(_ command: String) {
        guard let tabId = activeTabId, let conn = connection(for: tabId) else { return }
        conn.sendInput("\u{15}", tabId: tabId)  // Ctrl+U: clear line
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            conn.sendInput(command + "\r", tabId: tabId)
        }
    }

    func stopActive() {
        guard let tabId = activeTabId else { return }
        connection(for: tabId)?.stopActive(tabId: tabId)
    }

    func closeTab(_ tabId: String) {
        connection(for: tabId)?.killTab(tabId)
        // Switch to adjacent tab
        if activeTabId == tabId, let idx = tabs.firstIndex(where: { $0.id == tabId }) {
            let remaining = tabs.filter { $0.id != tabId }
            activeTabId = remaining.isEmpty ? nil : remaining[min(idx, remaining.count - 1)].id
            if let newId = activeTabId { subscribe(to: newId) }
        }
    }

    func closeAllTabs() {
        for tab in tabs {
            connection(for: tab.id)?.killTab(tab.id)
        }
        activeTabId = nil
    }

    func switchTab(delta: Int) {
        guard !tabs.isEmpty,
              let activeId = activeTabId,
              let idx = tabs.firstIndex(where: { $0.id == activeId }) else { return }
        subscribe(to: tabs[(idx + delta + tabs.count) % tabs.count].id)
    }

    func resize(tabId: String, cols: Int, rows: Int) {
        lastCols = cols
        lastRows = rows
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
        conn.newTab(cols: lastCols, rows: lastRows)
    }

    func resumeTab(sessionId: String, host: String) {
        connection(forHost: host).resumeTab(sessionId: sessionId, cols: lastCols, rows: lastRows)
    }

    func requestHistory() {
        mac.requestHistory()
        pi.requestHistory()
    }

    func regenerateName(sessionId: String, host: String) {
        connection(forHost: host).regenerateName(sessionId: sessionId)
    }
}
