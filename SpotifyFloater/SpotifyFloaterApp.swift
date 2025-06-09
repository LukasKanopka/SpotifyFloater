// FILE: SpotifyFloaterApp.swift
// DESCRIPTION: Replace the contents of your main app file (e.g., SpotifyFloaterApp.swift) with this.
//
import SwiftUI
import AuthenticationServices

@main
struct SpotifyFloaterApp: App {
    @StateObject private var authManager = SpotifyAuthManager()

   var body: some Scene {
       WindowGroup {
           ContentView()
               .environmentObject(authManager)
               .onOpenURL { url in
                   authManager.handleRedirect(url: url)
               }
               .background(WindowAccessor { window in
                   // --- START OF CHANGES ---
                   if let window = window {
                       window.level = .floating
                       window.styleMask = .borderless
                       window.titleVisibility = .hidden
                       window.titlebarAppearsTransparent = true
                       window.isMovableByWindowBackground = true

                       // Make the window background fully transparent
                       window.isOpaque = false
                       window.backgroundColor = .clear
                       
                       window.hasShadow = true

//                       // Hide the standard window buttons (close, minimize, zoom)
//                       window.standardWindowButton(.closeButton)?.isHidden = true
//                       window.standardWindowButton(.miniaturizeButton)?.isHidden = true
//                       window.standardWindowButton(.zoomButton)?.isHidden = true
                   }
                   // --- END OF CHANGES ---
               })
       }
       .windowStyle(.hiddenTitleBar)
       .commands {
           CommandGroup(before: .help) { // Place custom commands before the Help menu
               Button("Close Window") {
                   NSApplication.shared.keyWindow?.close()
               }
               .keyboardShortcut("w", modifiers: .command)

               Button("Quit SpotifyFloater") {
                   NSApplication.shared.terminate(nil)
               }
               .keyboardShortcut("q", modifiers: .command)
           }
       }
   }
}

class SpotifyAuthManager: NSObject, ObservableObject {
    private let clientID = "396d1e665262492eb3159f12423ae8a1" // IMPORTANT: Replace
    private let clientSecret = "eab8b520f38a4fc8aaeb8be94e1e2909" // IMPORTANT: Replace
    private let redirectURI = "spotifycontroller://callback"

    @Published var isAuthenticated = false
    @Published var accessToken: String?
    
