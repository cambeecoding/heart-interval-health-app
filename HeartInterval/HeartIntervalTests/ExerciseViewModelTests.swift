import XCTest
@testable import HeartInterval

// MARK: - Spy

final class SpyAudioService: AudioServiceProtocol {
    var spoken: [String] = []
    func speak(_ text: String)   { spoken.append(text) }
    func startSilentLoop()       {}
    func stopSilentLoop()        {}
    func reactivateSession()     {}
}

// MARK: - Tests

@MainActor
final class ExerciseViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a ViewModel with a spy audio service, exercising state, and a known HR sample.
    private func makeExercisingVM(hr: Double = 140, spy: SpyAudioService) -> ExerciseViewModel {
        let vm = ExerciseViewModel(audioService: spy)
        vm.appState = .exercising
        vm.handleNewHRSample(hr, source: .none)
        return vm
    }

    // =========================================================================
    // MARK: - HR sample handling
    // =========================================================================

    func test_handleSample_updatescurrentHR() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.handleNewHRSample(145, source: .none)
        XCTAssertEqual(vm.currentHR, 145)
    }

    func test_handleSample_updatesTotalAvg() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.handleNewHRSample(100, source: .none)
        vm.handleNewHRSample(200, source: .none)
        XCTAssertEqual(vm.totalAvgHR, 150)
    }

    func test_handleSample_healthKit_deduplicatesOldDate() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        let t1 = Date()
        let t0 = t1.addingTimeInterval(-5)
        vm.handleNewHRSample(150, source: .healthKit, date: t1)
        vm.handleNewHRSample(999, source: .healthKit, date: t0) // older — must be ignored
        XCTAssertEqual(vm.currentHR, 150, "Older HealthKit sample should be ignored")
    }

    // =========================================================================
    // MARK: - 30s mode announcements
    // =========================================================================

    /// At the 30 s midpoint: only "Current X B.P.M." — no total average.
    func test_shortMode_30s_announcesCurrentOnly() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 145, spy: spy)
        vm.shortInterval = true
        spy.spoken.removeAll()

        vm.onHalfwayTick()

        XCTAssertEqual(spy.spoken.last, "Current 145 B.P.M.")
        XCTAssertFalse(spy.spoken.last?.contains("Total") ?? false,
                       "30 s tick must not include total average")
    }

    /// At the 60 s boundary in 30s mode: "Current X B.P.M. Total average X B.P.M."
    func test_shortMode_60s_announcesCurrentAndTotal() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 145, spy: spy)
        vm.shortInterval = true
        spy.spoken.removeAll()

        vm.onFullMinuteTick()

        let last = spy.spoken.last ?? ""
        XCTAssertTrue(last.contains("Current"),       "60 s tick must include current HR. Got: \(last)")
        XCTAssertTrue(last.contains("Total average"), "60 s tick must include total average. Got: \(last)")
        XCTAssertFalse(last.contains("Last minute"),  "No last-minute phrasing should appear. Got: \(last)")
    }

    /// In 30s mode the halfway tick must NOT mention total average.
    func test_shortMode_halfwayTick_noTotalAvg() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 145, spy: spy)
        vm.shortInterval = true
        spy.spoken.removeAll()

        vm.onHalfwayTick()

        XCTAssertFalse(spy.spoken.last?.contains("Total") ?? false,
                       "30 s halfway tick must never include total average")
    }

    // =========================================================================
    // MARK: - 60s mode announcements
    // =========================================================================

    /// At the 60 s boundary in 60s mode: "Current X B.P.M. Total average X B.P.M."
    func test_longMode_60s_announcesCurrentAndTotal() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 120, spy: spy)
        vm.shortInterval = false
        spy.spoken.removeAll()

        vm.onFullMinuteTick()

        let last = spy.spoken.last ?? ""
        XCTAssertTrue(last.contains("Current"),       "60 s mode must include current HR. Got: \(last)")
        XCTAssertTrue(last.contains("Total average"), "60 s mode must include total average. Got: \(last)")
        XCTAssertFalse(last.contains("Last minute"),  "No last-minute phrasing should appear. Got: \(last)")
    }

    /// In 60s mode the halfway tick is completely silent.
    func test_longMode_halfwayTick_isSilent() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 120, spy: spy)
        vm.shortInterval = false
        spy.spoken.removeAll()

        vm.onHalfwayTick()

        XCTAssertTrue(spy.spoken.isEmpty,
                      "In 60 s mode the 30 s halfway tick must not speak. Got: \(spy.spoken)")
    }

    // =========================================================================
    // MARK: - Pause announcement
    // =========================================================================

    /// Pause includes current HR and total average.
    func test_pause_announcesCurrentAndTotal() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 130, spy: spy)
        spy.spoken.removeAll()

        vm.announceMetrics(includeTotal: true)

        let last = spy.spoken.last ?? ""
        XCTAssertTrue(last.contains("Current"),       "Pause must include current HR. Got: \(last)")
        XCTAssertTrue(last.contains("Total average"), "Pause must include total average. Got: \(last)")
        XCTAssertFalse(last.contains("Last minute"),  "No last-minute phrasing on pause. Got: \(last)")
    }

    /// Mid-exercise announcements (non-pause) do not include total average.
    func test_midExerciseAnnouncement_omitsTotal_whenNotRequested() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 130, spy: spy)
        spy.spoken.removeAll()

        vm.announceMetrics(includeTotal: false)

        let last = spy.spoken.last ?? ""
        XCTAssertFalse(last.contains("Total average"),
                       "includeTotal: false must omit total average. Got: \(last)")
    }

    /// No announcement fires when there is no current HR data yet.
    func test_announceMetrics_silentWithNoData() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        // no HR sample delivered

        vm.announceMetrics(includeTotal: true)

        XCTAssertTrue(spy.spoken.isEmpty,
                      "No announcement should fire without HR data. Got: \(spy.spoken)")
    }

    // =========================================================================
    // MARK: - onFullMinuteTick resets secondsInWindow
    // =========================================================================

    func test_fullMinuteTick_resetsSecondsInWindow() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(spy: spy)
        vm.secondsInWindow = 60

        vm.onFullMinuteTick()

        XCTAssertEqual(vm.secondsInWindow, 0, "onFullMinuteTick must reset secondsInWindow")
    }

    // =========================================================================
    // MARK: - Zone breach alerts
    // =========================================================================

    func test_zoneAlert_aboveMax_firesOnce() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.maxHR = 160
        vm.appState = .exercising
        vm.handleNewHRSample(170, source: .none)
        vm.handleNewHRSample(172, source: .none) // already above — must not re-fire
        XCTAssertEqual(spy.spoken.filter { $0.contains("Maximum") }.count, 1,
                       "Above-max alert must fire exactly once per breach")
    }

    func test_zoneAlert_belowMin_firesOnce() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.minHR = 120
        vm.appState = .exercising
        vm.handleNewHRSample(110, source: .none)
        vm.handleNewHRSample(108, source: .none) // still below — must not re-fire
        XCTAssertEqual(spy.spoken.filter { $0.contains("Minimum") }.count, 1,
                       "Below-min alert must fire exactly once per breach")
    }

    /// Alert resets when HR returns in-range, then fires again on next breach.
    func test_zoneAlert_resetAndRefires() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.maxHR = 160
        vm.appState = .exercising
        vm.handleNewHRSample(170, source: .none)  // fires
        vm.handleNewHRSample(155, source: .none)  // back in range — resets flag
        vm.handleNewHRSample(165, source: .none)  // fires again
        XCTAssertEqual(spy.spoken.filter { $0.contains("Maximum") }.count, 2,
                       "Alert should fire again after HR normalises and re-breaches")
    }

    func test_zoneAlert_suppressedWhenPaused() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.maxHR = 160
        vm.appState = .paused
        vm.handleNewHRSample(170, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("Maximum") }.count, 0,
                       "Zone alerts must be suppressed while paused")
    }

    func test_zoneAlert_suppressedWhenStandby() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.maxHR = 160
        vm.appState = .standby
        vm.handleNewHRSample(170, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("Maximum") }.count, 0,
                       "Zone alerts must be suppressed in standby")
    }

    func test_zoneAlert_noFire_whenInRange() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.minHR = 120
        vm.maxHR = 160
        vm.appState = .exercising
        vm.handleNewHRSample(140, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.lowercased().contains("heart rate") }.count, 0,
                       "No zone alert when HR is within the target range")
    }

    // =========================================================================
    // MARK: - Default HR range values
    // =========================================================================

    func test_defaultMinHR() {
        // Clear any persisted value so defaults apply
        UserDefaults.standard.removeObject(forKey: "minHR")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertEqual(vm.minHR, 120)
    }

    func test_defaultMaxHR() {
        UserDefaults.standard.removeObject(forKey: "maxHR")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertEqual(vm.maxHR, 160)
    }
}
