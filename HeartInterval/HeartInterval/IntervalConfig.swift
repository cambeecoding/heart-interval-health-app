import Foundation

enum TrainingMode: String, CaseIterable {
    case zone
    case intervals
}

struct IntervalConfig: Codable, Equatable {
    var workDuration: Int = 30
    var restDuration: Int = 30
    var rounds: Int = 8
    var warmupDuration: Int = 0

    var totalDuration: Int {
        warmupDuration + rounds * workDuration + max(0, rounds - 1) * restDuration
    }

    static let tabata = IntervalConfig(workDuration: 20, restDuration: 10, rounds: 8)
    static let thirtyThirty = IntervalConfig(workDuration: 30, restDuration: 30, rounds: 10)
    static let pt = IntervalConfig(workDuration: 50, restDuration: 20, rounds: 9)
    static let emom = IntervalConfig(workDuration: 50, restDuration: 10, rounds: 10)
    static let long = IntervalConfig(workDuration: 180, restDuration: 60, rounds: 5)
}

enum IntervalPhase: Equatable {
    case warmup
    case work(round: Int)
    case rest(round: Int)
    case finished

    var isWork: Bool {
        if case .work = self { return true }
        return false
    }
}
