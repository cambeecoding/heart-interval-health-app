import XCTest
@testable import BeatZone

@MainActor
final class IntervalTimerEngineTests: XCTestCase {

    private var engine: IntervalTimerEngine!
    private var phases: [IntervalPhase]!
    private var cues: [String]!
    private var completed: Bool!

    override func setUp() {
        super.setUp()
        engine = IntervalTimerEngine()
        phases = []
        cues = []
        completed = false

        engine.onPhaseChange = { [unowned self] phase in phases.append(phase) }
        engine.onAudioCue = { [unowned self] cue in cues.append(cue) }
        engine.onSessionComplete = { [unowned self] in completed = true }
    }

    private func tick(_ n: Int) { for _ in 0..<n { engine.tick() } }

    // MARK: - Phase transitions

    func test_noWarmup_startsAtWork1() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 2, warmupDuration: 0))
        XCTAssertEqual(engine.currentPhase, .work(round: 1))
        XCTAssertEqual(engine.currentRound, 1)
        XCTAssertEqual(engine.countdown, 5)
    }

    func test_withWarmup_startsAtWarmup() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 2, warmupDuration: 10))
        XCTAssertEqual(engine.currentPhase, .warmup)
        XCTAssertEqual(engine.countdown, 10)
    }

    func test_warmupTransitionsToWork1() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 3))
        tick(3)
        XCTAssertEqual(engine.currentPhase, .work(round: 1))
    }

    func test_workTransitionsToRest() {
        engine.start(config: IntervalConfig(workDuration: 3, restDuration: 5, rounds: 2, warmupDuration: 0))
        tick(3)
        XCTAssertEqual(engine.currentPhase, .rest(round: 1))
    }

    func test_restTransitionsToNextWork() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 2, rounds: 3, warmupDuration: 0))
        tick(4) // work(1)=2 + rest(1)=2
        XCTAssertEqual(engine.currentPhase, .work(round: 2))
        XCTAssertEqual(engine.currentRound, 2)
    }

    func test_lastRoundEndsWithoutRest() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 2, rounds: 2, warmupDuration: 0))
        tick(6) // work(1)=2 + rest(1)=2 + work(2)=2
        XCTAssertEqual(engine.currentPhase, .finished)
        XCTAssertTrue(completed)
    }

    func test_singleRound_workThenFinished() {
        engine.start(config: IntervalConfig(workDuration: 3, restDuration: 5, rounds: 1, warmupDuration: 0))
        tick(3)
        XCTAssertEqual(engine.currentPhase, .finished)
        XCTAssertTrue(completed)
    }

    func test_fullSession_3rounds() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 1, rounds: 3, warmupDuration: 0))
        // w1(2) r1(1) w2(2) r2(1) w3(2) = 8 ticks
        tick(8)
        XCTAssertEqual(engine.currentPhase, .finished)
        XCTAssertEqual(engine.currentRound, 3)
    }

    func test_fullSessionWithWarmup() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 1, rounds: 2, warmupDuration: 3))
        // warm(3) w1(2) r1(1) w2(2) = 8 ticks
        tick(8)
        XCTAssertEqual(engine.currentPhase, .finished)
    }

    // MARK: - Audio cues: warmup

    func test_warmupStartCue_minutes() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 180))
        XCTAssertTrue(cues.contains("Warm up. 3 minutes."))
    }

    func test_warmupStartCue_seconds() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 45))
        XCTAssertTrue(cues.contains("Warm up. 45 seconds."))
    }

    func test_warmupMidpointCue() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 60))
        // midpoint at countdown==30, so tick from 60 down to 30 = 30 ticks
        tick(30)
        XCTAssertTrue(cues.contains("30 seconds remaining."))
    }

    func test_warmup30sCue_distinctFromMidpoint() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 90))
        // midpoint at 45, 30s cue at 30
        tick(60)
        XCTAssertTrue(cues.contains("45 seconds remaining."))
        XCTAssertTrue(cues.contains("30 seconds."))
    }

    func test_warmupNoMidpointIfShort() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 30))
        tick(30)
        let midpointCues = cues.filter { $0.contains("remaining") }
        XCTAssertTrue(midpointCues.isEmpty)
    }

    // MARK: - Audio cues: work

    func test_workRoundCue() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 3, warmupDuration: 0))
        XCTAssertTrue(cues.contains("Round 1. Work."))
    }

    func test_lastRoundCue() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 1, rounds: 2, warmupDuration: 0))
        tick(3) // work(1)=2 + rest(1)=1 → work(2) starts
        XCTAssertTrue(cues.contains("Last round. Work."))
    }

    func test_singleRound_isLastRound() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 0))
        XCTAssertTrue(cues.contains("Last round. Work."))
    }

    func test_10sWarningOnLongWork() {
        engine.start(config: IntervalConfig(workDuration: 20, restDuration: 5, rounds: 1, warmupDuration: 0))
        tick(10) // 20 → 10
        XCTAssertTrue(cues.contains("10 seconds."))
    }

    func test_no10sWarningOnShortWork() {
        engine.start(config: IntervalConfig(workDuration: 15, restDuration: 5, rounds: 1, warmupDuration: 0))
        tick(5) // 15 → 10
        XCTAssertFalse(cues.contains("10 seconds."))
    }

    func test_halfwayCue() {
        engine.start(config: IntervalConfig(workDuration: 30, restDuration: 5, rounds: 1, warmupDuration: 0))
        tick(15) // 30 → 15
        XCTAssertTrue(cues.contains("Halfway."))
    }

    func test_noHalfwayCueWhenConflictsWithTenSecondWarning() {
        // work=20: halfway at 10, but 10s warning also at 10 → halfway suppressed
        engine.start(config: IntervalConfig(workDuration: 20, restDuration: 5, rounds: 1, warmupDuration: 0))
        tick(10)
        XCTAssertTrue(cues.contains("10 seconds."))
        XCTAssertFalse(cues.contains("Halfway."))
    }

    func test_321Countdown_duringWork() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 0))
        tick(4) // 5→4→3→2→1
        XCTAssertTrue(cues.contains("3"))
        XCTAssertTrue(cues.contains("2"))
        XCTAssertTrue(cues.contains("1"))
    }

    func test_321Countdown_duringRest() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 5, rounds: 2, warmupDuration: 0))
        tick(9) // work(5: cues 3,2,1) + rest(4 of 5: cues 3,2)
        XCTAssertTrue(cues.filter { $0 == "3" }.count >= 2)
        XCTAssertTrue(cues.filter { $0 == "2" }.count >= 2)
    }

    // MARK: - Audio cues: rest

    func test_restCueWithHR() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 5, rounds: 2, warmupDuration: 0))
        engine.currentHR = 165
        tick(2) // work ends, rest starts
        XCTAssertTrue(cues.contains("Rest. Heart rate 165."))
    }

    func test_restCueWithoutHR() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 5, rounds: 2, warmupDuration: 0))
        engine.currentHR = nil
        tick(2)
        XCTAssertTrue(cues.contains("Rest."))
    }

    // MARK: - Audio cues: session complete

    func test_sessionCompleteCueWithSamples() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 1, rounds: 1, warmupDuration: 0))
        engine.recordSample(HRSample(bpm: 150, date: Date()))
        engine.recordSample(HRSample(bpm: 170, date: Date()))
        tick(2)
        let completeCue = cues.first { $0.contains("Session complete") }
        XCTAssertNotNil(completeCue)
        XCTAssertTrue(completeCue!.contains("Average heart rate 160"))
        XCTAssertTrue(completeCue!.contains("Peak 170"))
    }

    func test_sessionCompleteCueWithoutSamples() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 1, rounds: 1, warmupDuration: 0))
        tick(2)
        let completeCue = cues.first { $0.contains("Session complete") }
        XCTAssertNotNil(completeCue)
        XCTAssertEqual(completeCue, "Session complete.")
    }

    // MARK: - Skip

    func test_skipAdvancesToNextPhase() {
        engine.start(config: IntervalConfig(workDuration: 30, restDuration: 10, rounds: 2, warmupDuration: 0))
        engine.skip()
        XCTAssertEqual(engine.currentPhase, .rest(round: 1))
        engine.skip()
        XCTAssertEqual(engine.currentPhase, .work(round: 2))
    }

    func test_skipLastRoundEndsSession() {
        engine.start(config: IntervalConfig(workDuration: 30, restDuration: 10, rounds: 1, warmupDuration: 0))
        engine.skip()
        XCTAssertEqual(engine.currentPhase, .finished)
        XCTAssertTrue(completed)
    }

    func test_skipWarmup() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 120))
        engine.skip()
        XCTAssertEqual(engine.currentPhase, .work(round: 1))
    }

    // MARK: - Pause / Resume

    func test_pauseFreezesCountdown() {
        engine.start(config: IntervalConfig(workDuration: 30, restDuration: 10, rounds: 1, warmupDuration: 0))
        tick(5) // 30→25
        engine.pause()
        let frozen = engine.countdown
        tick(5)
        XCTAssertEqual(engine.countdown, frozen)
    }

    func test_resumeContinues() {
        engine.start(config: IntervalConfig(workDuration: 30, restDuration: 10, rounds: 1, warmupDuration: 0))
        tick(5) // 30→25
        engine.pause()
        tick(3) // no effect
        engine.resume()
        tick(1) // 25→24
        XCTAssertEqual(engine.countdown, 24)
        XCTAssertEqual(engine.currentPhase, .work(round: 1))
    }

    // MARK: - Stop

    func test_stopEndsImmediately() {
        engine.start(config: IntervalConfig(workDuration: 30, restDuration: 10, rounds: 5, warmupDuration: 0))
        engine.stop()
        XCTAssertEqual(engine.currentPhase, .finished)
    }

    func test_tickAfterStopIsNoop() {
        engine.start(config: IntervalConfig(workDuration: 5, restDuration: 3, rounds: 1, warmupDuration: 0))
        engine.stop()
        let phaseBefore = engine.currentPhase
        tick(10)
        XCTAssertEqual(engine.currentPhase, phaseBefore)
    }

    // MARK: - Phase records

    func test_phaseRecordsTracked() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 1, rounds: 2, warmupDuration: 0))
        tick(6)
        XCTAssertEqual(engine.phaseRecords.count, 3) // work1, rest1, work2
        XCTAssertTrue(engine.phaseRecords[0].isWork)
        XCTAssertFalse(engine.phaseRecords[1].isWork)
        XCTAssertTrue(engine.phaseRecords[2].isWork)
    }

    func test_phaseRecordsIncludeWarmup() {
        engine.start(config: IntervalConfig(workDuration: 2, restDuration: 1, rounds: 1, warmupDuration: 3))
        tick(5)
        XCTAssertEqual(engine.phaseRecords.count, 2) // warmup, work1
        XCTAssertFalse(engine.phaseRecords[0].isWork)
        XCTAssertTrue(engine.phaseRecords[1].isWork)
    }

    // MARK: - Round samples

    func test_roundSamplesCollected() {
        engine.start(config: IntervalConfig(workDuration: 3, restDuration: 1, rounds: 2, warmupDuration: 0))
        engine.recordSample(HRSample(bpm: 150, date: Date()))
        tick(4) // work(1)=3 + rest(1)=1
        engine.recordSample(HRSample(bpm: 170, date: Date()))
        XCTAssertEqual(engine.roundSamples.count, 2)
        XCTAssertEqual(engine.roundSamples[0].count, 1)
        XCTAssertEqual(engine.roundSamples[1].count, 1)
    }

    // MARK: - Config: totalDuration

    func test_totalDuration() {
        let config = IntervalConfig(workDuration: 50, restDuration: 20, rounds: 9, warmupDuration: 180)
        // 180 + 9*50 + 8*20 = 180 + 450 + 160 = 790
        XCTAssertEqual(config.totalDuration, 790)
    }

    func test_totalDuration_singleRound() {
        let config = IntervalConfig(workDuration: 30, restDuration: 10, rounds: 1, warmupDuration: 0)
        XCTAssertEqual(config.totalDuration, 30)
    }
}
