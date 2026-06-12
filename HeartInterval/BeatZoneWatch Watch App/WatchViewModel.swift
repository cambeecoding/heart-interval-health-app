import Foundation
import Combine
import WatchKit

@MainActor
final class WatchViewModel: ObservableObject {

    @Published var currentBPM: Double?
    @Published var isWorkoutActive = false
    @Published var isPhoneReachable = false

    @Published var intervalPhase: String?
    @Published var intervalRound: Int = 0
    @Published var intervalCountdown: Int = 0
    @Published var intervalTotalRounds: Int = 0
    @Published var isIntervalActive: Bool = false

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

        connectivityManager.$intervalPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard let self, let phase else { return }
                self.intervalPhase = phase
                self.isIntervalActive = phase != "finished"
                self.fireHaptic(for: phase)
            }
            .store(in: &cancellables)

        connectivityManager.$intervalRound
            .receive(on: RunLoop.main)
            .assign(to: &$intervalRound)

        connectivityManager.$intervalCountdown
            .receive(on: RunLoop.main)
            .assign(to: &$intervalCountdown)

        connectivityManager.$intervalTotalRounds
            .receive(on: RunLoop.main)
            .assign(to: &$intervalTotalRounds)

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
        connectivityManager.clearIntervalState()
        isIntervalActive = false
        intervalPhase = nil
    }

    private func fireHaptic(for phase: String) {
        switch phase {
        case "work":
            WKInterfaceDevice.current().play(.notification)
        case "rest":
            WKInterfaceDevice.current().play(.click)
        case "finished":
            WKInterfaceDevice.current().play(.success)
        default:
            break
        }
    }
}
