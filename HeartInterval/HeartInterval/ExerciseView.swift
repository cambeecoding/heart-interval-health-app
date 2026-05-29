import SwiftUI

struct ExerciseView: View {
    @ObservedObject var viewModel: ExerciseViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                MetricRow(label: "Current", value: viewModel.currentHR, unit: "bpm", valueColor: .white)
                    .padding(.bottom, 28)

                MetricRow(label: "Last min", value: viewModel.lastMinuteAvgHR, unit: "bpm", valueColor: .yellow)

                Spacer()

                Button(action: { viewModel.pauseExercise() }) {
                    Text("PAUSE")
                        .font(.headline)
                        .frame(width: 160, height: 52)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.bottom, 48)
            }
        }
    }
}
