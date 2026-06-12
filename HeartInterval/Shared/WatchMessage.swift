import Foundation

enum WatchMessageType: String {
    case heartRate
    case startExercise
    case workoutEnded
    case intervalConfig
    case intervalPhaseUpdate
    case startIntervalExercise
}

enum WatchMessageKey {
    static let type = "type"
    static let bpm  = "bpm"
    static let date = "date"
    static let configJSON = "configJSON"
    static let phase = "phase"
    static let round = "round"
    static let countdown = "countdown"
    static let seq = "seq"
    static let totalRounds = "totalRounds"
}
