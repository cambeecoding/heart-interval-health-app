import Foundation
import Combine
import WatchConnectivity

final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    @Published var isPhoneReachable = false

    private let session = WCSession.default

    private override init() {
        super.init()
    }

    func activate() {
        session.delegate = self
        session.activate()
    }

    func sendHeartRate(_ bpm: Double, date: Date) {
        guard session.isReachable else { return }
        let message: [String: Any] = [
            WatchMessageKey.type: WatchMessageType.heartRate.rawValue,
            WatchMessageKey.bpm: bpm,
            WatchMessageKey.date: date.timeIntervalSince1970
        ]
        session.sendMessage(message, replyHandler: nil) { error in
            #if DEBUG
            print("[BeatZone Watch] sendMessage error: \(error.localizedDescription)")
            #endif
        }
    }

    func sendStartExercise() {
        guard session.isReachable else { return }
        let message: [String: Any] = [
            WatchMessageKey.type: WatchMessageType.startExercise.rawValue
        ]
        session.sendMessage(message, replyHandler: nil) { error in
            #if DEBUG
            print("[BeatZone Watch] sendStartExercise error: \(error.localizedDescription)")
            #endif
        }
    }

    func sendWorkoutEnded() {
        guard session.isReachable else { return }
        let message: [String: Any] = [
            WatchMessageKey.type: WatchMessageType.workoutEnded.rawValue
        ]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isPhoneReachable = session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isPhoneReachable = session.isReachable
        }
    }
}
