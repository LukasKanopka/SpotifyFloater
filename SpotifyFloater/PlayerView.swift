// FILE: PlayerView.swift
// DESCRIPTION: Create a new SwiftUI View file named "PlayerView.swift" and add this code.
//
import SwiftUI

struct PlayerView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    
    // State for the currently playing track and its artwork
    @State private var currentTrack: Track?
    @State private var albumArt: NSImage?
    @State private var isPlaying: Bool = false
    @State private var isFavorite: Bool = false // NEW: State to track favorite status
    
    // A timer to periodically fetch the latest track info
    let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
       HStack(spacing: 15) { // Changed back to HStack for horizontal arrangement
           if let track = currentTrack {
               // Display the album art on the left, downscaled
               Image(nsImage: albumArt ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!)
                   .resizable()
                   .aspectRatio(contentMode: .fit)
                   .frame(width: 60, height: 60) // Downscaled artwork
                   .cornerRadius(4) // Smaller corner radius
                   .shadow(radius: 3) // Smaller shadow
               
               VStack(alignment: .leading, spacing: 5) { // Stack for text and controls
                   VStack(alignment: .leading) { // Stack for song title and artist
                       Text(track.name)
                           .font(.headline) // Song name
                           .fontWeight(.bold)
                           .lineLimit(1)
                           .foregroundColor(.white) // Spotify theme text color
                       Text(track.artistNames)
                           .font(.caption) // Artist name
                           .foregroundColor(.gray) // Spotify theme secondary text color
                           .lineLimit(1)
                   }
                   
                   HStack(spacing: 20) { // Player control buttons
                       Button(action: { authManager.performPlayerAction(endpoint: .previous) }) {
                           Image(systemName: "backward.fill")
                               .foregroundColor(.white) // Spotify theme button color
                       }
                       
                       Button(action: { isPlaying ? authManager.performPlayerAction(endpoint: .pause) : authManager.performPlayerAction(endpoint: .play) }) {
                           Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                               .font(.title2) // Adjusted font size
                               .foregroundColor(Color(red: 0.11, green: 0.82, blue: 0.33)) // Spotify Green
                       }
                       
                       Button(action: { authManager.performPlayerAction(endpoint: .next) }) {
                           Image(systemName: "forward.fill")
                               .foregroundColor(.white) // Spotify theme button color
                       }
                   }
               }
               
               Spacer() // Pushes content to the left, favorite button to the right
               
               // Favorite button
               Button(action: toggleFavoriteStatus) {
                   Image(systemName: isFavorite ? "minus.circle.fill" : "plus.circle.fill") // Circular +/- icon
                       .foregroundColor(isFavorite ? Color(red: 0.11, green: 0.82, blue: 0.33) : .gray) // Spotify Green for favorited (minus), gray otherwise (plus)
               }
               .font(.title2)

           } else {
               Text("Nothing Playing")
                   .font(.title)
                   .foregroundColor(.secondary)
           }
       }
       .padding(.horizontal, 20) // Add horizontal padding
       .padding(.vertical, 10) // Adjusted vertical padding for a slightly shorter pill
       .frame(width: 350, height: 100) // Adjusted frame size for a long pill
       .background(Color(red: 0.1, green: 0.1, blue: 0.1)) // Dark background color
       .cornerRadius(50) // Apply corner radius for pill shape
       .shadow(radius: 10) // Add a subtle shadow
       .onAppear(perform: fetchCurrentTrack) // Fetch track when view appears
       .onReceive(timer) { _ in // And fetch track on a timer
           fetchCurrentTrack()
       }
   }
    
    // Fetches the track and then its artwork
    private func fetchCurrentTrack() {
        authManager.getCurrentTrack { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    // Only update UI if the track is new
                    if self.currentTrack?.id != response.item?.id {
                        self.currentTrack = response.item
                        if let imageURLString = response.item?.album.images.first?.url,
                           let imageURL = URL(string: imageURLString) {
                            self.fetchAlbumArt(from: imageURL)
                        } else {
                            self.albumArt = nil // No artwork URL
                        }
                    }
                    self.isPlaying = response.is_playing
                    
                    // Always check favorite status in case it changed
                    if let trackId = response.item?.id {
                        self.checkFavoriteStatus(for: trackId)
                    }
                    
                case .failure(let error):
                    // Don't clear the view for temporary errors like no active device
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
            // Currently a favorite, so remove it
            authManager.removeFromFavorites(trackId: trackId) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        self.isFavorite = false // Optimistically update UI
                    }
                }
            }
        } else {
            // Not a favorite, so add it
            authManager.addToFavorites(trackId: trackId) { error in
                if error == nil {
                    DispatchQueue.main.async {
                        self.isFavorite = true // Optimistically update UI
                    }
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
}

// FIX: Added a preview provider and injected a sample environment object
// This resolves the "Ambiguous use of 'init'" error.
#Preview {
    PlayerView()
        .environmentObject(SpotifyAuthManager())
}