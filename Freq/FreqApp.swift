import SwiftUI

@main
struct FreqApp: App {
    @StateObject private var authService = SpotifyAuthService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .onOpenURL { url in
                    Task {
                        await authService.handleCallback(url: url)
                    }
                }
        }
    }
}
