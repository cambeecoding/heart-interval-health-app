import Foundation

struct IntervalRound: Equatable {
    let roundNumber: Int
    let peakHR: Double
    let avgHR: Double
    let recoveryDrop: Double?
}

struct IntervalPhaseRecord: Equatable {
    let isWork: Bool
    let startDate: Date
    let endDate: Date
}

struct IntervalSessionData: Equatable {
    let config: IntervalConfig
    let rounds: [IntervalRound]
    let phases: [IntervalPhaseRecord]
}
