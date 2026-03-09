import SwiftUI

@main
struct AITerminalApp: App {
    @StateObject var sessionManager = SessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .preferredColorScheme(.dark)
        }
    }
}
