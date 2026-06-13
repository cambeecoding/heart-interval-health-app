import Foundation
import UIKit

enum AppState: Equatable {
    case launching  // initial splash while app and BLE initialise
    case standby
    case starting
    case exercising
    case paused
    case summary(SessionSummary)
}

enum HRSource {
    case none
    case ble
    case watch
    case healthKit
}

@MainActor
final class ExerciseViewModel: ObservableObject {

    // MARK: - Published state
    @Published var appState: AppState        = .launching
    @Published var currentHR: Int?           = nil
    @Published var totalAvgHR: Int?          = nil
    @Published var elapsedSeconds: Int       = 0
    @Published var secondsSinceLastHR: Int?  = nil
    @Published var hrSource: HRSource        = .none
    @Published var bleStatus: String         = ""
    @Published var standbyWatchBPM: Double?  = nil
    @Published var hrSourceTimedOut: Bool    = false

    // MARK: - Interval mode state
    @Published var intervalPhase: IntervalPhase?     = nil
    @Published var intervalCountdown: Int             = 0
    @Published var startCountdownRemaining: Int?      = nil
    private var intervalEngine: IntervalTimerEngine?

    // MARK: - UserDefaults-backed workout type
    var selectedActivityType: WorkoutActivityType {
        get {
            let raw = UserDefaults.standard.string(forKey: "workoutActivityType") ?? "other"
            return WorkoutActivityType(rawValue: raw) ?? .other
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "workoutActivityType")
            objectWillChange.send()
        }
    }

    // MARK: - Heart rate zones
    var heartRateZones: HeartRateZones {
        get {
            guard let data = UserDefaults.standard.data(forKey: "heartRateZones"),
                  let zones = try? JSONDecoder().decode(HeartRateZones.self, from: data)
            else { return .default }
            return zones
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "heartRateZones")
            }
            objectWillChange.send()
        }
    }

    /// Selected zone index (0-3 selectable on standby; 0=Recovery, 1=FatBurn, 2=Aerobic, 3=Threshold)
    var selectedZone: Int {
        get { UserDefaults.standard.object(forKey: "selectedZone") as? Int ?? 2 }
        set { UserDefaults.standard.set(newValue, forKey: "selectedZone"); objectWillChange.send() }
    }

    var minHR: Int { heartRateZones[selectedZone].minBPM }
    var maxHR: Int { heartRateZones[selectedZone].maxBPM }

    // MARK: - UserDefaults-backed announcement settings
    /// Seconds between current BPM announcements. 0 = off.
    /// Valid values: 0, 30, 60, 120, 180.
    var speakInterval: Int {
        get { UserDefaults.standard.object(forKey: "speakInterval") as? Int ?? 60 }
        set { UserDefaults.standard.set(newValue, forKey: "speakInterval"); objectWillChange.send() }
    }
    /// Seconds between summary (current + average) announcements. 0 = off.
    /// Valid values: 0, 120, 180, 300, 600.
    var summaryInterval: Int {
        get { UserDefaults.standard.object(forKey: "summaryInterval") as? Int ?? 300 }
        set { UserDefaults.standard.set(newValue, forKey: "summaryInterval"); objectWillChange.send() }
    }

    /// Drives the progress ring — uses the speak interval if active, otherwise summary, otherwise 60s fallback.
    var announcementInterval: Int {
        if speakInterval > 0 { return speakInterval }
        if summaryInterval > 0 { return summaryInterval }
        return 60
    }

    // MARK: - UserDefaults-backed user profile
    var userAge: Int? {
        get { UserDefaults.standard.object(forKey: "userAge") as? Int }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: "userAge") }
            else { UserDefaults.standard.removeObject(forKey: "userAge") }
            objectWillChange.send()
        }
    }

    var userSex: BiologicalSex? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "userSex") else { return nil }
            return BiologicalSex(rawValue: raw)
        }
        set {
            if let v = newValue { UserDefaults.standard.set(v.rawValue, forKey: "userSex") }
            else { UserDefaults.standard.removeObject(forKey: "userSex") }
            objectWillChange.send()
        }
    }

    var restingHR: Int? {
        get { UserDefaults.standard.object(forKey: "restingHR") as? Int }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: "restingHR") }
            else { UserDefaults.standard.removeObject(forKey: "restingHR") }
            objectWillChange.send()
        }
    }

    /// Whether zones were auto-set (vs manually adjusted by user).
    var zonesAutoSet: Bool {
        get { UserDefaults.standard.bool(forKey: "zonesAutoSet") }
        set { UserDefaults.standard.set(newValue, forKey: "zonesAutoSet"); objectWillChange.send() }
    }

    /// Calculates and applies HR zones using Karvonen method. Returns true if zones were updated.
    @discardableResult
    func autoCalculateZones() -> Bool {
        guard let age = userAge, age > 0, let rhr = restingHR, rhr > 0 else { return false }
        heartRateZones = HeartRateZones.calculate(age: age, restingHR: rhr)
        zonesAutoSet = true
        return true
    }

    func fetchProfileFromHealthKit() {
        healthKitService.fetchUserProfile { [weak self] profile in
            guard let self else { return }
            var updated = false
            if let age = profile.age, self.userAge == nil {
                self.userAge = age
                updated = true
            }
            if let sex = profile.sex, self.userSex == nil {
                self.userSex = sex
                updated = true
            }
            if let rhr = profile.restingHR, self.restingHR == nil {
                self.restingHR = rhr
                updated = true
            }
            if updated && !self.hasManualZones {
                self.autoCalculateZones()
            }
        }
    }

    private var hasManualZones: Bool {
        UserDefaults.standard.data(forKey: "heartRateZones") != nil && !zonesAutoSet
    }

    // MARK: - UserDefaults-backed training mode
    var trainingMode: TrainingMode {
        get {
            let raw = UserDefaults.standard.string(forKey: "trainingMode") ?? "zone"
            return TrainingMode(rawValue: raw) ?? .zone
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "trainingMode")
            objectWillChange.send()
        }
    }

    var intervalConfig: IntervalConfig {
        get {
            guard let data = UserDefaults.standard.data(forKey: "intervalConfig"),
                  let config = try? JSONDecoder().decode(IntervalConfig.self, from: data)
            else { return IntervalConfig() }
            return config
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "intervalConfig")
            }
            objectWillChange.send()
        }
    }

    var startCountdown: Int {
        get { UserDefaults.standard.object(forKey: "startCountdown") as? Int ?? 3 }
        set { UserDefaults.standard.set(newValue, forKey: "startCountdown"); objectWillChange.send() }
    }

    // MARK: - Services
    private let bleService       = BLEHeartRateService()
    let healthKitService: HealthKitServicing
    let watchConnectivityService: WatchConnectivityServicing
    let audioService: AudioServiceProtocol
    private let workoutManager   = WorkoutManager()
    private let standbyPollInterval: TimeInterval

    // MARK: - Timers
    private var clockTimer:   Timer?
    private var speakTimer:   Timer?
    private var summaryTimer: Timer?
    private var standbyPollTimer: Timer?
    private var noHRTimeoutTimer: Timer?
    private var watchTimeoutTimer: Timer?
    /// Seconds to wait before warning the user that no HR has been received.
    private let noHRTimeoutSeconds: TimeInterval = 20
    /// Seconds without Watch HR before falling back to HealthKit.
    private let watchTimeoutSeconds: TimeInterval = 6
    #if targetEnvironment(simulator)
    private var mockHRTimer: Timer?
    private var mockHRIndex = 0
    private let mockHRValues: [Double] = [142, 145, 148, 144, 147, 143, 146, 149, 141, 145]
    #endif

    // MARK: - Summary state
    @Published var isSaving     = false
    @Published var summaryError: String? = nil

    // MARK: - Samples
    private var allSamples:        [HRSample] = []
    private var lastSampleDate:    Date?
    private var exerciseStartDate: Date       = Date()

    // MARK: - Zone breach tracking
    private var isAboveMax = false
    private var isBelowMin = false

    // MARK: - Init

    init(audioService: AudioServiceProtocol? = nil,
         healthKitService: HealthKitServicing? = nil,
         watchConnectivityService: WatchConnectivityServicing? = nil,
         standbyPollInterval: TimeInterval = 5) {
        self.audioService = audioService ?? AudioService()
        self.healthKitService = healthKitService ?? HealthKitService()
        self.watchConnectivityService = watchConnectivityService ?? WatchConnectivityService()
        self.standbyPollInterval = standbyPollInterval
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        bleService.onHR = { [weak self] bpm in
            Task { @MainActor [weak self] in self?.handleNewHRSample(bpm, source: .ble) }
        }
        bleService.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .scanning:     self.bleStatus = "Scanning for HR monitor…"
                case .available:    self.bleStatus = "HR monitor available"
                case .connecting:   self.bleStatus = "Connecting…"
                case .connected:    self.bleStatus = "HR monitor connected"
                case .disconnected:
                    self.bleStatus = "HR monitor disconnected — reconnecting…"
                    if self.hrSource == .ble { self.hrSource = .none }
                case .idle:         self.bleStatus = ""
                }
            }
        }

        self.watchConnectivityService.onHeartRate = { [weak self] bpm, date in
            Task { @MainActor [weak self] in
                guard let self, self.hrSource != .ble else { return }
                if self.appState == .standby {
                    self.standbyWatchBPM = bpm
                } else {
                    self.handleNewHRSample(bpm, source: .watch, date: date)
                }
            }
        }
        self.watchConnectivityService.onStartExercise = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.appState == .standby else { return }
                self.startExercise()
            }
        }
        self.watchConnectivityService.onStartIntervalExercise = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.appState == .standby else { return }
                self.trainingMode = .intervals
                self.startExercise()
            }
        }
        self.watchConnectivityService.activate()

        // Start BLE scanning immediately so we can show HR source status on standby
        bleService.startScanning()

        // Give BLE + HealthKit a moment to initialise before showing standby
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if appState == .launching {
                appState = .standby
                startStandbyPoll()
            }
        }
    }

    @objc private func appDidBecomeActive() {
        if appState == .exercising || appState == .paused {
            audioService.startSilentLoop()
        }
    }

    // MARK: - Computed HR source status

    /// BLE-specific status row for standby screen. Empty message = row hidden.
    var bleSourceStatus: (message: String, isReady: Bool) {
        if hrSource == .ble || bleStatus == "HR monitor connected" {
            return ("Bluetooth HR monitor connected", true)
        }
        if bleStatus == "HR monitor available" {
            return ("Bluetooth HR monitor available", true)
        }
        if bleStatus == "Connecting…" {
            return ("Connecting to HR monitor…", false)
        }
        if bleStatus == "Scanning for HR monitor…" {
            return ("Scanning for Bluetooth HR monitor…", false)
        }
        return ("", false)
    }

    /// Apple Watch / HealthKit status row for standby screen. Empty message = row hidden.
    /// Purely data-driven: if we see recent HR from HealthKit, the Watch is streaming.
    var watchSourceStatus: (message: String, isReady: Bool) {
        if let bpm = standbyWatchBPM {
            return ("Apple Watch streaming — \(Int(bpm.rounded())) bpm", true)
        }
        return ("", false)
    }

    /// True when no HR source is actively streaming — show the universal instruction.
    var shouldShowSourceInstruction: Bool {
        !bleSourceStatus.isReady && !watchSourceStatus.isReady
    }

    // MARK: - Actions

    func startExercise() {
        exerciseStartDate  = Date()
        allSamples         = []
        currentHR          = nil
        totalAvgHR         = nil
        elapsedSeconds     = 0
        secondsSinceLastHR = nil
        lastSampleDate     = nil
        hrSource           = .none
        hrSourceTimedOut   = false

        stopStandbyPoll()
        appState = .starting
        workoutManager.beginExercise()
        audioService.startSilentLoop()

        bleService.start()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.requestHealthKitAndBegin()
        }
    }

    private func requestHealthKitAndBegin() {
        let since = Date().addingTimeInterval(-10)
        healthKitService.requestAuthorization { [weak self] granted in
            guard let self else { return }
            self.beginObservingHR(since: since)
            if self.startCountdown > 0 {
                self.runStartCountdown()
            } else {
                self.beginExercisePhase()
            }
        }
    }

    private func beginObservingHR(since: Date) {
        healthKitService.startObservingHeartRate(since: since) { [weak self] bpm, date in
            Task { @MainActor [weak self] in
                guard let self, self.hrSource != .ble && self.hrSource != .watch else { return }
                self.handleNewHRSample(bpm, source: .healthKit, date: date)
            }
        }
    }

    private func runStartCountdown() {
        startCountdownRemaining = startCountdown
        audioService.playTick()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                guard let remaining = self.startCountdownRemaining, remaining > 0 else {
                    timer.invalidate()
                    return
                }
                let next = remaining - 1
                if next <= 0 {
                    timer.invalidate()
                    self.startCountdownRemaining = nil
                    self.audioService.playGo()
                    self.beginExercisePhase()
                } else {
                    self.startCountdownRemaining = next
                    self.audioService.playTick()
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    private var watchPhaseSeq = 0

    private func beginExercisePhase() {
        appState = .exercising
        startTimers()
        startNoHRTimeout()

        if trainingMode == .intervals {
            watchPhaseSeq = 0
            watchConnectivityService.sendIntervalConfig(intervalConfig)

            let engine = IntervalTimerEngine()
            engine.onPhaseChange = { [weak self] phase in
                guard let self else { return }
                self.intervalPhase = phase
                if phase != .finished {
                    self.audioService.playGo()
                }
                self.watchPhaseSeq += 1
                self.watchConnectivityService.sendIntervalPhaseUpdate(
                    phase: self.phaseString(phase),
                    round: engine.currentRound,
                    countdown: engine.countdown,
                    seq: self.watchPhaseSeq,
                    totalRounds: engine.totalRounds
                )
            }
            engine.onCountdownTick = { [weak self] countdown in
                self?.intervalCountdown = countdown
            }
            engine.onAudioCue = { [weak self] cue, mood in
                self?.audioService.speak(cue, mood: mood)
            }
            engine.onBeep = { [weak self] in
                self?.audioService.playTick()
            }
            engine.onSessionComplete = { [weak self] in
                self?.endExercise()
            }
            self.intervalEngine = engine
            engine.start(config: intervalConfig)
        } else {
            audioService.speak("Starting exercise.")
        }
    }

    private func phaseString(_ phase: IntervalPhase) -> String {
        switch phase {
        case .warmup: return "warmup"
        case .work: return "work"
        case .rest: return "rest"
        case .finished: return "finished"
        }
    }

    private func startNoHRTimeout() {
        noHRTimeoutTimer?.invalidate()
        let t = Timer(timeInterval: noHRTimeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.currentHR == nil && self.hrSource == .none && self.appState == .exercising {
                    #if DEBUG
                    print("[BeatZone HK] No HR sample received after \(self.noHRTimeoutSeconds)s — surfacing warning")
                    #endif
                    self.hrSourceTimedOut = true
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        noHRTimeoutTimer = t
    }

    func pauseExercise() {
        stopTimers()
        intervalEngine?.pause()
        appState = .paused
        if trainingMode == .zone {
            announceMetrics(includeTotal: true)
        }
    }

    func continueExercise() {
        appState = .exercising
        intervalEngine?.resume()
        startTimers()
    }

    func skipInterval() {
        intervalEngine?.skip()
    }

    func endExercise() {
        stopTimers()
        bleService.returnToScanning()
        healthKitService.stopObservingHeartRate()
        workoutManager.endExercise()
        audioService.stopSilentLoop()

        var intervalData: IntervalSessionData?
        if let engine = intervalEngine {
            engine.stop()
            intervalData = buildIntervalSessionData(from: engine)
            intervalEngine = nil
        }

        let summary = SessionSummary(
            startDate: exerciseStartDate,
            endDate: Date(),
            durationSeconds: elapsedSeconds,
            samples: allSamples,
            minHR: minHR,
            maxHR: maxHR,
            activityType: selectedActivityType,
            intervalData: intervalData
        )
        appState = .summary(summary)
    }

    private func buildIntervalSessionData(from engine: IntervalTimerEngine) -> IntervalSessionData {
        var rounds: [IntervalRound] = []
        for (i, samples) in engine.roundSamples.enumerated() {
            let bpms = samples.map(\.bpm)
            let peak = bpms.max() ?? 0
            let avg = bpms.isEmpty ? 0 : bpms.reduce(0, +) / Double(bpms.count)

            var recovery: Double?
            if i < engine.restSamples.count {
                let restBpms = engine.restSamples[i].map(\.bpm)
                if let restMin = restBpms.min(), peak > 0 {
                    recovery = peak - restMin
                }
            }

            rounds.append(IntervalRound(
                roundNumber: i + 1,
                peakHR: peak,
                avgHR: avg,
                recoveryDrop: recovery
            ))
        }

        return IntervalSessionData(
            config: intervalConfig,
            rounds: rounds,
            phases: engine.phaseRecords
        )
    }

    func dismissSummary() {
        currentHR              = nil
        totalAvgHR             = nil
        elapsedSeconds         = 0
        secondsSinceLastHR     = nil
        hrSource               = .none
        hrSourceTimedOut       = false
        isAboveMax             = false
        isBelowMin             = false
        isSaving               = false
        summaryError           = nil
        allSamples             = []
        intervalPhase          = nil
        intervalCountdown      = 0
        intervalEngine         = nil
        startCountdownRemaining = nil
        appState               = .standby
        startStandbyPoll()
    }

    func saveAndDismiss(summary: SessionSummary) {
        isSaving     = true
        summaryError = nil
        healthKitService.saveWorkout(summary) { [weak self] result in
            guard let self else { return }
            self.isSaving = false
            switch result {
            case .success:
                self.dismissSummary()
            case .failure(let error):
                self.summaryError = error.localizedDescription
            }
        }
    }

    // MARK: - Standby liveness poll

    private func startStandbyPoll() {
        standbyPollTimer?.invalidate()
        let t = Timer(timeInterval: standbyPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollStandbyHR() }
        }
        RunLoop.main.add(t, forMode: .common)
        standbyPollTimer = t
        // Immediate first check so the UI doesn't wait 5s on entry.
        pollStandbyHR()
    }

    /// Internal for testability — drives one poll cycle.
    func pollStandbyHR() {
        healthKitService.fetchRecentSample(within: 60) { [weak self] bpm in
            Task { @MainActor [weak self] in self?.standbyWatchBPM = bpm }
        }
    }

    private func stopStandbyPoll() {
        standbyPollTimer?.invalidate()
        standbyPollTimer = nil
        standbyWatchBPM = nil
    }

    // MARK: - Private helpers

    func handleNewHRSample(_ bpm: Double, source: HRSource, date: Date = Date()) {
        if source == .healthKit || source == .watch {
            if let last = lastSampleDate, date <= last { return }
            lastSampleDate = date
        }
        hrSource           = source
        secondsSinceLastHR = 0
        hrSourceTimedOut   = false
        noHRTimeoutTimer?.invalidate()
        noHRTimeoutTimer   = nil
        if source == .watch {
            resetWatchTimeout()
        }
        currentHR = Int(bpm.rounded())

        if appState == .exercising {
            let sample = HRSample(bpm: bpm, date: date)
            allSamples.append(sample)
            totalAvgHR = average(of: allSamples.map(\.bpm))
            intervalEngine?.recordSample(sample)
        }
        checkZoneBreaches()
    }

    private func resetWatchTimeout() {
        watchTimeoutTimer?.invalidate()
        let t = Timer(timeInterval: watchTimeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.hrSource == .watch else { return }
                self.hrSource = .none
            }
        }
        RunLoop.main.add(t, forMode: .common)
        watchTimeoutTimer = t
    }

    private func checkZoneBreaches() {
        guard appState == .exercising, trainingMode == .zone, let hr = currentHR else { return }
        if hr > maxHR {
            if !isAboveMax {
                isAboveMax = true
                audioService.speak("Zone heartrate exceeded")
            }
        } else {
            if isAboveMax {
                isAboveMax = false
                audioService.speak("Back in zone. Heart rate \(hr).")
            }
        }
        if hr < minHR {
            if !isBelowMin {
                isBelowMin = true
                audioService.speak("Heartrate lower than zone minimum")
            }
        } else {
            if isBelowMin {
                isBelowMin = false
                audioService.speak("Back in zone. Heart rate \(hr).")
            }
        }
    }

    private func startTimers() {
        stopTimers()

        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedSeconds += 1
                if self.secondsSinceLastHR != nil { self.secondsSinceLastHR! += 1 }
                if let engine = self.intervalEngine {
                    engine.currentHR = self.currentHR
                    engine.tick()
                }
            }
        }
        RunLoop.main.add(clock, forMode: .common)
        clockTimer = clock

        if trainingMode == .zone {
            startSpeakTimer()
            startSummaryTimer()
        }

        #if targetEnvironment(simulator)
        let mock = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let bpm = self.mockHRValues[self.mockHRIndex % self.mockHRValues.count]
                self.mockHRIndex += 1
                self.handleNewHRSample(bpm, source: .ble)
            }
        }
        RunLoop.main.add(mock, forMode: .common)
        mockHRTimer = mock
        #endif
    }

    private func startSpeakTimer() {
        guard speakInterval > 0 else { return }
        let t = Timer(timeInterval: TimeInterval(speakInterval), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onSpeakTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        speakTimer = t
    }

    private func startSummaryTimer() {
        guard summaryInterval > 0 else { return }
        let t = Timer(timeInterval: TimeInterval(summaryInterval), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onSummaryTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        summaryTimer = t
    }

    private func stopTimers() {
        clockTimer?.invalidate();       clockTimer = nil
        speakTimer?.invalidate();       speakTimer = nil
        summaryTimer?.invalidate();     summaryTimer = nil
        noHRTimeoutTimer?.invalidate(); noHRTimeoutTimer = nil
        watchTimeoutTimer?.invalidate(); watchTimeoutTimer = nil
        #if targetEnvironment(simulator)
        mockHRTimer?.invalidate();     mockHRTimer = nil
        #endif
    }

    /// Fires on the speak interval — announces current BPM only.
    func onSpeakTick() {
        if let current = currentHR {
            audioService.speak("Current \(current) B.P.M.")
        }
    }

    /// Fires on the summary interval — announces current BPM + session average,
    /// then resets the speak timer to avoid a back-to-back announcement.
    func onSummaryTick() {
        announceMetrics(includeTotal: true)
        if speakInterval > 0 {
            speakTimer?.invalidate()
            startSpeakTimer()
        }
    }

    /// Announces current HR, and optionally the total session average.
    func announceMetrics(includeTotal: Bool) {
        var parts: [String] = []
        if let current = currentHR {
            parts.append("Current \(current) B.P.M.")
        }
        if includeTotal, let total = totalAvgHR {
            parts.append("Total average \(total) B.P.M.")
        }
        guard !parts.isEmpty else { return }
        audioService.speak(parts.joined(separator: ". "))
    }

    private func average(of values: [Double]) -> Int? {
        guard !values.isEmpty else { return nil }
        return Int((values.reduce(0, +) / Double(values.count)).rounded())
    }
}
