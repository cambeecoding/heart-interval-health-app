import SwiftUI

struct StartingView: View {
    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.4)

            Text("Starting…")
                .font(.headline)
                .fontWeight(.light)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
