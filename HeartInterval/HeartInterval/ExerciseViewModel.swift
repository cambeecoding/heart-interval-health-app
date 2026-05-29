import Foundation
import UIKit

enum AppState {
    case launching  // initial splash while app and BLE initialise
    case standby
    case starting
    case exercising
    case paused
}

enum HRSource {
    case none
    case ble
    case healthKit
}

@MainActor
final class ExerciseViewModel: ObservableObject {

    // MARK: - Published state
    @Published var appState: AppState        = .launching
    @Published var currentHR: Int?           = nil
    @Published var totalAvgHR: Int?          = nil
    @Published var elapsedSeconds: Int       = 0
    @Published var secondsInWindow: Int      = 0
    @Published var secondsSinceLastHR: Int?  = nil
    @Published var hrSource: HRSource        = .none
    @Published var bleStatus: String         = ""
    /// When true: announce current HR every 30 s + total avg every 60 s.
    /// When false: announce current HR + total avg every 60 s.
    @Published var shortInterval: Bool       = true

    // MARK: - UserDefaults-backed HR range (triggers objectWillChange for SwiftUI)
    var minHR: Int {
        get { UserDefaults.standard.object(forKey: "minHR") as? Int ?? 120 }
        set { UserDefaults.standard.set(newValue, forKey: "minHR"); objectWillChange.send() }
    }
    var maxHR: Int {
        get { UserDefaults.standard.object(forKey: "maxHR") as? Int ?? 160 }
        set { UserDefaults.standard.set(newValue, forKey: "maxHR"); objectWillChange.send() }
    }

    /// The interval driving the ring/counter — always 30s in short mode so ring reflects next announcement.
    var announcementInterval: Int { shortInterval ? 30 : 60 }

    // MARK: - Services
    private let bleService       = BLEHeartRateService()
    let healthKitService         = HealthKitService()
    let audioService: AudioServiceProtocol
    private let workoutManager   = WorkoutManager()

    // MARK: - Timers
    private var announcementTimer: Timer?
    private var clockTimer: Timer?

    // MARK: - Samples
    private var allSamples:    [Double] = []
    private var lastSampleDate: Date?

    // MARK: - Zone breach tracking
    private var isAboveMax = false
    private var isBelowMin = false

    // MARK: - Init

    init(audioService: AudioServiceProtocol = AudioService()) {
        self.audioService = audioService
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
                case .connecting:   self.bleStatus = "Connecting…"
                case .connected:    self.bleStatus = "HR monitor connected"
                case .disconnected:
                    self.bleStatus = "HR monitor disconnected — reconnecting…"
                    if self.hrSource == .ble { self.hrSource = .none }
                case .idle:         self.bleStatus = ""
                }
            }
        }

        // Start BLE scanning immediately so we can show HR source status on standby
        bleService.startScanning()

        // Give BLE + HealthKit a moment to initialise before showing standby
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if appState == .launching { appState = .standby }
        }
    }

    @objc private func appDidBecomeActive() {
        if appState == .exercising || appState == .paused {
            audioService.startSilentLoop()
        }
    }

    // MARK: - Computed HR source status

    var hrSourceStatus: (message: String, isReady: Bool) {
        // BLE connected takes priority
        if hrSource == .ble || bleStatus == "HR monitor connected" {
            return ("Heart rate monitor connected", true)
        }
        // BLE scanning/connecting
        if !bleStatus.isEmpty && bleStatus != "HR monitor disconnected — reconnecting…" {
            // Check if HealthKit is authorized as fallback
            if healthKitService.isAuthorized() {
                return ("Using Apple Watch via Health", true)
            }
            return (bleStatus, false)
        }
        // BLE disconnected
        if healthKitService.isAuthorized() {
            return ("Using Apple Watch via Health", true)
        }
        return ("No heart rate source detected", false)
    }

    // MARK: - Actions

    func startExercise() {
        allSamples         = []
        currentHR          = nil
        totalAvgHR         = nil
        elapsedSeconds     = 0
        secondsInWindow    = 0
        secondsSinceLastHR = nil
        lastSampleDate     = nil
        hrSource           = .none

        appState = .starting
        workoutManager.beginExercise()
        audioService.startSilentLoop()

        // BLE is already scanning from init; just mark as exercising so
        // disconnect handler auto-reconnects instead of returning to scan
        bleService.isExercising = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self.requestHealthKitAndBegin()
        }
    }

    private func requestHealthKitAndBegin() {
        healthKitService.requestAuthorization { [weak self] granted in
            guard let self else { return }
            self.appState = .exercising
            self.audioService.speak("Starting exercise.")
            self.startTimers()
            if granted {
                self.healthKitService.startObservingHeartRate { [weak self] bpm, date in
                    Task { @MainActor [weak self] in
                        guard let self, self.hrSource != .ble else { return }
                        self.handleNewHRSample(bpm, source: .healthKit, date: date)
                    }
                }
            }
        }
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
        // Return to scanning so standby shows live BLE status
        bleService.returnToScanning()
        healthKitService.stopObservingHeartRate()
        workoutManager.endExercise()
        audioService.stopSilentLoop()
        appState           = .standby
        currentHR          = nil
        totalAvgHR         = nil
        elapsedSeconds     = 0
        secondsInWindow    = 0
        secondsSinceLastHR = nil
        hrSource           = .none
        isAboveMax         = false
        isBelowMin         = false
    }

    // MARK: - Private helpers

    func handleNewHRSample(_ bpm: Double, source: HRSource, date: Date = Date()) {
        if source == .healthKit {
            if let last = lastSampleDate, date <= last { return }
            lastSampleDate = date
        }
        hrSource           = source
        secondsSinceLastHR = 0
        allSamples.append(bpm)
        currentHR  = Int(bpm.rounded())
        totalAvgHR = average(of: allSamples)
        checkZoneBreaches()
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

        // Clock: fires every second; also handles the 30s halfway announcement
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedSeconds  += 1
                self.secondsInWindow += 1
                if self.secondsSinceLastHR != nil { self.secondsSinceLastHR! += 1 }
                // In 30s mode, announce current HR at the midpoint of each 60s window
                if self.shortInterval && self.secondsInWindow == 30 {
                    self.onHalfwayTick()
                }
            }
        }
        RunLoop.main.add(clock, forMode: .common)
        clockTimer = clock

        // Main 60 s announcement timer
        let remainingFull = max(1, 60 - secondsInWindow)
        let firstFull = Timer(timeInterval: TimeInterval(remainingFull), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onFullMinuteTick()
                self?.startRepeatFullTimer()
            }
        }
        RunLoop.main.add(firstFull, forMode: .common)
        announcementTimer = firstFull

    }

    private func startRepeatFullTimer() {
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.onFullMinuteTick() }
        }
        RunLoop.main.add(t, forMode: .common)
        announcementTimer = t
    }

    private func stopTimers() {
        clockTimer?.invalidate();        clockTimer = nil
        announcementTimer?.invalidate(); announcementTimer = nil
    }

    /// Fires at the 60 s boundary — announces current HR + total avg, resets window counter.
    func onFullMinuteTick() {
        secondsInWindow = 0
        announceMetrics(includeTotal: true)
    }

    /// Fires at the 30 s midpoint in short mode — current HR only, no window reset.
    func onHalfwayTick() {
        guard shortInterval else { return }
        if let current = currentHR {
            audioService.speak("Current \(current) B.P.M.")
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
