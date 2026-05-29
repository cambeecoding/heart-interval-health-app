import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ExerciseViewModel()

    var body: some View {
        switch viewModel.appState {
        case .standby:
            StandbyView(viewModel: viewModel)
        case .exercising:
            ExerciseView(viewModel: viewModel)
        case .paused:
            PausedView(viewModel: viewModel)
        }
    }
}
