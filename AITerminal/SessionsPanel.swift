import SwiftUI

struct SessionsPanel: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool
    @State private var selectedHost = "mac"

    private var hostOnline: Bool {
        selectedHost == "pi" ? sessionManager.piConnected : sessionManager.macConnected
    }

    private var filteredHistory: [HistorySession] {
        sessionManager.historySessions.filter { $0.host == selectedHost }
    }

    var body: some View {
        NavigationView {
            List {
                // Host picker
                Section {
                    Picker("Host", selection: $selectedHost) {
                        Text("⌘  Mac").tag("mac")
                        Text("π  Pi").tag("pi")
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                // New session
                Section {
                    Button {
                        sessionManager.newTab(on: selectedHost)
                        isPresented = false
                    } label: {
                        Label("New Session on \(selectedHost == "pi" ? "Pi" : "Mac")",
                              systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(hostOnline ? .blue : .secondary)
                    }
                    .disabled(!hostOnline)
                }

                // Recent sessions
                if !filteredHistory.isEmpty {
                    Section("Recent") {
                        ForEach(filteredHistory) { session in
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
                            .disabled(!hostOnline)
                            .opacity(hostOnline ? 1.0 : 0.5)
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
