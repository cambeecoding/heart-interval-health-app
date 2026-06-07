import XCTest
@testable import BeatZone

// MARK: - Spy

final class SpyHealthKitService: HealthKitServicing {
    var authorized = false
    var authorizationResult = true
    var recentSampleResult: Double? = nil
    var observingSince: Date?
    var observingHandler: ((Double, Date) -> Void)?
    var stopObservingCalls = 0
    var recentSampleCalls = 0
    var requestAuthCalls = 0

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        requestAuthCalls += 1
        authorized = authorizationResult
        completion(authorizationResult)
    }

    func startObservingHeartRate(since: Date, handler: @escaping (Double, Date) -> Void) {
        observingSince = since
        observingHandler = handler
    }

    func fetchRecentSample(within seconds: TimeInterval, completion: @escaping (Double?) -> Void) {
        recentSampleCalls += 1
        // Synchronous in tests — deterministic and avoids RunLoop-vs-Task pumping flake.
        completion(recentSampleResult)
    }

    func isAuthorized() -> Bool { authorized }

    func stopObservingHeartRate() { stopObservingCalls += 1 }
}

// MARK: - Tests

@MainActor
final class ExerciseViewModelHRSourceTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(hk: SpyHealthKitService = SpyHealthKitService(),
                        pollInterval: TimeInterval = 0.05) -> ExerciseViewModel {
        ExerciseViewModel(audioService: SpyAudioService(),
                          healthKitService: hk,
                          standbyPollInterval: pollInterval)
    }

    /// Wait until `condition` is true, or fail after `timeout`.
    private func wait(for condition: @autoclosure () -> Bool,
                      timeout: TimeInterval = 1.0,
                      _ message: String = "",
                      file: StaticString = #file,
                      line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    // =========================================================================
    // MARK: - bleSourceStatus
    // =========================================================================

    func test_bleStatus_connected_whenSourceIsBLE() {
        let vm = makeVM()
        vm.hrSource = .ble
        XCTAssertEqual(vm.bleSourceStatus.message, "Bluetooth HR monitor connected")
        XCTAssertTrue(vm.bleSourceStatus.isReady)
    }

    func test_bleStatus_connected_whenBLEStatusString() {
        let vm = makeVM()
        vm.bleStatus = "HR monitor connected"
        XCTAssertEqual(vm.bleSourceStatus.message, "Bluetooth HR monitor connected")
        XCTAssertTrue(vm.bleSourceStatus.isReady)
    }

    func test_bleStatus_scanning() {
        let vm = makeVM()
        vm.bleStatus = "Scanning for HR monitor…"
        XCTAssertTrue(vm.bleSourceStatus.message.contains("Scanning"))
        XCTAssertFalse(vm.bleSourceStatus.isReady)
    }

    func test_bleStatus_connecting() {
        let vm = makeVM()
        vm.bleStatus = "Connecting…"
        XCTAssertTrue(vm.bleSourceStatus.message.contains("Connecting"))
        XCTAssertFalse(vm.bleSourceStatus.isReady)
    }

    func test_bleStatus_disconnectedDuringExercise_emptyRow() {
        let vm = makeVM()
        vm.bleStatus = "HR monitor disconnected — reconnecting…"
        XCTAssertEqual(vm.bleSourceStatus.message, "",
                       "Disconnect-reconnect noise should not occupy the standby row")
    }

    func test_bleStatus_idle_emptyRow() {
        let vm = makeVM()
        vm.bleStatus = ""
        vm.hrSource = .none
        XCTAssertEqual(vm.bleSourceStatus.message, "")
    }

    func test_bleStatus_unknownStatusString_emptyRow() {
        let vm = makeVM()
        vm.bleStatus = "garbage"
        XCTAssertEqual(vm.bleSourceStatus.message, "",
                       "Unrecognized status strings should fall through to empty")
    }

    // =========================================================================
    // MARK: - watchSourceStatus
    // =========================================================================

    func test_watchStatus_notAuthorized_emptyRow() {
        let hk = SpyHealthKitService()
        hk.authorized = false
        let vm = makeVM(hk: hk)
        XCTAssertEqual(vm.watchSourceStatus.message, "")
    }

    func test_watchStatus_authorizedNoLiveSample() {
        let hk = SpyHealthKitService()
        hk.authorized = true
        let vm = makeVM(hk: hk)
        vm.standbyWatchBPM = nil
        XCTAssertTrue(vm.watchSourceStatus.message.contains("start a workout"))
        XCTAssertFalse(vm.watchSourceStatus.isReady)
    }

    func test_watchStatus_authorizedWithLiveSample() {
        let hk = SpyHealthKitService()
        hk.authorized = true
        let vm = makeVM(hk: hk)
        vm.standbyWatchBPM = 132.4
        XCTAssertTrue(vm.watchSourceStatus.message.contains("132 bpm"),
                      "Got: \(vm.watchSourceStatus.message)")
        XCTAssertTrue(vm.watchSourceStatus.isReady)
    }

    func test_watchStatus_bpmRoundsCorrectly() {
        let hk = SpyHealthKitService()
        hk.authorized = true
        let vm = makeVM(hk: hk)
        vm.standbyWatchBPM = 132.6
        XCTAssertTrue(vm.watchSourceStatus.message.contains("133 bpm"),
                      "Got: \(vm.watchSourceStatus.message)")
    }

    func test_watchStatus_authorizedZeroBPM_documentsBehavior() {
        // Documents current behaviour: 0 still flips to streaming/green.
        // If undesired, change watchSourceStatus to treat 0 as nil.
        let hk = SpyHealthKitService()
        hk.authorized = true
        let vm = makeVM(hk: hk)
        vm.standbyWatchBPM = 0
        XCTAssertTrue(vm.watchSourceStatus.isReady)
        XCTAssertTrue(vm.watchSourceStatus.message.contains("0 bpm"))
    }

    // =========================================================================
    // MARK: - shouldShowSourceInstruction
    // =========================================================================

    func test_instruction_visibleWhenNeitherReady() {
        let hk = SpyHealthKitService()
        hk.authorized = false
        let vm = makeVM(hk: hk)
        XCTAssertTrue(vm.shouldShowSourceInstruction)
    }

    func test_instruction_hiddenWhenBLEReady() {
        let vm = makeVM()
        vm.hrSource = .ble
        XCTAssertFalse(vm.shouldShowSourceInstruction)
    }

    func test_instruction_hiddenWhenWatchStreaming() {
        let hk = SpyHealthKitService()
        hk.authorized = true
        let vm = makeVM(hk: hk)
        vm.standbyWatchBPM = 120
        XCTAssertFalse(vm.shouldShowSourceInstruction)
    }

    // =========================================================================
    // MARK: - Standby poll lifecycle
    // =========================================================================

    func test_standbyPoll_startsAfterSplash() {
        let hk = SpyHealthKitService()
        _ = makeVM(hk: hk)
        // init schedules the splash→standby transition with 1.5s sleep;
        // wait for at least one fetchRecentSample call to confirm the poll kicked in.
        wait(for: hk.recentSampleCalls >= 1, timeout: 3.0,
             "Standby poll should fire after splash transition")
    }

    func test_pollStandbyHR_updatesPublishedBPM() async {
        let hk = SpyHealthKitService()
        hk.recentSampleResult = 120
        let vm = makeVM(hk: hk)
        vm.pollStandbyHR()
        await Task.yield()
        XCTAssertEqual(vm.standbyWatchBPM, 120)
    }

    func test_pollStandbyHR_nilResultClearsBPM() async {
        let hk = SpyHealthKitService()
        hk.recentSampleResult = 120
        let vm = makeVM(hk: hk)
        vm.pollStandbyHR()
        await Task.yield()
        XCTAssertEqual(vm.standbyWatchBPM, 120)

        hk.recentSampleResult = nil
        vm.pollStandbyHR()
        await Task.yield()
        XCTAssertNil(vm.standbyWatchBPM,
                     "Watch dropping out of workout mode should clear standbyWatchBPM")
    }

    func test_startExercise_stopsStandbyPoll() {
        let hk = SpyHealthKitService()
        let vm = makeVM(hk: hk)
        vm.standbyWatchBPM = 120
        vm.startExercise()
        XCTAssertNil(vm.standbyWatchBPM, "startExercise should clear standby BPM")

        let callsBefore = hk.recentSampleCalls
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(hk.recentSampleCalls, callsBefore,
                       "Standby poll must not fire during exercise")
    }

    func test_endExercise_resumesStandbyPoll() {
        let hk = SpyHealthKitService()
        let vm = makeVM(hk: hk)
        vm.startExercise()
        let callsAfterStart = hk.recentSampleCalls

        vm.endExercise()
        wait(for: hk.recentSampleCalls > callsAfterStart, timeout: 2.5,
             "endExercise should restart the standby poll")
    }

    // =========================================================================
    // MARK: - startExercise / endExercise / observer integration
    // =========================================================================

    func test_startExercise_capturesStartDate_andPassesToObserver() {
        let hk = SpyHealthKitService()
        hk.authorizationResult = true
        let vm = makeVM(hk: hk)

        let before = Date()
        vm.startExercise()
        wait(for: hk.observingSince != nil, timeout: 1.0,
             "startObservingHeartRate should be invoked after auth grant")
        let since = hk.observingSince!
        let after = Date()
        XCTAssertGreaterThanOrEqual(since.timeIntervalSince1970, before.timeIntervalSince1970 - 0.01)
        XCTAssertLessThanOrEqual(since.timeIntervalSince1970, after.timeIntervalSince1970 + 0.01)
    }

    func test_startExercise_doesNotInvokeObserverWhenAuthDenied() {
        let hk = SpyHealthKitService()
        hk.authorizationResult = false
        let vm = makeVM(hk: hk)
        vm.startExercise()
        // Give the 150ms task time to run.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertNil(hk.observingSince,
                     "Observer must not be started when HealthKit auth is denied")
    }

    func test_endExercise_callsStopObserving() {
        let hk = SpyHealthKitService()
        let vm = makeVM(hk: hk)
        vm.endExercise()
        XCTAssertEqual(hk.stopObservingCalls, 1)
    }

    func test_blePriority_healthKitSampleIgnoredWhenBLEActive() {
        let hk = SpyHealthKitService()
        hk.authorizationResult = true
        let vm = makeVM(hk: hk)

        vm.startExercise()
        wait(for: hk.observingHandler != nil, timeout: 1.0)

        // Simulate BLE taking over first.
        vm.handleNewHRSample(150, source: .ble)
        XCTAssertEqual(vm.currentHR, 150)

        // HealthKit handler later delivers a different value — must be ignored.
        hk.observingHandler?(99, Date())
        // Let the @MainActor Task drain.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(vm.currentHR, 150,
                       "HealthKit samples must not override an active BLE source")
    }

    func test_repeatedStart_resetsStandbyBPM() {
        let hk = SpyHealthKitService()
        let vm = makeVM(hk: hk)
        vm.standbyWatchBPM = 100
        vm.startExercise()
        XCTAssertNil(vm.standbyWatchBPM)
    }

    // =========================================================================
    // MARK: - Frozen-HR regression: `since:` anchor
    // =========================================================================

    func test_observerSince_isAtOrAfterStartCall() {
        // Direct regression for the frozen-HR bug: the `since:` value passed to
        // startObservingHeartRate must be >= the moment the user pressed START,
        // so pre-exercise HealthKit samples (e.g. stale 61 bpm) cannot be returned.
        let hk = SpyHealthKitService()
        let vm = makeVM(hk: hk)
        let pressStart = Date()
        vm.startExercise()
        wait(for: hk.observingSince != nil, timeout: 1.0)
        XCTAssertGreaterThanOrEqual(hk.observingSince!.timeIntervalSince1970,
                                    pressStart.timeIntervalSince1970 - 0.01,
                                    "`since:` must not be earlier than the start of the exercise")
    }
}
