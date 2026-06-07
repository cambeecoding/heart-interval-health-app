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
                StartingView()
                    .transition(.opacity)
            case .exercising:
                ExerciseView(viewModel: viewModel)
                    .transition(.opacity)
            case .paused:
                PausedView(viewModel: viewModel)
                    .transition(.opacity)
            case .summary(let summary):
                SummaryView(viewModel: viewModel, summary: summary)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.appState)
    }
}
