import HealthKit

/// Protocol surface for ExerciseViewModel — enables a test double without HealthKit.
protocol HealthKitServicing: AnyObject {
    func requestAuthorization(completion: @escaping (Bool) -> Void)
    func startObservingHeartRate(since: Date, handler: @escaping (Double, Date) -> Void)
    func fetchRecentSample(within seconds: TimeInterval, completion: @escaping (Double?) -> Void)
    func stopObservingHeartRate()
    func saveWorkout(_ summary: SessionSummary, completion: @escaping (Result<Void, Error>) -> Void)
}

extension HealthKitServicing {
    func saveWorkout(_ summary: SessionSummary, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.success(()))
    }
}

final class HealthKitService: HealthKitServicing {

    private let store  = HKHealthStore()
    private let hrType = HKQuantityType(.heartRate)

    private var observerQuery: HKObserverQuery?
    private var pollTimer: Timer?

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            #if DEBUG
            print("[BeatZone HK] HealthKit not available on this device")
            #endif
            completion(false)
            return
        }
        let writeTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate)
        ]
        store.requestAuthorization(toShare: writeTypes, read: [hrType]) { granted, error in
            #if DEBUG
            if let error {
                print("[BeatZone HK] requestAuthorization error: \(error.localizedDescription)")
            }
            print("[BeatZone HK] requestAuthorization returned granted=\(granted) (note: 'granted' reflects whether the dialog was presented, NOT whether read was actually granted)")
            #endif
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Calls handler with (bpm, sampleDate) — date lets the caller deduplicate.
    /// `since` anchors the query so pre-exercise samples can never be returned.
    func startObservingHeartRate(since: Date, handler: @escaping (Double, Date) -> Void) {
        let unit = HKUnit.count().unitDivided(by: .minute())

        #if DEBUG
        print("[BeatZone HK] startObservingHeartRate since=\(since)")
        #endif

        store.enableBackgroundDelivery(for: hrType, frequency: .immediate) { success, error in
            #if DEBUG
            if let error {
                print("[BeatZone HK] enableBackgroundDelivery error: \(error.localizedDescription)")
            } else {
                print("[BeatZone HK] enableBackgroundDelivery success=\(success)")
            }
            #endif
        }

        let observer = HKObserverQuery(sampleType: hrType, predicate: nil) { [weak self] _, completionHandler, error in
            #if DEBUG
            if let error {
                print("[BeatZone HK] Observer query error: \(error.localizedDescription)")
            } else {
                print("[BeatZone HK] Observer query fired")
            }
            #endif
            guard error == nil else { completionHandler(); return }
            self?.fetchLatestSample(since: since, unit: unit, source: "observer", handler: handler)
            completionHandler()
        }
        store.execute(observer)
        observerQuery = observer

        // 5-second polling fallback for Garmin's inconsistent batch writes
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.fetchLatestSample(since: since, unit: unit, source: "poll", handler: handler)
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        fetchLatestSample(since: since, unit: unit, source: "initial", handler: handler)
    }

    private func fetchLatestSample(since: Date, unit: HKUnit, source: String,
                                   handler: @escaping (Double, Date) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, error in
            #if DEBUG
            if let error {
                print("[BeatZone HK] fetchLatestSample(\(source)) error: \(error.localizedDescription)")
            }
            #endif
            guard let sample = samples?.first as? HKQuantitySample else {
                #if DEBUG
                print("[BeatZone HK] fetchLatestSample(\(source)) returned no samples since=\(since)")
                #endif
                return
            }
            let bpm = sample.quantity.doubleValue(for: unit)
            #if DEBUG
            print("[BeatZone HK] fetchLatestSample(\(source)) → bpm=\(bpm) endDate=\(sample.endDate) source=\(sample.sourceRevision.source.name)")
            #endif
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

    func stopObservingHeartRate() {
        if let q = observerQuery { store.stop(q); observerQuery = nil }
        pollTimer?.invalidate(); pollTimer = nil
        store.disableBackgroundDelivery(for: hrType) { _, _ in }
    }

    func saveWorkout(_ summary: SessionSummary, completion: @escaping (Result<Void, Error>) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(.failure(NSError(
                domain: "com.lbcoding.beatzone",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device."]
            )))
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = summary.activityType.hkType

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        builder.beginCollection(withStart: summary.startDate) { _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            if !summary.samples.isEmpty {
                let unit = HKUnit.count().unitDivided(by: .minute())

                let hrSamples: [HKQuantitySample] = summary.samples.map { sample in
                    HKQuantitySample(
                        type: HKQuantityType(.heartRate),
                        quantity: HKQuantity(unit: unit, doubleValue: sample.bpm),
                        start: sample.date,
                        end: sample.date
                    )
                }

                builder.add(hrSamples) { _, _ in }
            }

            builder.endCollection(withEnd: summary.endDate) { _, error in
                if let error {
                    DispatchQueue.main.async { completion(.failure(error)) }
                    return
                }
                builder.finishWorkout { _, error in
                    DispatchQueue.main.async {
                        if let error { completion(.failure(error)) }
                        else         { completion(.success(())) }
                    }
                }
            }
        }
    }
}
