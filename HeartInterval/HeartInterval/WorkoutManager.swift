import UIKit

/// Handles idle-timer suppression and background audio session lifecycle.
final class WorkoutManager {

    func beginExercise() {
        // Keep screen on during exercise
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func endExercise() {
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
