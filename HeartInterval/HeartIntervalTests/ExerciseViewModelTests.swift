import XCTest
@testable import BeatZone

// MARK: - Spy

@MainActor
final class SpyAudioService: AudioServiceProtocol {
    var spoken: [String] = []
    var tickCount = 0
    var goCount = 0
    func speak(_ text: String)   { spoken.append(text) }
    func speak(_ text: String, mood: SpeechMood) { spoken.append(text) }
    func playTick()              { tickCount += 1 }
    func playGo()                { goCount += 1 }
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
        vm.appState = .exercising
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

    func test_defaultMinMaxHR_usesAerobicZone() {
        UserDefaults.standard.removeObject(forKey: "heartRateZones")
        UserDefaults.standard.removeObject(forKey: "selectedZone")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        // Default selected zone = 2 (Aerobic), default zones Z3 = 125-138
        XCTAssertEqual(vm.selectedZone, 2)
        XCTAssertEqual(vm.minHR, HeartRateZones.default[2].minBPM)
        XCTAssertEqual(vm.maxHR, HeartRateZones.default[2].maxBPM)
    }

    // =========================================================================
    // MARK: - Zone adjacency
    // =========================================================================

    func test_setMin_adjustsAdjacentZoneMax() {
        var zones = HeartRateZones.calculate(age: 52, restingHR: 60)
        let oldZ2Max = zones[1].maxBPM
        // Raise Z3 min by 3
        zones.setMin(oldZ2Max + 3, forZone: 2)
        XCTAssertEqual(zones[2].minBPM, oldZ2Max + 3)
        XCTAssertEqual(zones[1].maxBPM, oldZ2Max + 3, "Z2 max must follow Z3 min")
    }

    func test_setMax_adjustsAdjacentZoneMin() {
        var zones = HeartRateZones.calculate(age: 52, restingHR: 60)
        let oldZ3Max = zones[2].maxBPM
        // Lower Z3 max by 3
        zones.setMax(oldZ3Max - 3, forZone: 2)
        XCTAssertEqual(zones[2].maxBPM, oldZ3Max - 3)
        XCTAssertEqual(zones[3].minBPM, oldZ3Max - 3, "Z4 min must follow Z3 max")
    }

    func test_setMin_firstZone_noAdjacentBelow() {
        var zones = HeartRateZones.calculate(age: 52, restingHR: 60)
        zones.setMin(100, forZone: 0)
        XCTAssertEqual(zones[0].minBPM, 100)
    }

    func test_setMax_lastZone_noAdjacentAbove() {
        var zones = HeartRateZones.calculate(age: 52, restingHR: 60)
        zones.setMax(175, forZone: 4)
        XCTAssertEqual(zones[4].maxBPM, 175)
    }

    func test_setMin_clampsToNotExceedMax() {
        var zones = HeartRateZones.default
        let max = zones[2].maxBPM
        zones.setMin(max + 10, forZone: 2)
        XCTAssertEqual(zones[2].minBPM, max - 1)
    }

    // =========================================================================
    // MARK: - Zone breach alerts
    // =========================================================================

    /// Helper: set the selected zone's boundaries for testing.
    private func setActiveZone(_ vm: ExerciseViewModel, min: Int, max: Int) {
        vm.trainingMode = .zone
        var zones = vm.heartRateZones
        zones[vm.selectedZone] = HRZone(minBPM: min, maxBPM: max)
        vm.heartRateZones = zones
    }

