import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authService: SpotifyAuthService
    @State private var track: NowPlayingTrack?
    @State private var isPlaying = false
    @State private var pollTimer: Timer?

    var body: some View {
        ZStack {
            Color(hex: "0A0A0A")
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Text("freq")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Disconnect") {
                        stopPolling()
                        authService.disconnect()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(hex: "4D9BFF"))
                }
                .padding(.horizontal)

                Spacer()

                if let track = track {
                    AsyncImage(url: URL(string: track.albumArtURL)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 280, height: 280)
                                .cornerRadius(12)
                                .shadow(color: Color(hex: "4D9BFF").opacity(0.3), radius: 20)
                        case .failure:
                            albumPlaceholder
                        default:
                            ProgressView()
                                .tint(.white)
                                .frame(width: 280, height: 280)
                        }
                    }

                    VStack(spacing: 8) {
                        Text(track.name)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Text(track.artist)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                } else {
                    albumPlaceholder

                    Text("Not playing")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.gray)
                }

                Spacer()
            }
            .padding(.top, 8)
        }
        .onAppear { startPolling() }
        .onDisappear { stopPolling() }
    }

    private var albumPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.05))
            .frame(width: 280, height: 280)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundColor(.gray)
            )
    }

    // MARK: - Polling

    private func startPolling() {
        fetchNowPlaying()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            fetchNowPlaying()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func fetchNowPlaying() {
        Task {
            guard let token = await authService.getValidAccessToken() else { return }
            guard let url = URL(string: SpotifyConfig.currentlyPlayingURL) else { return }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else { return }

                if httpResponse.statusCode == 204 || data.isEmpty {
                    track = nil
                    isPlaying = false
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    #if DEBUG
                    print("[Spotify] Currently playing request failed: \(httpResponse.statusCode)")
                    #endif
                    return
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard let item = json?["item"] as? [String: Any],
                      let trackName = item["name"] as? String,
                      let artists = item["artists"] as? [[String: Any]],
                      let artistName = artists.first?["name"] as? String else {
                    track = nil
                    return
                }

                var artURL = ""
                if let album = item["album"] as? [String: Any],
                   let images = album["images"] as? [[String: Any]],
                   let firstImage = images.first,
                   let imageURL = firstImage["url"] as? String {
                    artURL = imageURL
                }

                track = NowPlayingTrack(name: trackName, artist: artistName, albumArtURL: artURL)
                isPlaying = json?["is_playing"] as? Bool ?? false
            } catch {
                #if DEBUG
                print("[Spotify] Error fetching now playing: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

struct NowPlayingTrack {
    let name: String
    let artist: String
    let albumArtURL: String
}