    private var refreshToken: String?
    private var webAuthSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        loadAndRefreshToken()
    }

    // MARK: - Initialization and Token Loading

    private func loadAndRefreshToken() {
        self.refreshToken = UserDefaults.standard.string(forKey: "spotify_refresh_token")
        if self.refreshToken != nil {
            print("Found refresh token in UserDefaults: \(self.refreshToken!). Attempting to refresh.")
            refreshAccessToken()
        } else {
            print("No refresh token found in UserDefaults.")
        }
    }

    // MARK: - Authentication Flow

    func startAuthentication() {
        let scopes = "user-read-playback-state user-modify-playback-state user-library-modify user-library-read" // Added user-library-read scope
        let authURLString = "https://accounts.spotify.com/authorize?client_id=\(clientID)&response_type=code&redirect_uri=\(redirectURI)&scope=\(scopes)"
        
        guard let authURL = URL(string: authURLString) else {
            print("Error: Invalid authorization URL")
            return
        }
        
        self.webAuthSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "spotifycontroller") { [weak self] callbackURL, error in
            guard let callbackURL = callbackURL, error == nil else {
                print("Authentication session failed with error: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            self?.handleRedirect(url: callbackURL)
        }
        
        webAuthSession?.presentationContextProvider = self
        webAuthSession?.start()
    }
    
    func handleRedirect(url: URL) {
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            print("Invalid callback URL. Could not find authorization code.")
            return
        }
        exchangeCodeForTokens(code: code)
    }

    private func exchangeCodeForTokens(code: String) {
        let authHeader = "\(clientID):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        
        request.httpMethod = "POST"
        request.setValue("Basic \(authHeader)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                print("Error exchanging token: \(error?.localizedDescription ?? "Unknown")")
                return
            }
            
            do {
                let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                DispatchQueue.main.async {
                    self?.accessToken = tokenResponse.access_token
                    self?.refreshToken = tokenResponse.refresh_token
                    self?.isAuthenticated = true

                    // Save refresh token to UserDefaults
                    if let refreshToken = tokenResponse.refresh_token {
                        UserDefaults.standard.set(refreshToken, forKey: "spotify_refresh_token")
                        print("Saved refresh token to UserDefaults.")
                    } else {
                        print("No refresh token received to save.")
                    }
                }
            } catch {
                print("Failed to decode token response: \(error)")
            }
        }.resume()
    }
    
    func logOut() {
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "spotify_refresh_token")
    }

    func refreshAccessToken() {
        guard let refreshToken = self.refreshToken else {
            print("refreshAccessToken: No refresh token available.")
            return
        }
        print("refreshAccessToken: Using refresh token \(refreshToken)")

        let authHeader = "\(clientID):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)

        request.httpMethod = "POST"
        request.setValue("Basic \(authHeader)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                print("refreshAccessToken: Error refreshing token: \(error?.localizedDescription ?? "Unknown")")
                // Optionally clear the invalid refresh token
                UserDefaults.standard.removeObject(forKey: "spotify_refresh_token")
                self?.refreshToken = nil
                DispatchQueue.main.async {
                     self?.isAuthenticated = false
                     print("refreshAccessToken: Error refreshing token. isAuthenticated is now false.")
                }
                return
            }

            do {
                let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
                DispatchQueue.main.async {
                    self?.accessToken = tokenResponse.access_token
                    // Spotify might return a new refresh token, update if available
                    self?.refreshToken = tokenResponse.refresh_token ?? self?.refreshToken
                    if let newRefreshToken = tokenResponse.refresh_token {
                         UserDefaults.standard.set(newRefreshToken, forKey: "spotify_refresh_token")
                         print("refreshAccessToken: Updated and saved new refresh token.")
                    } else {
                        print("refreshAccessToken: No new refresh token received.")
                    }
                    self?.isAuthenticated = true
                    print("refreshAccessToken: Successfully refreshed token. isAuthenticated is now true.")
                }
            } catch {
                print("refreshAccessToken: Failed to decode refresh token response: \(error)")
                 // Optionally clear the invalid refresh token
                UserDefaults.standard.removeObject(forKey: "spotify_refresh_token")
                self?.refreshToken = nil
                 DispatchQueue.main.async {
                    self?.isAuthenticated = false
                    print("refreshAccessToken: Failed to refresh token. isAuthenticated is now false.")
                }
            }
        }.resume()
    }

    // MARK: - API Calls
    
    private func makeAPIRequest<T: Decodable>(endpoint: String, method: String, completion: @escaping (Result<T, Error>) -> Void) {
        guard let token = accessToken else {
            completion(.failure(APIError.notAuthenticated))
            return
        }
        
        guard let url = URL(string: "https://api.spotify.com\(endpoint)") else {
            completion(.failure(APIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(APIError.badResponse(statusCode: 500)))
                return
            }

            if !(200...299).contains(httpResponse.statusCode) {
                completion(.failure(APIError.badResponse(statusCode: httpResponse.statusCode)))
                return
            }
            
            guard let data = data, !data.isEmpty else {
                completion(.failure(APIError.noData))
                return
            }
            
            do {
                let decodedObject = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decodedObject))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func makeAPICallWithoutDecoding(endpoint: String, method: String, completion: @escaping (Error?) -> Void) {
        guard let token = accessToken else {
            completion(APIError.notAuthenticated)
            return
        }
        guard let url = URL(string: "https://api.spotify.com\(endpoint)") else {
            completion(APIError.invalidURL)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("API Error for \(endpoint): \(error.localizedDescription)")
                completion(error)
                return
            }
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let apiError = APIError.badResponse(statusCode: httpResponse.statusCode)
                print("API Error for \(endpoint): Status Code \(httpResponse.statusCode)")
                completion(apiError)
            } else {
                print("Successfully performed action: \(endpoint)")
                completion(nil)
            }
        }.resume()
    }

    enum PlayerEndpoint: String {
        case play = "/v1/me/player/play"
        case pause = "/v1/me/player/pause"
        case next = "/v1/me/player/next"
        case previous = "/v1/me/player/previous"
    }

    // UPDATED: Now includes a completion handler to report success or failure.
    func performPlayerAction(endpoint: PlayerEndpoint, completion: @escaping (Error?) -> Void) {
        let method = (endpoint == .next || endpoint == .previous) ? "POST" : "PUT"
        makeAPICallWithoutDecoding(endpoint: endpoint.rawValue, method: method, completion: completion)
    }

    func getCurrentTrack(completion: @escaping (Result<SpotifyTrackResponse, Error>) -> Void) {
        makeAPIRequest(endpoint: "/v1/me/player/currently-playing", method: "GET", completion: completion)
    }
    
    func addToFavorites(trackId: String, completion: @escaping (Error?) -> Void) {
        makeAPICallWithoutDecoding(endpoint: "/v1/me/tracks?ids=\(trackId)", method: "PUT", completion: completion)
    }
    
    func removeFromFavorites(trackId: String, completion: @escaping (Error?) -> Void) {
        makeAPICallWithoutDecoding(endpoint: "/v1/me/tracks?ids=\(trackId)", method: "DELETE", completion: completion)
    }

    func checkIfTrackIsSaved(trackId: String, completion: @escaping (Result<[Bool], Error>) -> Void) {
        makeAPIRequest(endpoint: "/v1/me/tracks/contains?ids=\(trackId)", method: "GET", completion: completion)
    }
}

// MARK: - Helper Models
struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String?
    let scope: String
}

enum APIError: Error {
    case notAuthenticated
    case invalidURL
    case badResponse(statusCode: Int)
    case noData
}

// Helper to access the NSWindow
struct WindowAccessor: NSViewRepresentable {
   var callback: (NSWindow?) -> Void

   func makeNSView(context: Context) -> NSView {
       let view = NSView()
       DispatchQueue.main.async { [weak view] in
           self.callback(view?.window)
       }
       return view
   }

   func updateNSView(_ nsView: NSView, context: Context) {}
}

extension SpotifyAuthManager: ASWebAuthenticationPresentationContextProviding {
   func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
       return NSApplication.shared.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
   }
}
