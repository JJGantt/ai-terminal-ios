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

    var activeTab: TabInfo? {
        sessionManager.tabs.first { $0.id == sessionManager.activeTabId }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip

            if let tabId = sessionManager.activeTabId {
                TerminalHostView(tabId: tabId, voiceRecorder: voice)
                    .id(tabId)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                placeholderView
            }
        }
        .background(.black)
        .overlay(alignment: .bottomTrailing) {
            controlOverlay
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

                // Voice button
                voiceButton

                // Keyboard / dismiss button
                keyboardButton
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .animation(.spring(duration: 0.2), value: activeTab?.working)
        .animation(.spring(duration: 0.2), value: keyboardVisible)
        .animation(.spring(duration: 0.2), value: voice.state == .idle)
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
                    .font(.system(size: 18))
                    .foregroundStyle(.primary)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }

        case .recording:
            Button {
                voice.stop()
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.red)
                    .frame(width: 48, height: 48)
                    .background(Color.red.opacity(0.2), in: Circle())
            }
            .symbolEffect(.pulse, isActive: true)

        case .transcribing:
            ProgressView()
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
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
                .font(.system(size: 18))
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .foregroundStyle(.primary)
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
