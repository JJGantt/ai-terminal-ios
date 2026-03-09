import SwiftUI

@main
struct AITerminalApp: App {
    @StateObject var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .onAppear { sessionManager.connect() }
                .preferredColorScheme(.dark)
        }
    }
}
