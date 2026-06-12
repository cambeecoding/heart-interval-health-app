import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ExerciseViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.appState {
            case .launching:
                SplashView()
                    .transition(.opacity)
            case .standby:
                StandbyView(viewModel: viewModel)
                    .transition(.opacity)
            case .starting:
                if let remaining = viewModel.startCountdownRemaining {
                    StartCountdownView(remaining: remaining, mode: viewModel.trainingMode)
                        .transition(.opacity)
                } else {
                    StartingView()
                        .transition(.opacity)
                }
            case .exercising:
                if viewModel.trainingMode == .intervals {
                    IntervalExerciseView(viewModel: viewModel)
                        .transition(.opacity)
                } else {
                    ExerciseView(viewModel: viewModel)
                        .transition(.opacity)
                }
            case .paused:
                PausedView(viewModel: viewModel)
                    .transition(.opacity)
            case .summary(let summary):
                if summary.intervalData != nil {
                    IntervalSummaryView(viewModel: viewModel, summary: summary)
                        .transition(.opacity)
                } else {
                    SummaryView(viewModel: viewModel, summary: summary)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.appState)
    }
}

// MARK: - Start countdown

private struct StartCountdownView: View {
    let remaining: Int
    let mode: TrainingMode

    var body: some View {
        VStack(spacing: 12) {
            Text("GET READY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.4))
                .tracking(2)

            Text("\(remaining)")
                .font(.system(size: 120, weight: .ultraLight, design: .rounded))
                .foregroundColor(mode == .zone ? .blue : .orange)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: remaining)
        }
    }
}
