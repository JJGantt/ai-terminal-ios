import SwiftUI

struct SessionsPanel: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                // New session buttons
                Section("New Session") {
                    Button {
                        sessionManager.newTab(on: "mac")
                        isPresented = false
                    } label: {
                        Label("Mac  ⌘", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(sessionManager.macConnected ? .blue : .secondary)
                    }
                    .disabled(!sessionManager.macConnected)

                    Button {
                        sessionManager.newTab(on: "pi")
                        isPresented = false
                    } label: {
                        Label("Pi  π", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(sessionManager.piConnected ? .blue : .secondary)
                    }
                    .disabled(!sessionManager.piConnected)
                }

                // All recent sessions mixed together
                if !sessionManager.historySessions.isEmpty {
                    Section("Recent") {
                        ForEach(sessionManager.historySessions) { session in
                            let online = session.host == "pi"
                                ? sessionManager.piConnected
                                : sessionManager.macConnected
                            Button {
                                sessionManager.resumeTab(sessionId: session.id, host: session.host)
                                isPresented = false
                            } label: {
                                HStack(spacing: 10) {
                                    Text(session.host == "pi" ? "π" : "⌘")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(session.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text(formattedDate(session.timestamp))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .disabled(!online)
                            .opacity(online ? 1.0 : 0.5)
                        }
                    }
                } else {
                    Section {
                        Text("No recent sessions")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
        .onAppear { sessionManager.requestHistory() }
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}