    func test_zoneAlert_aboveMax_firesOnce() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        setActiveZone(vm, min: 120, max: 160)
        vm.appState = .exercising
        vm.handleNewHRSample(170, source: .none)
        vm.handleNewHRSample(172, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("exceeded") }.count, 1,
                       "Above-max alert must fire exactly once per breach")
    }

    func test_zoneAlert_belowMin_firesOnce() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        setActiveZone(vm, min: 120, max: 160)
        vm.appState = .exercising
        vm.handleNewHRSample(110, source: .none)
        vm.handleNewHRSample(108, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("zone minimum") }.count, 1,
                       "Below-min alert must fire exactly once per breach")
    }

    func test_zoneAlert_resetAndRefires() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        setActiveZone(vm, min: 120, max: 160)
        vm.appState = .exercising
        vm.handleNewHRSample(170, source: .none)
        vm.handleNewHRSample(155, source: .none)
        vm.handleNewHRSample(165, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("exceeded") }.count, 2,
                       "Alert should fire again after HR normalises and re-breaches")
        XCTAssertEqual(spy.spoken.filter { $0.contains("Back in zone") }.count, 1,
                       "Re-entry announcement should fire when HR returns to zone")
    }

    func test_zoneAlert_suppressedWhenPaused() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        setActiveZone(vm, min: 120, max: 160)
        vm.appState = .paused
        vm.handleNewHRSample(170, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("exceeded") }.count, 0,
                       "Zone alerts must be suppressed while paused")
    }

    func test_zoneAlert_suppressedWhenStandby() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        setActiveZone(vm, min: 120, max: 160)
        vm.appState = .standby
        vm.handleNewHRSample(170, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.contains("exceeded") }.count, 0,
                       "Zone alerts must be suppressed in standby")
    }

    func test_zoneAlert_noFire_whenInRange() {
        let spy = SpyAudioService()
        let vm  = ExerciseViewModel(audioService: spy)
        setActiveZone(vm, min: 120, max: 160)
        vm.appState = .exercising
        vm.handleNewHRSample(140, source: .none)
        XCTAssertEqual(spy.spoken.filter { $0.lowercased().contains("heart rate") }.count, 0,
                       "No zone alert when HR is within the target range")
    }

    // =========================================================================
    // MARK: - User profile & auto zones
    // =========================================================================

    // =========================================================================
    // MARK: - HeartRateZones model
    // =========================================================================

    func test_karvonen_age52_resting60() {
        // maxHR = 220-52 = 168, reserve = 168-60 = 108
        let zones = HeartRateZones.calculate(age: 52, restingHR: 60)
        XCTAssertEqual(zones.zones.count, 5)
        // Z1: 60 + 54 = 114, 60 + 65 = 125
        XCTAssertEqual(zones[0].minBPM, 114)
        XCTAssertEqual(zones[0].maxBPM, 125)
        // Z2: 60 + 65 = 125, 60 + 76 = 136
        XCTAssertEqual(zones[1].minBPM, 125)
        XCTAssertEqual(zones[1].maxBPM, 136)
        // Z3: 60 + 76 = 136, 60 + 86 = 146
        XCTAssertEqual(zones[2].minBPM, 136)
        XCTAssertEqual(zones[2].maxBPM, 146)
        // Z4: 60 + 86 = 146, 60 + 97 = 157
        XCTAssertEqual(zones[3].minBPM, 146)
        XCTAssertEqual(zones[3].maxBPM, 157)
        // Z5: 60 + 97 = 157, 60 + 108 = 168
        XCTAssertEqual(zones[4].minBPM, 157)
        XCTAssertEqual(zones[4].maxBPM, 168)
    }

    func test_karvonen_age30_resting55() {
        // maxHR = 190, reserve = 135
        let zones = HeartRateZones.calculate(age: 30, restingHR: 55)
        // Z3 (aerobic): 55 + 95 = 150, 55 + 108 = 163 (rounding may vary)
        XCTAssertEqual(zones[2].minBPM, 150) // 55 + round(135*0.7) = 55+94.5→95
        XCTAssertEqual(zones[2].maxBPM, 163) // 55 + round(135*0.8) = 55+108
    }

    func test_zones_contiguous() {
        let zones = HeartRateZones.calculate(age: 40, restingHR: 65)
        for i in 0..<4 {
            XCTAssertEqual(zones[i].maxBPM, zones[i + 1].minBPM,
                           "Zone \(i+1) max should equal zone \(i+2) min")
        }
    }

    // =========================================================================
    // MARK: - ViewModel zone integration
    // =========================================================================

    func test_autoCalculateZones_karvonen() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.userAge = 52
        vm.restingHR = 60
        vm.autoCalculateZones()
        // Selected zone defaults to 2 (Aerobic/Z3) → index 2
        // Z3 for age 52, resting 60: 136-146
        XCTAssertEqual(vm.minHR, 136)
        XCTAssertEqual(vm.maxHR, 146)
        XCTAssertTrue(vm.zonesAutoSet)
    }

    func test_autoCalculateZones_noAge_returnsFalse() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.userAge = nil
        XCTAssertFalse(vm.autoCalculateZones())
    }

    func test_autoCalculateZones_noRestingHR_returnsFalse() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.userAge = 40
        vm.restingHR = nil
        XCTAssertFalse(vm.autoCalculateZones())
    }

    func test_selectedZone_changesMinMaxHR() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.userAge = 52
        vm.restingHR = 60
        vm.autoCalculateZones()

        vm.selectedZone = 0 // Recovery
        XCTAssertEqual(vm.minHR, 114)
        XCTAssertEqual(vm.maxHR, 125)

        vm.selectedZone = 3 // Threshold
        XCTAssertEqual(vm.minHR, 146)
        XCTAssertEqual(vm.maxHR, 157)
    }

    func test_defaultSelectedZone_isAerobic() {
        UserDefaults.standard.removeObject(forKey: "selectedZone")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertEqual(vm.selectedZone, 2)
    }

    func test_defaultRestingHR_isNil() {
        UserDefaults.standard.removeObject(forKey: "restingHR")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertNil(vm.restingHR)
    }

    func test_defaultUserAge_isNil() {
        UserDefaults.standard.removeObject(forKey: "userAge")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertNil(vm.userAge)
    }

    func test_defaultUserSex_isNil() {
        UserDefaults.standard.removeObject(forKey: "userSex")
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        XCTAssertNil(vm.userSex)
    }

    func test_userSex_roundTrips() {
        let vm = ExerciseViewModel(audioService: SpyAudioService())
        vm.userSex = .female
        XCTAssertEqual(vm.userSex, .female)
        vm.userSex = .male
        XCTAssertEqual(vm.userSex, .male)
        vm.userSex = nil
        XCTAssertNil(vm.userSex)
    }

    func test_fetchProfile_setsAgeAndRestingHR_andAutoCalculatesZones() {
        let hk = SpyHealthKitService()
        hk.profileResult = UserProfile(age: 52, sex: .male, restingHR: 60)
        let vm = ExerciseViewModel(audioService: SpyAudioService(),
                                   healthKitService: hk)
        UserDefaults.standard.removeObject(forKey: "userAge")
        UserDefaults.standard.removeObject(forKey: "userSex")
        UserDefaults.standard.removeObject(forKey: "restingHR")
        UserDefaults.standard.set(false, forKey: "zonesAutoSet")
        vm.userAge = nil
        vm.userSex = nil
        vm.restingHR = nil

        vm.fetchProfileFromHealthKit()

        XCTAssertEqual(vm.userAge, 52)
        XCTAssertEqual(vm.userSex, .male)
        XCTAssertEqual(vm.restingHR, 60)
        // Default selected zone = 2 (Aerobic), Z3 for 52yo/60rhr = 136-146
        XCTAssertEqual(vm.minHR, 136)
        XCTAssertEqual(vm.maxHR, 146)
    }

    func test_fetchProfile_doesNotOverrideExistingValues() {
        let hk = SpyHealthKitService()
        hk.profileResult = UserProfile(age: 35, sex: .male, restingHR: 55)
        let vm = ExerciseViewModel(audioService: SpyAudioService(),
                                   healthKitService: hk)
        vm.userAge = 40
        vm.userSex = .female
        vm.restingHR = 65

        vm.fetchProfileFromHealthKit()

        XCTAssertEqual(vm.userAge, 40, "Should not override existing age")
        XCTAssertEqual(vm.userSex, .female, "Should not override existing sex")
        XCTAssertEqual(vm.restingHR, 65, "Should not override existing resting HR")
    }
}
