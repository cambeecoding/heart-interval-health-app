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
    /// Latest HR sample seen from HealthKit while on the standby screen.
    /// nil = no recent sample (Watch/device not currently streaming).
    @Published var standbyWatchBPM: Double?  = nil
    /// True if no HR sample has arrived within the timeout after starting exercise.
    /// Surfaces a warning + Settings deep-link in ExerciseView.
    @Published var hrSourceTimedOut: Bool    = false

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

    // MARK: - UserDefaults-backed HR range
    var minHR: Int {
        get { UserDefaults.standard.object(forKey: "minHR") as? Int ?? 120 }
        set { UserDefaults.standard.set(newValue, forKey: "minHR"); objectWillChange.send() }
    }
    var maxHR: Int {
        get { UserDefaults.standard.object(forKey: "maxHR") as? Int ?? 160 }
        set { UserDefaults.standard.set(newValue, forKey: "maxHR"); objectWillChange.send() }
    }

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
        // Relaxed by 10s: defends against clock skew / sync lag where the Watch
        // timestamps a sample fractions of a second before the auth callback fires.
        // Still rules out genuinely stale samples (the original "frozen 61 bpm" bug
        // involved samples from hours ago).
        let since = Date().addingTimeInterval(-10)
        #if DEBUG
        print("[BeatZone HK] requestAuthorization called, since=\(since)")
        #endif
        healthKitService.requestAuthorization { [weak self] granted in
            guard let self else { return }
            #if DEBUG
            print("[BeatZone HK] requestAuthorization completed, granted=\(granted)")
            #endif
            self.appState = .exercising
            self.audioService.speak("Starting exercise.")
            self.startTimers()
            self.startNoHRTimeout()
            self.healthKitService.startObservingHeartRate(since: since) { [weak self] bpm, date in
                Task { @MainActor [weak self] in
                    guard let self, self.hrSource != .ble && self.hrSource != .watch else { return }
                    self.handleNewHRSample(bpm, source: .healthKit, date: date)
                }
            }
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
        appState = .paused
        announceMetrics(includeTotal: true)
    }

    func continueExercise() {
        appState = .exercising
        startTimers()
    }

    func endExercise() {
        stopTimers()
        bleService.returnToScanning()
        healthKitService.stopObservingHeartRate()
        workoutManager.endExercise()
        audioService.stopSilentLoop()

        let summary = SessionSummary(
            startDate: exerciseStartDate,
            endDate: Date(),
            durationSeconds: elapsedSeconds,
            samples: allSamples,
            minHR: minHR,
            maxHR: maxHR,
            activityType: selectedActivityType
        )
        appState = .summary(summary)
    }

    func dismissSummary() {
        currentHR          = nil
        totalAvgHR         = nil
        elapsedSeconds     = 0
        secondsSinceLastHR = nil
        hrSource           = .none
        hrSourceTimedOut   = false
        isAboveMax         = false
        isBelowMin         = false
        isSaving           = false
        summaryError       = nil
        allSamples         = []
        appState           = .standby
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
        allSamples.append(HRSample(bpm: bpm, date: date))
        currentHR  = Int(bpm.rounded())
        totalAvgHR = average(of: allSamples.map(\.bpm))
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
        guard appState == .exercising, let hr = currentHR else { return }
        if hr > maxHR {
            if !isAboveMax {
                isAboveMax = true
                audioService.speak("Maximum heart rate reached")
            }
        } else {
            isAboveMax = false
        }
        if hr < minHR {
            if !isBelowMin {
                isBelowMin = true
                audioService.speak("Minimum heart rate reached")
            }
        } else {
            isBelowMin = false
        }
    }

    private func startTimers() {
        stopTimers()

        // Clock: fires every second to drive elapsed time and secondsSinceLastHR
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedSeconds += 1
                if self.secondsSinceLastHR != nil { self.secondsSinceLastHR! += 1 }
            }
        }
        RunLoop.main.add(clock, forMode: .common)
        clockTimer = clock

        startSpeakTimer()
        startSummaryTimer()

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
