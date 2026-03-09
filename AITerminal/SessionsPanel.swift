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
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo")
                                .frame(width: 18)
                            Image(systemName: "plus.circle.fill")
                            Spacer()
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(sessionManager.macConnected ? .blue : .secondary)
                    }
                    .disabled(!sessionManager.macConnected)

                    Button {
                        sessionManager.newTab(on: "pi")
                        isPresented = false
                    } label: {
                        HStack(spacing: 10) {
                            Text("π")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 18)
                            Image(systemName: "plus.circle.fill")
                            Spacer()
                        }
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
                                    hostIcon(session.host)
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

    @ViewBuilder
    private func hostIcon(_ host: String) -> some View {
        if host == "pi" {
            Text("π")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "apple.logo")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        // Try with fractional seconds + timezone (Mac format)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        // Try with timezone, no fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        // Try without timezone (Pi format: 2026-03-09T13:44:40)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        df.timeZone = .current
        if let date = df.date(from: iso) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}
