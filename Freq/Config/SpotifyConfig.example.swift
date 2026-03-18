// Copy this file as SpotifyConfig.swift and replace with your real credentials
import Foundation

enum SpotifyConfig {
    static let clientID = "YOUR_SPOTIFY_CLIENT_ID_HERE"
    static let redirectURI = "freq://callback"
    static let scopes = "user-read-currently-playing user-read-playback-state"

    static let authorizeURL = "https://accounts.spotify.com/authorize"
    static let tokenURL = "https://accounts.spotify.com/api/token"
    static let currentlyPlayingURL = "https://api.spotify.com/v1/me/player/currently-playing"
}
