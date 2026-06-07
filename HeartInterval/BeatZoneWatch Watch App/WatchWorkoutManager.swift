import Foundation
import Combine
import HealthKit

final class WatchWorkoutManager: NSObject, ObservableObject {

    var onHeartRate: ((Double, Date) -> Void)?

    @Published var isWorkoutActive = false
    @Published var currentBPM: Double?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private var throttleTimer: Timer?
    private var latestBPM: Double?
    private var latestDate: Date?
    private let sendInterval: TimeInterval = 2

    func startWorkout() {
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate)
        ]
        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { [weak self] _, error in
            #if DEBUG
            if let error {
                print("[BeatZone Watch] HealthKit auth error: \(error)")
            }
            #endif
            DispatchQueue.main.async {
                self?.beginWorkoutSession()
            }
        }
    }

    private func beginWorkoutSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
        } catch {
            #if DEBUG
            print("[BeatZone Watch] Failed to create workout session: \(error)")
            #endif
            return
        }

        session?.delegate = self
        builder?.delegate = self
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                       workoutConfiguration: config)

        let startDate = Date()
        session?.startActivity(with: startDate)
        builder?.beginCollection(withStart: startDate) { [weak self] success, error in
            #if DEBUG
            if let error {
                print("[BeatZone Watch] beginCollection error: \(error)")
            }
            #endif
            guard success else { return }
            DispatchQueue.main.async {
                self?.isWorkoutActive = true
                self?.startThrottleTimer()
            }
        }
    }

    func stopWorkout() {
        session?.end()
    }

    private func startThrottleTimer() {
        throttleTimer?.invalidate()
        throttleTimer = Timer.scheduledTimer(withTimeInterval: sendInterval, repeats: true) { [weak self] _ in
            self?.flushLatestSample()
        }
    }

    private func stopThrottleTimer() {
        throttleTimer?.invalidate()
        throttleTimer = nil
    }

    private func flushLatestSample() {
        guard let bpm = latestBPM, let date = latestDate else { return }
        onHeartRate?(bpm, date)
        latestBPM = nil
        latestDate = nil
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        DispatchQueue.main.async { [weak self] in
            self?.isWorkoutActive = (toState == .running)
            if toState == .ended {
                self?.stopThrottleTimer()
                self?.builder?.endCollection(withEnd: date) { _, _ in
                    self?.builder?.finishWorkout { _, _ in }
                }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        #if DEBUG
        print("[BeatZone Watch] Workout session error: \(error)")
        #endif
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType) else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let statistics = workoutBuilder.statistics(for: hrType),
              let value = statistics.mostRecentQuantity()?.doubleValue(for: unit) else { return }

        let date = statistics.mostRecentQuantityDateInterval()?.end ?? Date()

        DispatchQueue.main.async { [weak self] in
            self?.currentBPM = value
            self?.latestBPM = value
            self?.latestDate = date
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
