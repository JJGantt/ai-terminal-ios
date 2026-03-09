import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var showKeypad = false

    var activeTab: TabInfo? {
        sessionManager.tabs.first { $0.id == sessionManager.activeTabId }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip

            if let tabId = sessionManager.activeTabId {
                TerminalHostView(tabId: tabId)
                    .id(tabId) // force new view on tab switch (replays scrollback)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                placeholderView
            }
        }
        .background(.black)
        .overlay(alignment: .bottomTrailing) {
            controlOverlay
        }
    }

    // MARK: — Tab strip

    var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                connectionDot

                ForEach(sessionManager.tabs) { tab in
                    TabChip(
                        tab: tab,
                        isActive: tab.id == sessionManager.activeTabId,
                        onTap: { sessionManager.subscribe(to: tab.id) }
                    )
                }

                if sessionManager.tabs.isEmpty && sessionManager.connected {
                    Text("No open sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.black.opacity(0.85))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    var connectionDot: some View {
        Circle()
            .fill(sessionManager.connected ? .green : .orange)
            .frame(width: 7, height: 7)
            .padding(.leading, 4)
    }

    // MARK: — Placeholder

    var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(sessionManager.connected ? "No open sessions on Mac" : "Connecting to Mac…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    // MARK: — Control overlay

    var controlOverlay: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if showKeypad {
                KeypadView(onKey: { sessionManager.sendInput($0) })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.trailing, 16)
            }

            HStack(spacing: 10) {
                // Stop button — only when Claude is working
                if activeTab?.working == true {
                    Button(action: sessionManager.stopActive) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.red)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // Keypad toggle
                Button {
                    withAnimation(.spring(duration: 0.25)) { showKeypad.toggle() }
                } label: {
                    Image(systemName: showKeypad ? "keyboard.chevron.compact.down" : "keyboard")
                        .font(.system(size: 18))
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .foregroundStyle(.primary)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .animation(.spring(duration: 0.2), value: activeTab?.working)
    }
}

// MARK: — Tab chip

struct TabChip: View {
    let tab: TabInfo
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if tab.working {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }
                Text(tab.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isActive ? Color.blue : Color(.systemGray6), in: Capsule())
            .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
