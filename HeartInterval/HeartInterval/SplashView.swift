import SwiftUI

struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {

                // Logo — lightning bolt over heart, matching app icon concept
                ZStack {
                    Image(systemName: "heart.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.85, green: 0.1, blue: 0.1),
                                         Color(red: 0.6,  green: 0.0, blue: 0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(pulse ? 1.06 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: pulse
                        )

                    Image(systemName: "bolt.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, Color(red: 1, green: 0.8, blue: 0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .offset(y: -2)
                        .shadow(color: .yellow.opacity(0.6), radius: 8)
                }

                // App name
                VStack(spacing: 4) {
                    Text("BeatZone")
                        .font(.system(size: 32, weight: .thin, design: .rounded))
                        .foregroundColor(.white)

                    Text("heart rate training")
                        .font(.system(size: 12, weight: .light))
                        .foregroundColor(.white.opacity(0.35))
                        .tracking(1.5)
                }

                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.4)))
                    .scaleEffect(0.9)
            }
        }
        .onAppear { pulse = true }
    }
}
