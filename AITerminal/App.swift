import SwiftUI

@main
struct AITerminalApp: App {
    @StateObject var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    handleURL(url)
                }
        }
    }

    private func handleURL(_ url: URL) {
        // aiterminal://new?host=pi&record=true
        guard url.scheme == "aiterminal" else { return }
        let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "host" })?.value ?? "pi"
        let record = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "record" })?.value == "true"

        switch url.host {
        case "new":
            sessionManager.pendingAction = .newSession(host: host, record: record)
        default:
            break
        }
    }
}
