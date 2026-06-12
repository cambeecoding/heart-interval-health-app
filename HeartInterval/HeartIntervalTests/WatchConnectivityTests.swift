import XCTest
@testable import BeatZone

// MARK: - Spy

@MainActor
final class SpyWatchConnectivityService: WatchConnectivityServicing {
    var onHeartRate: ((Double, Date) -> Void)?
    var onStartExercise: (() -> Void)?
    var onStartIntervalExercise: (() -> Void)?
    var activateCalls = 0

    func activate() { activateCalls += 1 }
    func sendIntervalConfig(_ config: IntervalConfig) {}
    func sendIntervalPhaseUpdate(phase: String, round: Int, countdown: Int, seq: Int, totalRounds: Int) {}
}

// MARK: - Tests

@MainActor
final class WatchConnectivityTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(hk: SpyHealthKitService? = nil,
                        wc: SpyWatchConnectivityService? = nil,
                        pollInterval: TimeInterval = 0.05) -> ExerciseViewModel {
        ExerciseViewModel(audioService: SpyAudioService(),
                          healthKitService: hk ?? SpyHealthKitService(),
                          watchConnectivityService: wc ?? SpyWatchConnectivityService(),
                          standbyPollInterval: pollInterval)
    }

    // =========================================================================
    // MARK: - Activation
    // =========================================================================

    func test_init_activatesWatchConnectivity() {
        let wc = SpyWatchConnectivityService()
        _ = makeVM(wc: wc)
        XCTAssertEqual(wc.activateCalls, 1)
    }

    // =========================================================================
    // MARK: - Watch HR accepted when no BLE
    // =========================================================================

    func test_watchHR_acceptedWhenNoBLE() {
        let wc = SpyWatchConnectivityService()
        let vm = makeVM(wc: wc)
        vm.appState = .exercising

        wc.onHeartRate?(130, Date())
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(vm.currentHR, 130)
        XCTAssertEqual(vm.hrSource, .watch)
    }

    // =========================================================================
    // MARK: - BLE priority over Watch
    // =========================================================================

    func test_watchHR_rejectedWhenBLEActive() {
        let wc = SpyWatchConnectivityService()
        let vm = makeVM(wc: wc)
        vm.appState = .exercising

        vm.handleNewHRSample(150, source: .ble)
        XCTAssertEqual(vm.currentHR, 150)

        wc.onHeartRate?(99, Date())
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(vm.currentHR, 150,
                       "Watch HR must not override an active BLE source")
    }

    // =========================================================================
    // MARK: - Watch priority over HealthKit
    // =========================================================================

    func test_watchPriority_healthKitIgnoredWhenWatchActive() {
        let hk = SpyHealthKitService()
        let wc = SpyWatchConnectivityService()
        let vm = makeVM(hk: hk, wc: wc)

        vm.startExercise()

        let deadline = Date().addingTimeInterval(1.0)
        while hk.observingHandler == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        vm.handleNewHRSample(140, source: .watch)
        XCTAssertEqual(vm.hrSource, .watch)

        hk.observingHandler?(99, Date())
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(vm.currentHR, 140,
                       "HealthKit must not override an active Watch source")
    }

    // =========================================================================
    // MARK: - Watch start triggers exercise
    // =========================================================================

    func test_watchStartExercise_triggersFromStandby() {
        let wc = SpyWatchConnectivityService()
        let vm = makeVM(wc: wc)
        vm.appState = .standby

        wc.onStartExercise?()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertNotEqual(vm.appState, .standby,
                          "Watch startExercise should transition away from standby")
    }

    func test_watchStartExercise_ignoredDuringExercise() {
        let wc = SpyWatchConnectivityService()
        let vm = makeVM(wc: wc)
        vm.appState = .exercising

        wc.onStartExercise?()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(vm.appState, .exercising,
                       "startExercise command should be ignored when already exercising")
    }

    // =========================================================================
    // MARK: - Watch HR on standby updates standbyWatchBPM
    // =========================================================================

    func test_watchHR_onStandby_updatesStandbyBPM() {
        let wc = SpyWatchConnectivityService()
        let vm = makeVM(wc: wc)
        vm.appState = .standby

        wc.onHeartRate?(125, Date())
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(vm.standbyWatchBPM, 125)
    }

    // =========================================================================
    // MARK: - Deduplication by date
    // =========================================================================

    func test_watchHR_deduplicatesByDate() {
        let wc = SpyWatchConnectivityService()
        let vm = makeVM(wc: wc)
        vm.appState = .exercising

        let sampleDate = Date()
        vm.handleNewHRSample(130, source: .watch, date: sampleDate)
        XCTAssertEqual(vm.currentHR, 130)

        vm.handleNewHRSample(999, source: .watch, date: sampleDate)
        XCTAssertEqual(vm.currentHR, 130,
                       "Duplicate date should be rejected")
    }

    // =========================================================================
    // MARK: - Watch timeout falls back
    // =========================================================================

    func test_watchTimeout_resetsSourceToNone() {
        let wc = SpyWatchConnectivityService()
        let vm = makeVM(wc: wc)
        vm.appState = .exercising

        vm.handleNewHRSample(130, source: .watch)
        XCTAssertEqual(vm.hrSource, .watch)

        let expectation = XCTestExpectation(description: "Watch timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 8)

        XCTAssertEqual(vm.hrSource, .none,
                       "After 6s with no Watch HR, source should reset to .none")
    }
}
