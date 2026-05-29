import HealthKit

final class HealthKitService {

    private let store = HKHealthStore()
    private let hrType = HKQuantityType(.heartRate)
    private var query: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        store.requestAuthorization(toShare: [], read: [hrType]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Starts a live HKAnchoredObjectQuery that calls `handler` for every new HR sample.
    func startObservingHeartRate(handler: @escaping (Double) -> Void) {
        let unit = HKUnit.count().unitDivided(by: .minute())

        let updateHandler: HKAnchoredObjectQueryHandler = { [weak self] query, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            guard let samples = samples as? [HKQuantitySample] else { return }
            for sample in samples {
                let bpm = sample.quantity.doubleValue(for: unit)
                handler(bpm)
            }
        }

        let q = HKAnchoredObjectQuery(
            type: hrType,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit,
            resultsHandler: updateHandler
        )
        q.updateHandler = updateHandler
        store.execute(q)
        query = q
    }

    func stopObservingHeartRate() {
        if let q = query {
            store.stop(q)
            query = nil
        }
    }
}
