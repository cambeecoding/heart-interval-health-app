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

    // MARK: 30 s mode

    /// At the 30s midpoint, only "Current X B.P.M." is announced — no last-minute average.
    func test_shortMode_30s_announcesCurrentOnly() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.shortInterval = true
        vm.handleNewHRSample(145, source: .none)

        vm.onHalfwayTick()

        XCTAssertEqual(spy.spoken.last, "Current 145 B.P.M.")
        XCTAssertFalse(spy.spoken.last?.contains("Last minute") ?? false,
                       "30 s tick must not include last-minute average")
    }

    /// At the 60s boundary in 30s mode, the full announcement fires:
    /// "Last minute X B.P.M. Current X B.P.M." — no total average.
    func test_shortMode_60s_announcesLastMinuteAndCurrent() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.shortInterval = true
        vm.handleNewHRSample(145, source: .none)

        vm.onFullMinuteTick()

        let last = spy.spoken.last ?? ""
        XCTAssertTrue(last.contains("Last minute"),
                      "60 s tick must include last-minute average. Got: \(last)")
        XCTAssertTrue(last.contains("Current"),
                      "60 s tick must include current HR. Got: \(last)")
        XCTAssertFalse(last.contains("Total"),
                       "60 s mid-exercise tick must not include total average")
    }

    /// At the 30s midpoint, the window samples are NOT reset — we still accumulate for the minute.
    func test_shortMode_30s_doesNotResetWindow() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.shortInterval = true
        vm.handleNewHRSample(140, source: .none)
        vm.handleNewHRSample(150, source: .none)

        vm.onHalfwayTick()

        // After the 60 s tick the average should cover both samples
        vm.onFullMinuteTick()
        let msg = spy.spoken.last ?? ""
        // average of 140 and 150 = 145
        XCTAssertTrue(msg.contains("Last minute 145"),
                      "Minute average should cover both samples collected before the 30 s tick. Got: \(msg)")
    }

    // MARK: 60 s mode

    /// At the 60s boundary in 60s mode, the full announcement fires.
    func test_longMode_60s_announcesLastMinuteAndCurrent() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.shortInterval = false
        vm.handleNewHRSample(120, source: .none)

        vm.onFullMinuteTick()

        let last = spy.spoken.last ?? ""
        XCTAssertTrue(last.contains("Last minute"),
                      "60 s mode must announce last-minute average. Got: \(last)")
        XCTAssertTrue(last.contains("Current"),
                      "60 s mode must announce current HR. Got: \(last)")
        XCTAssertFalse(last.contains("Total"),
                       "Mid-exercise 60 s tick must not include total average")
    }

    /// In 60s mode the halfway tick is a no-op.
    func test_longMode_halfwayTick_isSilent() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.shortInterval = false
        vm.handleNewHRSample(120, source: .none)

        vm.onHalfwayTick()

        XCTAssertTrue(spy.spoken.isEmpty,
                      "In 60s mode the 30s midpoint must not speak. Got: \(spy.spoken)")
    }

    // MARK: Pause

    /// Pausing mid-exercise announces last-minute avg, current, AND total average.
    func test_pause_includesTotal() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.handleNewHRSample(130, source: .none)
        vm.onFullMinuteTick()          // sets lastMinuteAvgHR
        vm.handleNewHRSample(140, source: .none)  // updates totalAvgHR

        vm.announceMetrics(includeTotal: true)

        let last = spy.spoken.last ?? ""
        XCTAssertTrue(last.contains("Last minute"),  "Pause must include last-minute avg. Got: \(last)")
        XCTAssertTrue(last.contains("Current"),      "Pause must include current HR. Got: \(last)")
        XCTAssertTrue(last.contains("Total average"),"Pause must include total average. Got: \(last)")
    }

    /// Without pausing (includeTotal: false) the total average is omitted.
    func test_announceMetrics_withoutTotal_omitsTotal() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        vm.handleNewHRSample(130, source: .none)
        vm.onFullMinuteTick()
        vm.handleNewHRSample(140, source: .none)

        vm.announceMetrics(includeTotal: false)

        let last = spy.spoken.last ?? ""
        XCTAssertFalse(last.contains("Total average"),
                       "Non-pause announcement must omit total average. Got: \(last)")
    }
}
