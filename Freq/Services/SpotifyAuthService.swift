import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class SpotifyAuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false

    private var codeVerifier: String?
    private var tokenExpirationDate: Date?

    private enum KeychainKeys {
        static let accessToken = "spotify_access_token"
        static let refreshToken = "spotify_refresh_token"
        static let tokenExpiration = "spotify_token_expiration"
    }

    init() {
        isAuthenticated = KeychainHelper.loadString(key: KeychainKeys.accessToken) != nil
        if let expirationString = KeychainHelper.loadString(key: KeychainKeys.tokenExpiration),
           let interval = TimeInterval(expirationString) {
            tokenExpirationDate = Date(timeIntervalSince1970: interval)
        }
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .prefix(64)
            .description
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Auth Flow

    func startAuth() -> URL? {
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: SpotifyConfig.authorizeURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyConfig.redirectURI),
            URLQueryItem(name: "scope", value: SpotifyConfig.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        return components?.url
    }

    func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            #if DEBUG
            print("[SpotifyAuth] No authorization code in callback URL")
            #endif
            return
        }

        // Validate the code contains only expected characters
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard code.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            #if DEBUG
            print("[SpotifyAuth] Invalid characters in authorization code")
            #endif
            return
        }

        await exchangeCodeForTokens(code: code)
    }

    private func exchangeCodeForTokens(code: String) async {
        guard let verifier = codeVerifier else {
            #if DEBUG
            print("[SpotifyAuth] Missing code verifier")
            #endif
            return
        }

        isLoading = true
        defer { isLoading = false }

        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": SpotifyConfig.redirectURI,
            "client_id": SpotifyConfig.clientID,
            "code_verifier": verifier
        ]

        guard let tokenResponse = await performTokenRequest(body: body) else { return }
        storeTokens(tokenResponse)
        codeVerifier = nil
    }

    func refreshAccessToken() async -> Bool {
        guard let refreshToken = KeychainHelper.loadString(key: KeychainKeys.refreshToken) else {
            #if DEBUG
            print("[SpotifyAuth] No refresh token available")
            #endif
            return false
        }

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": SpotifyConfig.clientID
        ]

        guard let tokenResponse = await performTokenRequest(body: body) else { return false }
        storeTokens(tokenResponse)
        return true
    }

    private func performTokenRequest(body: [String: String]) async -> SpotifyTokenResponse? {
        guard let url = URL(string: SpotifyConfig.tokenURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                #if DEBUG
                print("[SpotifyAuth] Token request failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                #endif
                return nil
            }

            return try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        } catch {
            #if DEBUG
            print("[SpotifyAuth] Token request error: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func storeTokens(_ response: SpotifyTokenResponse) {
        KeychainHelper.saveString(key: KeychainKeys.accessToken, value: response.accessToken)

        if let refreshToken = response.refreshToken {
            KeychainHelper.saveString(key: KeychainKeys.refreshToken, value: refreshToken)
        }

        let expiration = Date().addingTimeInterval(TimeInterval(response.expiresIn - 60))
        tokenExpirationDate = expiration
        KeychainHelper.saveString(key: KeychainKeys.tokenExpiration, value: String(expiration.timeIntervalSince1970))

        isAuthenticated = true
    }

    // MARK: - Token Access

    func getValidAccessToken() async -> String? {
        if let expiration = tokenExpirationDate, Date() >= expiration {
            let refreshed = await refreshAccessToken()
            if !refreshed {
                disconnect()
                return nil
            }
        }
        return KeychainHelper.loadString(key: KeychainKeys.accessToken)
    }

    func disconnect() {
        KeychainHelper.delete(key: KeychainKeys.accessToken)
        KeychainHelper.delete(key: KeychainKeys.refreshToken)
        KeychainHelper.delete(key: KeychainKeys.tokenExpiration)
        tokenExpirationDate = nil
        isAuthenticated = false
    }
}
