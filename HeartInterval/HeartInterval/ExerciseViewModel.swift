import Foundation
import Combine

enum AppState {
    case standby
    case exercising
    case paused
}

@MainActor
final class ExerciseViewModel: ObservableObject {

    // MARK: - Published state
    @Published var appState: AppState = .standby
    @Published var currentHR: Int? = nil
    @Published var lastMinuteAvgHR: Int? = nil
    @Published var totalAvgHR: Int? = nil

    // MARK: - Services
    private let healthKitService = HealthKitService()
    private let audioService = AudioService()
    private let workoutManager = WorkoutManager()

    // MARK: - Internal bookkeeping
    /// All HR samples collected since START (value, timestamp)
    private var allSamples: [(value: Double, date: Date)] = []
    /// Samples collected in the current 60-second window
    private var windowSamples: [Double] = []
    private var minuteTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Actions

    func startExercise() {
        allSamples = []
        windowSamples = []
        currentHR = nil
        lastMinuteAvgHR = nil
        totalAvgHR = nil

        workoutManager.beginExercise()
        appState = .exercising

        healthKitService.requestAuthorization { [weak self] granted in
            guard granted else { return }
            self?.healthKitService.startObservingHeartRate { [weak self] bpm in
                Task { @MainActor [weak self] in
                    self?.handleNewHRSample(bpm)
                }
            }
        }

        startMinuteTimer()
    }

    func pauseExercise() {
        minuteTimer?.invalidate()
        appState = .paused
        announceMetrics(includeTotal: true)
    }

    func continueExercise() {
        appState = .exercising
        windowSamples = []
        startMinuteTimer()
    }

    func endExercise() {
        minuteTimer?.invalidate()
        healthKitService.stopObservingHeartRate()
        workoutManager.endExercise()
        appState = .standby
        currentHR = nil
        lastMinuteAvgHR = nil
        totalAvgHR = nil
    }

    // MARK: - Private helpers

    private func handleNewHRSample(_ bpm: Double) {
        let now = Date()
        allSamples.append((bpm, now))
        windowSamples.append(bpm)
        currentHR = Int(bpm.rounded())
        totalAvgHR = average(of: allSamples.map(\.value))
    }

    private func startMinuteTimer() {
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onMinuteTick()
            }
        }
    }

    private func onMinuteTick() {
        lastMinuteAvgHR = average(of: windowSamples)
        windowSamples = []
        announceMetrics(includeTotal: false)
    }

    private func announceMetrics(includeTotal: Bool) {
        var parts: [String] = []

        if let last = lastMinuteAvgHR {
            parts.append("Last minute heart rate is \(last) beats per minute.")
        }
        if let current = currentHR {
            parts.append("Current heart rate is \(current) beats per minute.")
        }
        if includeTotal, let total = totalAvgHR {
            parts.append("Total average heart rate is \(total) beats per minute.")
        }

        guard !parts.isEmpty else { return }
        audioService.speak(parts.joined(separator: " "))
    }

    private func average(of values: [Double]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }
}
