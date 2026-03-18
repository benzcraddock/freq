import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: SpotifyAuthService

    var body: some View {
        Group {
            if authService.isAuthenticated {
                HomeView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authService.isAuthenticated)
    }
}
