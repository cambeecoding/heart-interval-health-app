import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = WatchViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            if viewModel.isIntervalActive {
                WatchIntervalView(viewModel: viewModel)
            } else if let bpm = viewModel.currentBPM {
                Text("\(Int(bpm.rounded()))")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(.red)
                Text("BPM")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            } else if viewModel.isWorkoutActive {
                Text("--")
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.3))
                Text("Waiting for HR")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Text("BeatZone")
                    .font(.title3)
                    .fontWeight(.medium)
            }

            Spacer()

            Button(action: {
                if viewModel.isWorkoutActive {
                    viewModel.stopWorkout()
                } else {
                    viewModel.startWorkout()
                }
            }) {
                Text(viewModel.isWorkoutActive ? "Stop" : "Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isWorkoutActive ? .red : .green)

            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.isPhoneReachable ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(viewModel.isPhoneReachable ? "iPhone connected" : "iPhone not reachable")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding()
    }
}
