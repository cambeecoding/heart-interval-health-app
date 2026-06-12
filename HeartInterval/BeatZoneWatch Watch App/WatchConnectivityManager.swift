import Foundation
import Combine
import WatchConnectivity

final class WatchConnectivityManager: NSObject, ObservableObject {

    static let shared = WatchConnectivityManager()

    @Published var isPhoneReachable = false
    @Published var intervalPhase: String?
    @Published var intervalRound: Int = 0
    @Published var intervalCountdown: Int = 0
    @Published var intervalTotalRounds: Int = 0
    @Published var intervalConfig: Data?

    private let session = WCSession.default
    private var lastSeq = -1

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

    func sendStartIntervalExercise() {
        guard session.isReachable else { return }
        let message: [String: Any] = [
            WatchMessageKey.type: WatchMessageType.startIntervalExercise.rawValue
        ]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func sendWorkoutEnded() {
        guard session.isReachable else { return }
        let message: [String: Any] = [
            WatchMessageKey.type: WatchMessageType.workoutEnded.rawValue
        ]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func clearIntervalState() {
        intervalPhase = nil
        intervalRound = 0
        intervalCountdown = 0
        intervalTotalRounds = 0
        lastSeq = -1
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

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let rawType = message[WatchMessageKey.type] as? String,
              let type = WatchMessageType(rawValue: rawType) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch type {
            case .intervalConfig:
                if let data = message[WatchMessageKey.configJSON] as? Data {
                    self.intervalConfig = data
                }

            case .intervalPhaseUpdate:
                let seq = message[WatchMessageKey.seq] as? Int ?? 0
                guard seq > self.lastSeq else { return }
                self.lastSeq = seq
                self.intervalPhase = message[WatchMessageKey.phase] as? String
                self.intervalRound = message[WatchMessageKey.round] as? Int ?? 0
                self.intervalCountdown = message[WatchMessageKey.countdown] as? Int ?? 0
                if let total = message[WatchMessageKey.totalRounds] as? Int, total > 0 {
                    self.intervalTotalRounds = total
                }

            default:
                break
            }
        }
    }
}
