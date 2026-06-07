import Foundation
import Combine

@MainActor
final class WatchViewModel: ObservableObject {

    @Published var currentBPM: Double?
    @Published var isWorkoutActive = false
    @Published var isPhoneReachable = false

    private let workoutManager = WatchWorkoutManager()
    private let connectivityManager = WatchConnectivityManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        workoutManager.$currentBPM
            .receive(on: RunLoop.main)
            .assign(to: &$currentBPM)

        workoutManager.$isWorkoutActive
            .receive(on: RunLoop.main)
            .assign(to: &$isWorkoutActive)

        connectivityManager.$isPhoneReachable
            .receive(on: RunLoop.main)
            .assign(to: &$isPhoneReachable)

        workoutManager.onHeartRate = { [weak self] bpm, date in
            self?.connectivityManager.sendHeartRate(bpm, date: date)
        }
    }

    func startWorkout() {
        workoutManager.startWorkout()
        connectivityManager.sendStartExercise()
    }

    func stopWorkout() {
        workoutManager.stopWorkout()
        connectivityManager.sendWorkoutEnded()
    }
}
