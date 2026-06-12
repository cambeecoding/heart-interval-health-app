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
    var onAudioCue: ((String) -> Void)? { get set }
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
    var onAudioCue: ((String) -> Void)?
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

    private func emitPhaseStartCue(_ phase: IntervalPhase) {
        switch phase {
        case .warmup:
            let mins = config.warmupDuration / 60
            let secs = config.warmupDuration % 60
            if mins > 0 && secs == 0 {
                onAudioCue?("Warm up. \(mins) \(mins == 1 ? "minute" : "minutes").")
            } else {
                onAudioCue?("Warm up. \(config.warmupDuration) seconds.")
            }
        case .work(let round):
            if round == totalRounds {
                onAudioCue?("Last round. Work.")
            } else {
                onAudioCue?("Round \(round). Work.")
            }
        case .rest:
            if let hr = currentHR {
                onAudioCue?("Rest. Heart rate \(hr).")
            } else {
                onAudioCue?("Rest.")
            }
        case .finished:
            break
        }
    }

    private func emitTickCues() {
        guard let phase = currentPhase else { return }
        let duration = durationForCurrentPhase()

        switch phase {
        case .warmup:
            if config.warmupDuration >= 60 {
                let midpoint = config.warmupDuration / 2
                if countdown == midpoint {
                    onAudioCue?("\(countdown) seconds remaining.")
                }
                if countdown == 30 && midpoint != 30 {
                    onAudioCue?("30 seconds.")
                }
            }
        case .work:
            if duration > 15 && countdown == 10 {
                onAudioCue?("10 seconds.")
            }
            if duration >= 10 {
                let half = duration / 2
                if countdown == half && half != 10 && half > 3 {
                    onAudioCue?("Halfway.")
                }
            }
        case .rest, .finished:
            break
        }

        if countdown >= 1 && countdown <= 3 {
            onAudioCue?("\(countdown)")
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
        onAudioCue?(parts.joined(separator: " "))
    }
}
