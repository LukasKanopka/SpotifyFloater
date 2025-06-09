// FILE: ContentView.swift
// DESCRIPTION: Replace the contents of ContentView.swift with this code.
//
import Foundation // Added for potential future use, good practice
import SwiftUI // Already present, but ensuring it's here
import Combine // Added for potential future use with ObservableObject
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: SpotifyAuthManager
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                // If we are authenticated, show the player UI.
                PlayerView()
            } else {
                // If not authenticated, show the login button.
                VStack(spacing: 20) {
                    Text("Spotify Hover Player")
                        .font(.largeTitle)
                    Text("Please log in to continue.")
                    
                    Button("Login with Spotify") {
                        authManager.startAuthentication()
                    }
                    .padding()
                    .background(Color(red: 0.11, green: 0.82, blue: 0.33)) // Spotify Green
                    .foregroundColor(.white)
                    .cornerRadius(25) // More rounded corners
                }
                .frame(width: 300, height: 200) // Adjusted frame size
                .background(Color(red: 0.1, green: 0.1, blue: 0.1)) // Dark background color
                .cornerRadius(25) // Apply corner radius to the container
                .shadow(radius: 10) // Add a subtle shadow
            }
        }
    }
}