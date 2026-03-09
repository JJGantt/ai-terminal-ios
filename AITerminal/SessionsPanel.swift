import SwiftUI

struct SessionsPanel: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                Section {
                    Button {
                        sessionManager.newTab()
                        isPresented = false
                    } label: {
                        Label("New Session", systemImage: "plus.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                }

                if !sessionManager.historySessions.isEmpty {
                    Section("Recent Sessions") {
                        ForEach(sessionManager.historySessions) { session in
                            Button {
                                sessionManager.resumeTab(sessionId: session.id)
                                isPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(formattedDate(session.timestamp))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 2)
                            }
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
        // fallback: try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return iso
    }
}
