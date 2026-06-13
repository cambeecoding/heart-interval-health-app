import Foundation

@MainActor
protocol IntervalTimerEngineProtocol: AnyObject {
    func start(config: IntervalConfig)
    func tick()
    func pause()
    func resume()
    func skip()
    func stop()

    var currentPhase: IntervalPhase? { get }
    var countdown: Int { get }
    var currentRound: Int { get }
    var totalRounds: Int { get }
    var currentHR: Int? { get set }

    var onPhaseChange: ((IntervalPhase) -> Void)? { get set }
    var onCountdownTick: ((Int) -> Void)? { get set }
    var onAudioCue: ((String, SpeechMood) -> Void)?  { get set }
    var onBeep: (() -> Void)? { get set }
    var onSessionComplete: (() -> Void)? { get set }

    var phaseRecords: [IntervalPhaseRecord] { get }
    var roundSamples: [[HRSample]] { get }
    var restSamples: [[HRSample]] { get }
}

@MainActor
final class IntervalTimerEngine: IntervalTimerEngineProtocol {

    private(set) var currentPhase: IntervalPhase?
    private(set) var countdown: Int = 0
    private(set) var currentRound: Int = 0
    private(set) var totalRounds: Int = 0
    var currentHR: Int?

    var onPhaseChange: ((IntervalPhase) -> Void)?
    var onCountdownTick: ((Int) -> Void)?
    var onAudioCue: ((String, SpeechMood) -> Void)?
    var onBeep: (() -> Void)?
    var onSessionComplete: (() -> Void)?

    private var config = IntervalConfig()
    private var isPaused = false

    private(set) var phaseRecords: [IntervalPhaseRecord] = []
    private(set) var roundSamples: [[HRSample]] = []
    private(set) var restSamples: [[HRSample]] = []
    private var currentPhaseStartDate = Date()

    func start(config: IntervalConfig) {
        self.config = config
        totalRounds = config.rounds
        phaseRecords = []
        roundSamples = []
        restSamples = []
        isPaused = false

        if config.warmupDuration > 0 {
            enterPhase(.warmup, duration: config.warmupDuration)
        } else {
            startRound(1)
        }
    }

    func tick() {
        guard currentPhase != nil, currentPhase != .finished, !isPaused else { return }

        countdown -= 1
        emitTickCues()
        onCountdownTick?(countdown)

        if countdown <= 0 {
            advancePhase()
        }
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        isPaused = false
    }

    func skip() {
        guard currentPhase != nil, currentPhase != .finished else { return }
        advancePhase()
    }

    func stop() {
        closeCurrentPhaseRecord()
        currentPhase = .finished
    }

    func recordSample(_ sample: HRSample) {
        switch currentPhase {
        case .work:
            guard !roundSamples.isEmpty else { return }
            roundSamples[roundSamples.count - 1].append(sample)
        case .rest:
            guard !restSamples.isEmpty else { return }
            restSamples[restSamples.count - 1].append(sample)
        default:
            break
        }
    }

    // MARK: - Phase management

    private func enterPhase(_ phase: IntervalPhase, duration: Int) {
        closeCurrentPhaseRecord()
        currentPhase = phase
        countdown = duration
        currentPhaseStartDate = Date()

        if case .work(let round) = phase {
            currentRound = round
            if round > roundSamples.count {
                roundSamples.append([])
            }
        }
        if case .rest = phase {
            restSamples.append([])
        }

        onPhaseChange?(phase)
        emitPhaseStartCue(phase)
    }

    private func advancePhase() {
        guard let phase = currentPhase else { return }

        switch phase {
        case .warmup:
            startRound(1)
        case .work(let round):
            if round >= totalRounds {
                closeCurrentPhaseRecord()
                currentPhase = .finished
                countdown = 0
                emitSessionCompleteCue()
                onPhaseChange?(.finished)
                onSessionComplete?()
            } else {
                enterPhase(.rest(round: round), duration: config.restDuration)
            }
        case .rest(let round):
            startRound(round + 1)
        case .finished:
            break
        }
    }

    private func startRound(_ round: Int) {
        enterPhase(.work(round: round), duration: config.workDuration)
    }

    private func durationForCurrentPhase() -> Int {
        guard let phase = currentPhase else { return 0 }
        switch phase {
        case .warmup: return config.warmupDuration
        case .work: return config.workDuration
        case .rest: return config.restDuration
        case .finished: return 0
        }
    }

    // MARK: - Phase records

    private func closeCurrentPhaseRecord() {
        guard let phase = currentPhase, phase != .finished else { return }
        let isWork: Bool
        switch phase {
        case .work: isWork = true
        default: isWork = false
        }
        phaseRecords.append(IntervalPhaseRecord(
            isWork: isWork,
            startDate: currentPhaseStartDate,
            endDate: Date()
        ))
    }

    // MARK: - Audio cues

    private func moodForPhase(_ phase: IntervalPhase?) -> SpeechMood {
        switch phase {
        case .work: return .energetic
        case .rest: return .calm
        default: return .neutral
        }
    }

    private func spokenDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins == 0 { return "\(secs) seconds" }
        if secs == 0 { return "\(mins) \(mins == 1 ? "minute" : "minutes")" }
        return "\(mins) \(mins == 1 ? "minute" : "minutes") \(secs) seconds"
    }

    private func emitPhaseStartCue(_ phase: IntervalPhase) {
        let mood = moodForPhase(phase)
        switch phase {
        case .warmup:
            onAudioCue?("Warm up. \(spokenDuration(config.warmupDuration)).", .neutral)
        case .work(let round):
            if round == totalRounds {
                onAudioCue?("Last round. Work!", mood)
            } else {
                onAudioCue?("Round \(round). Work!", mood)
            }
        case .rest:
            if let hr = currentHR {
                onAudioCue?("Rest. Heart rate \(hr).", mood)
            } else {
                onAudioCue?("Rest.", mood)
            }
        case .finished:
            break
        }
    }

    private func emitTickCues() {
        guard let phase = currentPhase else { return }
        let duration = durationForCurrentPhase()
        let mood = moodForPhase(phase)

        // Every-minute markers for phases longer than 2 minutes
        if duration > 120 && countdown > 10 && countdown % 60 == 0 {
            onAudioCue?("\(spokenDuration(countdown)) remaining.", mood)
        }

        // Halfway marker (only if it doesn't collide with a minute marker)
        if phase.isWork || phase == .warmup {
            if duration >= 10 {
                let half = duration / 2
                let isMinuteBoundary = duration > 120 && half % 60 == 0
                if countdown == half && half > 10 && !isMinuteBoundary {
                    onAudioCue?("Halfway.", mood)
                }
            }
        }

        // 10 seconds warning for all active phases
        if duration > 15 && countdown == 10 {
            onAudioCue?("10 seconds.", mood)
        }

        // 3-2-1 beep countdown for all phases
        if countdown >= 1 && countdown <= 3 {
            onBeep?()
        }
    }

    private func emitSessionCompleteCue() {
        var parts = ["Session complete."]
        let allSamples = roundSamples.flatMap { $0 }
        if !allSamples.isEmpty {
            let avg = Int((allSamples.map(\.bpm).reduce(0, +) / Double(allSamples.count)).rounded())
            parts.append("Average heart rate \(avg).")
            let peak = Int(allSamples.map(\.bpm).max()!.rounded())
            parts.append("Peak \(peak).")
        }
        onAudioCue?(parts.joined(separator: " "), .neutral)
    }
}
