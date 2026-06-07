import Foundation

enum WatchMessageType: String {
    case heartRate
    case startExercise
    case workoutEnded
}

enum WatchMessageKey {
    static let type = "type"
    static let bpm  = "bpm"
    static let date = "date"
}
