import HealthKit

final class HealthKitService {

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
    func startObservingHeartRate(handler: @escaping (Double, Date) -> Void) {
        let unit = HKUnit.count().unitDivided(by: .minute())

        store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { _, _ in }

        let observer = HKObserverQuery(sampleType: hrType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else { completionHandler(); return }
            self?.fetchLatestSample(unit: unit, handler: handler)
            completionHandler()
        }
        store.execute(observer)
        observerQuery = observer

        // 5-second polling fallback for Garmin's inconsistent batch writes
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.fetchLatestSample(unit: unit, handler: handler)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        fetchLatestSample(unit: unit, handler: handler)
    }

    private func fetchLatestSample(unit: HKUnit, handler: @escaping (Double, Date) -> Void) {
        // Only accept samples written in the last 5 minutes — prevents stale
        // resting-HR readings (e.g. 57bpm from hours ago) from being displayed
        let freshPredicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-300),
            end: nil,
            options: []
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrType, predicate: freshPredicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let bpm = sample.quantity.doubleValue(for: unit)
            handler(bpm, sample.endDate)
        }
        store.execute(query)
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
