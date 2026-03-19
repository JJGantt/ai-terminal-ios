import SwiftUI

private struct ModelOption {
    let label: String
    let alias: String
}

private let modelOptions: [ModelOption] = [
    ModelOption(label: "Opus 4.6",   alias: "opus"),
    ModelOption(label: "Sonnet 4.6", alias: "sonnet"),
    ModelOption(label: "Haiku 4.5",  alias: "haiku"),
]

struct SessionsPanel: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool
    @State private var confirmCloseAll = false

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
                            Text("\u{03C0}")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 18)
                            Image(systemName: "plus.circle.fill")
                            Spacer()
                        }
                        .foregroundStyle(sessionManager.piConnected ? .blue : .secondary)
                    }
                    .disabled(!sessionManager.piConnected)
                }

                // Close all tabs
                if !sessionManager.tabs.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            confirmCloseAll = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "xmark.circle.fill")
                                    .frame(width: 18)
                                Text("Close All Tabs")
                                Spacer()
                                Text("\(sessionManager.tabs.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 16, weight: .medium))
                        }
                        .confirmationDialog(
                            "Close all \(sessionManager.tabs.count) tabs?",
                            isPresented: $confirmCloseAll,
                            titleVisibility: .visible
                        ) {
                            Button("Close All", role: .destructive) {
                                sessionManager.closeAllTabs()
                                isPresented = false
                            }
                        }
                    }
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
                            .contextMenu {
                                Button {
                                    sessionManager.regenerateName(sessionId: session.id, host: session.host)
                                } label: {
                                    Label("Regenerate Name", systemImage: "arrow.triangle.2.circlepath")
                                }
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

                // Settings
                Section("Settings") {
                    Button {
                        sessionManager.sendSlashCommand("/usage")
                        isPresented = false
                    } label: {
                        Label("Check Usage", systemImage: "chart.bar.fill")
                            .foregroundStyle(.primary)
                    }

                    ForEach(modelOptions, id: \.alias) { model in
                        Button {
                            sessionManager.sendSlashCommand("/model \(model.alias)")
                            isPresented = false
                        } label: {
                            Text(model.label)
                                .foregroundStyle(.primary)
                        }
                    }
                    Button {
                        sessionManager.sendSlashCommand("/model")
                        isPresented = false
                    } label: {
                        Label("Browse All Models…", systemImage: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                }
            }
            .navigationTitle("Menu")
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
