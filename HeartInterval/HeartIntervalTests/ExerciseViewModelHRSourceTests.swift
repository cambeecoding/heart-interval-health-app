import XCTest
@testable import BeatZone

// MARK: - Spy

final class SpyHealthKitService: HealthKitServicing {
    var authorizationResult = true
    var recentSampleResult: Double? = nil
    var profileResult = UserProfile()
    var observingSince: Date?
    var observingHandler: ((Double, Date) -> Void)?
    var stopObservingCalls = 0
    var recentSampleCalls = 0
    var requestAuthCalls = 0

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        requestAuthCalls += 1
        completion(authorizationResult)
    }

    func startObservingHeartRate(since: Date, handler: @escaping (Double, Date) -> Void) {
        observingSince = since
        observingHandler = handler
    }

    func fetchRecentSample(within seconds: TimeInterval, completion: @escaping (Double?) -> Void) {
        recentSampleCalls += 1
        completion(recentSampleResult)
    }

    func fetchUserProfile(completion: @escaping (UserProfile) -> Void) {
        completion(profileResult)
    }

    func stopObservingHeartRate() { stopObservingCalls += 1 }
}

// MARK: - Tests

@MainActor
final class ExerciseViewModelHRSourceTests: XCTestCase {

    // MARK: - Helpers

    private func makeVM(hk: SpyHealthKitService? = nil,
                        wc: SpyWatchConnectivityService? = nil,
                        pollInterval: TimeInterval = 0.05) -> ExerciseViewModel {
        ExerciseViewModel(audioService: SpyAudioService(),
                          healthKitService: hk ?? SpyHealthKitService(),
                          watchConnectivityService: wc ?? SpyWatchConnectivityService(),
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

    func test_watchStatus_noLiveSample_emptyRow() {
        let vm = makeVM()
        vm.standbyWatchBPM = nil
        XCTAssertEqual(vm.watchSourceStatus.message, "")
        XCTAssertFalse(vm.watchSourceStatus.isReady)
    }

    func test_watchStatus_liveSample() {
        let vm = makeVM()
        vm.standbyWatchBPM = 132.4
        XCTAssertTrue(vm.watchSourceStatus.message.contains("132 bpm"),
                      "Got: \(vm.watchSourceStatus.message)")
        XCTAssertTrue(vm.watchSourceStatus.isReady)
    }

    func test_watchStatus_bpmRoundsCorrectly() {
        let vm = makeVM()
        vm.standbyWatchBPM = 132.6
        XCTAssertTrue(vm.watchSourceStatus.message.contains("133 bpm"),
                      "Got: \(vm.watchSourceStatus.message)")
    }

    func test_watchStatus_zeroBPM_documentsBehavior() {
        let vm = makeVM()
        vm.standbyWatchBPM = 0
        XCTAssertTrue(vm.watchSourceStatus.isReady)
        XCTAssertTrue(vm.watchSourceStatus.message.contains("0 bpm"))
    }

    // =========================================================================
    // MARK: - shouldShowSourceInstruction
    // =========================================================================

    func test_instruction_visibleWhenNeitherReady() {
        let vm = makeVM()
        XCTAssertTrue(vm.shouldShowSourceInstruction)
    }

    func test_instruction_hiddenWhenBLEReady() {
        let vm = makeVM()
        vm.hrSource = .ble
        XCTAssertFalse(vm.shouldShowSourceInstruction)
    }

    func test_instruction_hiddenWhenWatchStreaming() {
        let vm = makeVM()
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

    func test_endExercise_transitionsToSummary() {
        let vm = makeVM()
        vm.startExercise()
        vm.endExercise()
        if case .summary = vm.appState { } else {
            XCTFail("endExercise should transition to .summary, not .standby. Got: \(vm.appState)")
        }
    }

    func test_dismissSummary_resumesStandbyPoll() {
        let hk = SpyHealthKitService()
        let vm = makeVM(hk: hk)
        vm.startExercise()
        vm.endExercise()
        let callsAfterEnd = hk.recentSampleCalls

        vm.dismissSummary()
        wait(for: hk.recentSampleCalls > callsAfterEnd, timeout: 2.5,
             "dismissSummary should restart the standby poll")
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
        // `since` is intentionally backdated by ~10s to absorb Watch sample clock skew.
        XCTAssertGreaterThanOrEqual(since.timeIntervalSince1970, before.timeIntervalSince1970 - 30)
        XCTAssertLessThanOrEqual(since.timeIntervalSince1970, after.timeIntervalSince1970 + 0.01)
    }

    func test_startExercise_startsObserverEvenWhenAuthDenied() {
        let hk = SpyHealthKitService()
        hk.authorizationResult = false
        let vm = makeVM(hk: hk)
        vm.startExercise()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertNotNil(hk.observingSince,
                        "Observer should always start — queries return no data if auth denied")
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

    func test_observerSince_isWithinReasonableWindow() {
        // Regression for the frozen-HR bug: the `since:` value must not be so old that
        // pre-exercise stale samples (e.g. 61 bpm from hours ago) can be returned.
        // A small backward window (~10s) is permitted to absorb clock skew between the
        // Apple Watch sample timestamps and the iPhone's exercise-start moment.
        let hk = SpyHealthKitService()
        let vm = makeVM(hk: hk)
        let pressStart = Date()
        vm.startExercise()
        wait(for: hk.observingSince != nil, timeout: 1.0)
        let delta = pressStart.timeIntervalSince1970 - hk.observingSince!.timeIntervalSince1970
        XCTAssertGreaterThanOrEqual(delta, -0.5,
                                    "`since:` must not be in the future relative to the start of the exercise")
        XCTAssertLessThanOrEqual(delta, 30,
                                 "`since:` must be within 30s of the start of the exercise to avoid frozen-HR regression")
    }
}
