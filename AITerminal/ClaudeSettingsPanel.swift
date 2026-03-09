import SwiftUI

private struct ModelOption {
    let label: String
    let alias: String
}

private let models: [ModelOption] = [
    ModelOption(label: "Opus 4.6",   alias: "opus"),
    ModelOption(label: "Sonnet 4.6", alias: "sonnet"),
    ModelOption(label: "Haiku 4.5",  alias: "haiku"),
]

struct ClaudeSettingsPanel: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                Section("Usage") {
                    Button {
                        sessionManager.sendInput("\u{15}/usage\r")
                        isPresented = false
                    } label: {
                        Label("Check Usage", systemImage: "chart.bar.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Model") {
                    ForEach(models, id: \.alias) { model in
                        Button {
                            sessionManager.sendInput("\u{15}/model \(model.alias)\r")
                            isPresented = false
                        } label: {
                            Text(model.label)
                                .foregroundStyle(.primary)
                        }
                    }
                    Button {
                        sessionManager.sendInput("\u{15}/model\r")
                        isPresented = false
                    } label: {
                        Label("Browse All Models…", systemImage: "chevron.right")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
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
