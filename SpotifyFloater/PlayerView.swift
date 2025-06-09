// FILE: PlayerView.swift
// DESCRIPTION: Replace the contents of PlayerView.swift with this code.

import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    
    // State for the currently playing track and its artwork
    @State private var currentTrack: Track?
    @State private var albumArt: NSImage?
    @State private var isPlaying: Bool = false
    @State private var isFavorite: Bool = false
    
    // A timer to periodically fetch the latest track info
    // Slow down the timer to reduce unnecessary background polling.
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
       HStack(spacing: 12) {
           if let track = currentTrack {
               // Album art
               Image(nsImage: albumArt ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!)
                   .resizable()
                   .aspectRatio(contentMode: .fit)
                   .frame(width: 72, height: 72)
                   .cornerRadius(8)
                   .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

               // Track info and controls
               VStack(alignment: .leading, spacing: 5) {
                   Text(track.name)
                       .font(.headline)
                       .fontWeight(.bold)
                       .foregroundColor(.primary)
                   Text(track.artistNames)
                       .font(.caption)
                       .foregroundColor(.secondary)
                   
                  HStack(spacing: 15) {
                      // Backward Button
                      PlayerButton(systemName: "backward.fill") {
                          authManager.performPlayerAction(endpoint: .previous) { error in
                              if error == nil { self.fetchAfterAction() }
                          }
                      }
                      
                      // Play/Pause Button
                      PlayerButton(systemName: isPlaying ? "pause.fill" : "play.fill", fontSize: .title2) {
                          let endpoint: SpotifyAuthManager.PlayerEndpoint = isPlaying ? .pause : .play
                          authManager.performPlayerAction(endpoint: endpoint) { error in
                              if error == nil { self.fetchAfterAction() }
                          }
                      }
                      
                      // Forward Button
                      PlayerButton(systemName: "forward.fill") {
                          authManager.performPlayerAction(endpoint: .next) { error in
                              if error == nil { self.fetchAfterAction() }
                          }
                      }
                  }
               }
               
               // Spacer()
               
                // --- FAVORITE BUTTON REVAMP (now a heart icon) ---
               PlayerButton(systemName: isFavorite ? "heart.fill" : "heart", fontSize: .title2) {
                   toggleFavoriteStatus()
               }
               .tint(isFavorite ? .pink : .secondary) // Pink when favorited
               .animation(.spring(), value: isFavorite)

           } else {
               Text("Nothing Playing")
                   .font(.title)
                   .foregroundColor(.secondary)
           }
       }
       .padding(.horizontal, 20)
       .padding(.vertical, 12)
       .frame(width: 300, height: 100) // Adjusted height
       // --- UI REVAMP: FROSTED GLASS EFFECT ---
       .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 50.0))
       // --- END OF UI REVAMP ---
       .shadow(color: .black.opacity(0.2), radius: 20, y: 5)
       .onAppear(perform: fetchCurrentTrack)
       .onReceive(timer) { _ in
           fetchCurrentTrack()
       }
   }
    
    // Fetches the track and then its artwork
    private func fetchCurrentTrack() {
        authManager.getCurrentTrack { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    if self.currentTrack?.id != response.item?.id {
                        self.currentTrack = response.item
                        if let imageURLString = response.item?.album.images.first?.url,
                           let imageURL = URL(string: imageURLString) {
                            self.fetchAlbumArt(from: imageURL)
                        } else {
                            self.albumArt = nil
                        }
                    }
                    self.isPlaying = response.is_playing
                    
                    if let trackId = response.item?.id {
                        self.checkFavoriteStatus(for: trackId)
                    }
                    
                case .failure(let error):
                    if let apiError = error as? APIError, case .badResponse(let statusCode) = apiError, statusCode == 403 {
                        print("Playback not active on any device (403).")
                    } else {
                        print("Error fetching track: \(error.localizedDescription)")
                        self.currentTrack = nil
                    }
                }
            }
        }
    }
    
    private func checkFavoriteStatus(for trackId: String) {
        authManager.checkIfTrackIsSaved(trackId: trackId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let isSavedArray):
                    self.isFavorite = isSavedArray.first ?? false
                case .failure(let error):
                    print("Could not check favorite status: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func toggleFavoriteStatus() {
        guard let trackId = currentTrack?.id else { return }
        
        if isFavorite {
            authManager.removeFromFavorites(trackId: trackId) { error in
                if error == nil {
                    DispatchQueue.main.async { self.isFavorite = false }
                }
            }
        } else {
            authManager.addToFavorites(trackId: trackId) { error in
                if error == nil {
                    DispatchQueue.main.async { self.isFavorite = true }
                }
            }
        }
    }
    
    // Fetches image data from a URL
    private func fetchAlbumArt(from url: URL) {
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    self.albumArt = image
                }
            } else {
                print("Error fetching album art: \(error?.localizedDescription ?? "Unknown error")")
            }
        }.resume()
    }
    // Instantly fetches track info after a short delay to ensure
    // Spotify's backend has processed the change.
    private func fetchAfterAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.fetchCurrentTrack()
        }
    }
}

// --- NEW HELPER VIEW FOR PRETTIER BUTTONS ---
struct PlayerButton: View {
    let systemName: String
    var fontSize: Font = .body
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(fontSize)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain) // Removes default button chrome for a cleaner look
    }
}

#Preview {
    PlayerView()
        .environmentObject(SpotifyAuthManager())
}