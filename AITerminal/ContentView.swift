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

    var activeTab: TabInfo? {
        sessionManager.tabs.first { $0.id == sessionManager.activeTabId }
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
    }

    // MARK: — Tab strip

    var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    connectionDot

                    ForEach(sessionManager.tabs) { tab in
                        TabChip(
                            tab: tab,
                            isActive: tab.id == sessionManager.activeTabId,
                            onTap: { sessionManager.subscribe(to: tab.id) }
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

    // MARK: — Bottom bar

    var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: 0) {
                // Sessions button
                Button {
                    showSessions = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }

                // Voice / transcribing button (center)
                voiceButton
                    .frame(maxWidth: .infinity)

                // Keyboard / dismiss button
                keyboardButton
                    .frame(maxWidth: .infinity)
            }
            .background(.black.opacity(0.85))
            .overlay(alignment: .topLeading) {
                // Stop button floats above the bar when Claude is working
                if activeTab?.working == true {
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
            .animation(.spring(duration: 0.2), value: activeTab?.working)
        }
    }

    // MARK: — Voice button

    @ViewBuilder
    var voiceButton: some View {
        switch voice.state {
        case .idle:
            Button {
                voice.start()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.primary)
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
            }

        case .recording:
            Button {
                voice.stop()
            } label: {
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

    // MARK: — Keyboard / dismiss button

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
