import SwiftUI

private struct ModelOption {
    let label: String
    let id: String
}

private struct ThinkingOption {
    let label: String
    let cmd: String
}

private let models: [ModelOption] = [
    ModelOption(label: "Opus 4.6",   id: "claude-opus-4-6"),
    ModelOption(label: "Sonnet 4.6", id: "claude-sonnet-4-6"),
    ModelOption(label: "Haiku 4.5",  id: "claude-haiku-4-5-20251001"),
]

private let thinkingLevels: [ThinkingOption] = [
    ThinkingOption(label: "Think",      cmd: "think "),
    ThinkingOption(label: "Think Hard", cmd: "think hard "),
    ThinkingOption(label: "Ultrathink", cmd: "ultrathink "),
]

struct ClaudeSettingsPanel: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                Section("Usage") {
                    Button {
                        sessionManager.sendInput("/usage\r")
                        isPresented = false
                    } label: {
                        Label("Check Usage", systemImage: "chart.bar.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Model") {
                    ForEach(models, id: \.id) { model in
                        Button {
                            sessionManager.sendInput("/model \(model.id)\r")
                            isPresented = false
                        } label: {
                            Text(model.label)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                Section("Thinking") {
                    ForEach(thinkingLevels, id: \.cmd) { level in
                        Button {
                            sessionManager.sendInput(level.cmd)
                            isPresented = false
                        } label: {
                            Text(level.label)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}
