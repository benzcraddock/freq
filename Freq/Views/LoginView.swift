import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @EnvironmentObject var authService: SpotifyAuthService

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Text("freq")
                        .font(.system(size: 56, weight: .bold, design: .default))
                        .foregroundColor(.white)

                    Text("see the music around you")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.gray)
                }

                Spacer()

                Button(action: startSpotifyAuth) {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                        Text("Connect Spotify")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(hex: "4D9BFF"))
                    .cornerRadius(27)
                }
                .padding(.horizontal, 40)

                if authService.isLoading {
                    ProgressView()
                        .tint(.white)
                }

                Spacer()
                    .frame(height: 60)
            }
        }
    }

    private func startSpotifyAuth() {
        guard let authURL = authService.startAuth() else { return }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "freq"
        ) { callbackURL, error in
            if let error = error {
                print("[SpotifyAuth] ASWebAuthenticationSession error: \(error.localizedDescription)")
                return
            }

            guard let callbackURL = callbackURL else { return }

            Task { @MainActor in
                await authService.handleCallback(url: callbackURL)
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = PresentationContextProvider.shared
        session.start()
    }
}

// Provides a presentation anchor for ASWebAuthenticationSession
final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
