import XCTest
@testable import BeatZone

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

    /// Returns a ViewModel in exercising state with a known HR sample injected.
    private func makeExercisingVM(hr: Double = 140, spy: SpyAudioService) -> ExerciseViewModel {
        let vm = ExerciseViewModel(audioService: spy)
        vm.appState = .exercising
        vm.handleNewHRSample(hr, source: .none)
        return vm
    }

    // =========================================================================
    // MARK: - HR sample handling
    // =========================================================================

    func test_handleSample_updatesCurrentHR() {
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
        vm.handleNewHRSample(999, source: .healthKit, date: t0)
        XCTAssertEqual(vm.currentHR, 150, "Older HealthKit sample should be ignored")
    }

    // =========================================================================
    // MARK: - Speak tick
    // =========================================================================

    func test_speakTick_announcesCurrentOnly() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 145, spy: spy)
        spy.spoken.removeAll()

        vm.onSpeakTick()

        XCTAssertEqual(spy.spoken.last, "Current 145 B.P.M.")
        XCTAssertFalse(spy.spoken.last?.contains("Total") ?? false,
                       "Speak tick must not include total average")
    }

    func test_speakTick_silentWhenNoHRData() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)

        vm.onSpeakTick()

        XCTAssertTrue(spy.spoken.isEmpty,
                      "Speak tick must be silent with no HR data. Got: \(spy.spoken)")
    }

    // =========================================================================
    // MARK: - Summary tick
    // =========================================================================

    func test_summaryTick_announcesCurrentAndTotal() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 145, spy: spy)
        spy.spoken.removeAll()

        vm.onSummaryTick()

        let last = spy.spoken.last ?? ""
        XCTAssertTrue(last.contains("Current"),       "Summary tick must include current HR. Got: \(last)")
        XCTAssertTrue(last.contains("Total average"), "Summary tick must include total average. Got: \(last)")
    }

    func test_summaryTick_silentWhenNoHRData() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)

        vm.onSummaryTick()

        XCTAssertTrue(spy.spoken.isEmpty,
                      "Summary tick must be silent with no HR data. Got: \(spy.spoken)")
    }

    // =========================================================================
    // MARK: - Pause announcement
    // =========================================================================

    func test_pause_announcesCurrentAndTotal() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 130, spy: spy)
        spy.spoken.removeAll()

        vm.announceMetrics(includeTotal: true)

        let last = spy.spoken.last ?? ""
        XCTAssertTrue(last.contains("Current"),       "Pause must include current HR. Got: \(last)")
        XCTAssertTrue(last.contains("Total average"), "Pause must include total average. Got: \(last)")
    }

    func test_announceMetrics_omitsTotal_whenNotRequested() {
        let spy = SpyAudioService()
        let vm  = makeExercisingVM(hr: 130, spy: spy)
        spy.spoken.removeAll()

        vm.announceMetrics(includeTotal: false)

        let last = spy.spoken.last ?? ""
        XCTAssertFalse(last.contains("Total average"),
                       "includeTotal: false must omit total average. Got: \(last)")
    }

    func test_announceMetrics_silentWithNoData() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)

        vm.announceMetrics(includeTotal: true)

        XCTAssertTrue(spy.spoken.isEmpty,
                      "No announcement should fire without HR data. Got: \(spy.spoken)")
    }

    // =========================================================================
    // MARK: - announcementInterval computed property
    // =========================================================================

    func test_announcementInterval_returnsSpeakWhenSet() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.speakInterval   = 30
        vm.summaryInterval = 300
        XCTAssertEqual(vm.announcementInterval, 30)
    }

    func test_announcementInterval_returnsSummaryWhenSpeakOff() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.speakInterval   = 0
        vm.summaryInterval = 180
        XCTAssertEqual(vm.announcementInterval, 180)
    }

    func test_announcementInterval_fallsBackTo60WhenBothOff() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.speakInterval   = 0
        vm.summaryInterval = 0
        XCTAssertEqual(vm.announcementInterval, 60)
    }

    // =========================================================================
    // MARK: - Default settings
    // =========================================================================

    func test_defaultSpeakInterval() {
        UserDefaults.standard.removeObject(forKey: "speakInterval")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertEqual(vm.speakInterval, 60)
    }

    func test_defaultSummaryInterval() {
        UserDefaults.standard.removeObject(forKey: "summaryInterval")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertEqual(vm.summaryInterval, 300)
    }

    func test_defaultMinHR() {
        UserDefaults.standard.removeObject(forKey: "minHR")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertEqual(vm.minHR, 120)
    }

    func test_defaultMaxHR() {
        UserDefaults.standard.removeObject(forKey: "maxHR")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertEqual(vm.maxHR, 160)
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
        vm.handleNewHRSample(172, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("Maximum") }.count, 1,
                       "Above-max alert must fire exactly once per breach")
    }

    func test_zoneAlert_belowMin_firesOnce() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.minHR = 120
        vm.appState = .exercising
        vm.handleNewHRSample(110, source: .none)
        vm.handleNewHRSample(108, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("Minimum") }.count, 1,
                       "Below-min alert must fire exactly once per breach")
    }

    func test_zoneAlert_resetAndRefires() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.maxHR = 160
        vm.appState = .exercising
        vm.handleNewHRSample(170, source: .none)
        vm.handleNewHRSample(155, source: .none)
        vm.handleNewHRSample(165, source: .none)
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
}
