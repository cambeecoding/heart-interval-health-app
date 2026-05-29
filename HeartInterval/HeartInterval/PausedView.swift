import SwiftUI

struct PausedView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                MetricRow(label: "Avg total", value: viewModel.totalAvgHR, unit: "bpm", valueColor: .white)
                    .padding(.bottom, 24)

                MetricRow(label: "Last min", value: viewModel.lastMinuteAvgHR, unit: "bpm", valueColor: .yellow)
                    .padding(.bottom, 24)

                MetricRow(label: "Current", value: viewModel.currentHR, unit: "bpm", valueColor: .white.opacity(0.6))

                Spacer()

                HStack(spacing: 20) {
                    Button(action: { viewModel.endExercise() }) {
                        Text("END")
                            .font(.headline)
                            .frame(width: 120, height: 52)
                            .background(Color.red.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    Button(action: { viewModel.continueExercise() }) {
                        Text("CONTINUE")
                            .font(.headline)
                            .frame(width: 140, height: 52)
                            .background(Color.green.opacity(0.85))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.bottom, 48)
            }
        }
    }
}
