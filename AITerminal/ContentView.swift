import SwiftUI

extension UIApplication {
    func endEditing() {
        connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.endEditing(true)
    }
}

struct ContentView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @StateObject private var voice = VoiceRecorder()
    @State private var keyboardVisible = false
    @State private var showSessions = false
    @State private var pendingCloseTabId: String?

    var activeTab: TabInfo? {
        sessionManager.tabs.first { $0.id == sessionManager.activeTabId }
    }

    func isOnline(_ tab: TabInfo) -> Bool {
        tab.host == "pi" ? sessionManager.piConnected : sessionManager.macConnected
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip

            if let tabId = sessionManager.activeTabId {
                TerminalHostView(tabId: tabId, voiceRecorder: voice)
                    .id(tabId)
            } else {
                placeholderView
            }

            bottomBar
        }
        .background(.black)
        .sheet(isPresented: $showSessions) {
            SessionsPanel(isPresented: $showSessions)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onAppear {
            voice.requestPermission { granted in
                print("[Voice] microphone permission: \(granted)")
            }
            voice.onComplete = { data, duration in
                sessionManager.sendVoice(audioData: data, durationS: duration)
            }
        }
        .onChange(of: sessionManager.pendingAction) { _, action in
            guard let action else { return }
            sessionManager.pendingAction = nil
            switch action {
            case .newSession(let host, let record):
                sessionManager.newTab(on: host)
                if record {
                    // Delay to let the tab create and TerminalHostView mount
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        voice.start()
                    }
                }
            }
        }
    }

    // MARK: — Tab strip

    var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    connectionDots

                    ForEach(sessionManager.tabs) { tab in
                        TabChip(
                            tab: tab,
                            isActive: tab.id == sessionManager.activeTabId,
                            isOnline: isOnline(tab),
                            isPendingClose: pendingCloseTabId == tab.id,
                            onTap: {
                                guard isOnline(tab) else { return }
                                if pendingCloseTabId == tab.id {
                                    // Second tap on red tab → close
                                    pendingCloseTabId = nil
                                    sessionManager.closeTab(tab.id)
                                } else if tab.id == sessionManager.activeTabId {
                                    // Tap on already-active tab → arm close
                                    pendingCloseTabId = tab.id
                                } else {
                                    // Tap on inactive tab → switch to it
                                    pendingCloseTabId = nil
                                    sessionManager.subscribe(to: tab.id)
                                }
                            }
                        )
                        .id(tab.id)
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
            .onChange(of: sessionManager.activeTabId) { _, newId in
                if let id = newId {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .background(.black.opacity(0.85))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.3)
        }
    }

    // Two small dots — one for Mac, one for Pi
    var connectionDots: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(sessionManager.macConnected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Circle()
                .fill(sessionManager.piConnected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
        }
        .padding(.leading, 4)
    }

    // MARK: — Placeholder

    var placeholderView: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(sessionManager.connected ? "No open sessions" : "Connecting…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    // MARK: — Bottom bar

    var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: 0) {
                Button { showSessions = true } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }

                voiceButton
                    .frame(maxWidth: .infinity)

                keyboardButton
                    .frame(maxWidth: .infinity)

                Button {
                    sessionManager.newTab(on: "pi")
                } label: {
                    HStack(spacing: 2) {
                        Text("\u{03C0}")
                            .font(.system(size: 18, weight: .semibold))
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(sessionManager.piConnected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .disabled(!sessionManager.piConnected)
            }
            .background(.black.opacity(0.85))
            .overlay(alignment: .topLeading) {
                if voice.state == .recording {
                    Button(action: voice.cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.leading, 8)
                    .offset(y: -44)
                    .transition(.scale.combined(with: .opacity))
                } else if activeTab?.working == true {
                    Button(action: sessionManager.stopActive) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.red)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .padding(.leading, 8)
                    .offset(y: -44)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.2), value: voice.state == .recording)
            .animation(.spring(duration: 0.2), value: activeTab?.working)
        }
    }

    // MARK: — Voice button

    @ViewBuilder
    var voiceButton: some View {
        switch voice.state {
        case .idle:
            Button { voice.start() } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
            }

        case .recording:
            Button { voice.stop() } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
            }
            .symbolEffect(.pulse, isActive: true)

        case .transcribing:
            ProgressView()
                .frame(height: 52)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: — Keyboard button

    var keyboardButton: some View {
        Button {
            if keyboardVisible {
                UIApplication.shared.endEditing()
            } else {
                sessionManager.focusTerminal?()
            }
        } label: {
            Image(systemName: keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                .font(.system(size: 20))
                .foregroundStyle(.primary)
                .frame(height: 52)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: — Tab chip

struct TabChip: View {
    let tab: TabInfo
    let isActive: Bool
    let isOnline: Bool
    let isPendingClose: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if tab.working && isOnline && !isPendingClose {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                }
                Text(tab.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if tab.host == "pi" {
                    Text("π")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.6)
                } else {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 9, weight: .medium))
                        .opacity(0.6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(chipBackground, in: Capsule())
            .foregroundStyle(chipForeground)
            .opacity(isOnline ? 1.0 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isOnline)
    }

    private var chipBackground: Color {
        if isPendingClose { return .red }
        return isActive && isOnline ? .blue : Color(.systemGray6)
    }

    private var chipForeground: Color {
        if isPendingClose { return .white }
        return isActive && isOnline ? .white : .primary
    }
}
