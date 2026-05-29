import SwiftUI

struct StandbyView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Central graphic
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        .frame(width: 160, height: 160)
                    Image(systemName: "heart.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.white.opacity(0.85))
                }

                Text("Heart Interval")
                    .font(.title2)
                    .fontWeight(.light)
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                // Announcement interval toggle — only configurable before starting
                HStack(spacing: 0) {
                    Button(action: { viewModel.shortInterval = true }) {
                        Text("30s")
                            .font(.subheadline).fontWeight(.medium)
                            .frame(width: 70, height: 36)
                            .background(viewModel.shortInterval ? Color.blue : Color.clear)
                            .foregroundColor(.white)
                    }
                    Button(action: { viewModel.shortInterval = false }) {
                        Text("60s")
                            .font(.subheadline).fontWeight(.medium)
                            .frame(width: 70, height: 36)
                            .background(!viewModel.shortInterval ? Color.blue : Color.clear)
                            .foregroundColor(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.2), lineWidth: 1))

                Button(action: { viewModel.startExercise() }) {
                    Text("START")
                        .font(.headline)
                        .frame(width: 160, height: 52)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
        }
    }
}
