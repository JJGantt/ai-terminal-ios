import SwiftUI

private struct ThinkingOption {
    let label: String
    let prefix: String  // prepended to next voice recording
}

private let thinkingLevels: [ThinkingOption] = [
    ThinkingOption(label: "Think",      prefix: "think: "),
    ThinkingOption(label: "Think Hard", prefix: "think hard: "),
    ThinkingOption(label: "Ultrathink", prefix: "ultrathink: "),
]

struct ClaudeSettingsPanel: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool
    let voice: VoiceRecorder

    var body: some View {
        NavigationView {
            List {
                Section("Usage") {
                    Button {
                        sessionManager.sendInput("\u{1b}/usage\r")
                        isPresented = false
                    } label: {
                        Label("Check Usage", systemImage: "chart.bar.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Model") {
                    Button {
                        sessionManager.sendInput("\u{1b}/model\r")
                        isPresented = false
                    } label: {
                        Label("Choose Model…", systemImage: "cpu")
                            .foregroundStyle(.primary)
                    }
                }

                Section {
                    ForEach(thinkingLevels, id: \.prefix) { level in
                        Button {
                            voice.thinkingPrefix = level.prefix
                            isPresented = false
                        } label: {
                            HStack {
                                Text(level.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if voice.thinkingPrefix == level.prefix {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                        }
                    }
                    if voice.thinkingPrefix != nil {
                        Button(role: .destructive) {
                            voice.thinkingPrefix = nil
                            isPresented = false
                        } label: {
                            Text("Clear Thinking Mode")
                        }
                    }
                } header: {
                    Text("Thinking (next voice)")
                } footer: {
                    Text("Prepends the selected keyword to your next voice recording.")
                        .font(.caption)
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
