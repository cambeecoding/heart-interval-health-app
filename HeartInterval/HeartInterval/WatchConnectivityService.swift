import Foundation
import WatchConnectivity

protocol WatchConnectivityServicing: AnyObject {
    var onHeartRate: ((Double, Date) -> Void)? { get set }
    var onStartExercise: (() -> Void)? { get set }
    var onStartIntervalExercise: (() -> Void)? { get set }
    func activate()
    func sendIntervalConfig(_ config: IntervalConfig)
    func sendIntervalPhaseUpdate(phase: String, round: Int, countdown: Int, seq: Int, totalRounds: Int)
}

final class WatchConnectivityService: NSObject, WatchConnectivityServicing, WCSessionDelegate {

    var onHeartRate: ((Double, Date) -> Void)?
    var onStartExercise: (() -> Void)?
    var onStartIntervalExercise: (() -> Void)?

    private let session: WCSession

    init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate (required)

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        #if DEBUG
        if let error {
            print("[BeatZone WC] Activation error: \(error.localizedDescription)")
        } else {
            print("[BeatZone WC] Activated, state=\(activationState.rawValue)")
        }
        #endif
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    // MARK: - Receive messages from Watch

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any]) {
        guard let rawType = message[WatchMessageKey.type] as? String,
              let type = WatchMessageType(rawValue: rawType) else { return }

        switch type {
        case .heartRate:
            guard let bpm = message[WatchMessageKey.bpm] as? Double,
                  let timestamp = message[WatchMessageKey.date] as? TimeInterval else { return }
            let date = Date(timeIntervalSince1970: timestamp)
            DispatchQueue.main.async { [weak self] in
                self?.onHeartRate?(bpm, date)
            }

        case .startExercise:
            DispatchQueue.main.async { [weak self] in
                self?.onStartExercise?()
            }

        case .workoutEnded:
            break

        case .startIntervalExercise:
            DispatchQueue.main.async { [weak self] in
                self?.onStartIntervalExercise?()
            }

        case .intervalConfig, .intervalPhaseUpdate:
            break
        }
    }

    // MARK: - Send to Watch

    func sendIntervalConfig(_ config: IntervalConfig) {
        guard session.isReachable, let data = try? JSONEncoder().encode(config) else { return }
        let message: [String: Any] = [
            WatchMessageKey.type: WatchMessageType.intervalConfig.rawValue,
            WatchMessageKey.configJSON: data
        ]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func sendIntervalPhaseUpdate(phase: String, round: Int, countdown: Int, seq: Int, totalRounds: Int = 0) {
        guard session.isReachable else { return }
        let message: [String: Any] = [
            WatchMessageKey.type: WatchMessageType.intervalPhaseUpdate.rawValue,
            WatchMessageKey.phase: phase,
            WatchMessageKey.round: round,
            WatchMessageKey.countdown: countdown,
            WatchMessageKey.seq: seq,
            WatchMessageKey.totalRounds: totalRounds
        ]
        session.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }
}
