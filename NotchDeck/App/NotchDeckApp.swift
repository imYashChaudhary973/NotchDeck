import SwiftUI

/// Application entry point.
///
/// Phase 0 placeholder: this only proves the project builds and launches.
/// The notch window, Activity Engine and state machine arrive in Phase 1
/// (see ROADMAP.md and ARCHITECTURE.md).
@main
struct NotchDeckApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 8) {
                Text("NotchDeck")
                    .font(.title)
                Text("Under construction — Phase 1 has not started.")
                    .foregroundStyle(.secondary)
            }
            .padding(32)
        }
    }
}
