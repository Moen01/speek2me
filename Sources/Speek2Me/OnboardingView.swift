import SwiftUI

/// Placeholder until Task 12 builds the step list.
struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var controller: AnnouncementController
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome to Speek2Me").font(.title)
            Button("Finish", action: finish)
        }
        .padding(40)
    }
}
