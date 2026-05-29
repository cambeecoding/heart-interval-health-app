import SwiftUI

struct StandbyView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("BeatZone")
                    .font(.title)
                    .fontWeight(.light)
                    .foregroundColor(.white.opacity(0.6))

                // HR source status label
                let status = viewModel.hrSourceStatus
                if !status.message.isEmpty {
                    Text(status.message)
                        .font(.footnote)
                        .foregroundColor(status.isReady ? .green.opacity(0.8) : .orange.opacity(0.7))
                        .padding(.top, 6)
                }

                Spacer()
                    .frame(height: 32)

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
                .padding(.bottom, 24)

                // Dual-handle HR range slider
                HRRangeSlider(range: 60...200, low: $viewModel.minHR, high: $viewModel.maxHR)
                    .padding(.bottom, 28)

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
