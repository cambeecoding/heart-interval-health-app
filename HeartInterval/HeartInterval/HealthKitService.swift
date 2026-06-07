import HealthKit

/// Protocol surface for ExerciseViewModel — enables a test double without HealthKit.
protocol HealthKitServicing: AnyObject {
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func startObservingHeartRate(since: Date, handler: @escaping (Double, Date) -> Void)
    func fetchRecentSample(within seconds: TimeInterval, completion: @escaping (Double?) -> Void)
    func isAuthorized() -> Bool
    func stopObservingHeartRate()
}

final class HealthKitService: HealthKitServicing {

    private let store  = HKHealthStore()
    private let hrType = HKQuantityType(.heartRate)

    private var observerQuery: HKObserverQuery?
    private var pollTimer: Timer?

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        store.requestAuthorization(toShare: [], read: [hrType]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Calls handler with (bpm, sampleDate) — date lets the caller deduplicate.
    /// `since` anchors the query so pre-exercise samples can never be returned.
    func startObservingHeartRate(since: Date, handler: @escaping (Double, Date) -> Void) {
        let unit = HKUnit.count().unitDivided(by: .minute())

        store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { _, _ in }

        let observer = HKObserverQuery(sampleType: hrType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            self?.fetchLatestSample(since: since, unit: unit, handler: handler)
            completionHandler()
        }
        store.execute(observer)
        observerQuery = observer

        // 5-second polling fallback for Garmin's inconsistent batch writes
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.fetchLatestSample(since: since, unit: unit, handler: handler)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        fetchLatestSample(since: since, unit: unit, handler: handler)
    }

    private func fetchLatestSample(since: Date, unit: HKUnit, handler: @escaping (Double, Date) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let bpm = sample.quantity.doubleValue(for: unit)
            handler(bpm, sample.endDate)
        }
        store.execute(query)
    }

    /// One-shot liveness check: returns the most recent HR sample if written
    /// within `seconds` seconds, otherwise nil. Used for standby polling to
    /// detect whether the Watch is actively streaming HR right now.
    func fetchRecentSample(within seconds: TimeInterval, completion: @escaping (Double?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(nil); return
        }
        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-seconds),
            end: nil,
            options: []
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let q = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            let bpm = (samples?.first as? HKQuantitySample)
                .map { $0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) }
            DispatchQueue.main.async { completion(bpm) }
        }
        store.execute(q)
    }

    /// Returns true if the user has already authorized sharing of heart rate data.
    /// Does not prompt — read-only status check.
    func isAuthorized() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return HKHealthStore().authorizationStatus(for: HKObjectType.quantityType(forIdentifier: .heartRate)!) == .sharingAuthorized
    }

    func stopObservingHeartRate() {
        if let q = observerQuery { store.stop(q); observerQuery = nil }
        pollTimer?.invalidate(); pollTimer = nil
        store.disableBackgroundDelivery(for: hrType) { _, _ in }
    }
}
