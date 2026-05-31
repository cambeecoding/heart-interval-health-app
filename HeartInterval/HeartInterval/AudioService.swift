import AVFoundation

/// Abstraction over audio output so the ViewModel can be tested with a spy.
protocol AudioServiceProtocol {
    func speak(_ text: String)
    func startSilentLoop()
    func stopSilentLoop()
    func reactivateSession()
}

final class AudioService: NSObject, AudioServiceProtocol {

    private let synthesizer = AVSpeechSynthesizer()
    private var silentPlayer: AVAudioPlayer?

    /// Tracks how many utterances are active or pending.
    /// Incremented before each speak; decremented in didFinish.
    /// Only releases ducking when it reaches zero.
    private var activeSpeechCount = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func reactivateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #if targetEnvironment(simulator)
        print("[BeatZone Audio] Session activated — ducking other audio")
        #endif
    }

    /// Drops .duckOthers so other audio (music, podcasts) resumes at full volume,
    /// while keeping the session active for background speech.
    private func releaseDucking() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #if targetEnvironment(simulator)
        print("[BeatZone Audio] Ducking released — other audio restored")
        #endif
    }

    /// Starts looping a silent audio buffer so iOS keeps the audio session
    /// alive in the background, allowing speech to fire while screen is off.
    func startSilentLoop() {
        reactivateSession()
        guard silentPlayer == nil else { return }

        // Build a 1-second silent PCM buffer in memory — no audio file needed
        let sampleRate: Double = 44100
        let frameCount = AVAudioFrameCount(sampleRate)
        guard
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return }
        buffer.frameLength = frameCount
        // All samples default to 0 (silence) — no fill needed

        // Convert buffer → Data for AVAudioPlayer
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("silence.caf")
        if !FileManager.default.fileExists(atPath: tmp.path) {
            guard let file = try? AVAudioFile(forWriting: tmp, settings: format.settings) else { return }
            try? file.write(from: buffer)
        }
        guard let player = try? AVAudioPlayer(contentsOf: tmp) else { return }
        player.numberOfLoops = -1   // loop forever
        player.volume = 0
        player.prepareToPlay()
        player.play()
        silentPlayer = player
    }

    func stopSilentLoop() {
        silentPlayer?.stop()
        silentPlayer = nil
    }

    func speak(_ text: String) {
        // Increment BEFORE stopping any current utterance so that when
        // didFinish fires for the interrupted utterance, activeSpeechCount
        // is still ≥ 1 and ducking is not released prematurely.
        activeSpeechCount += 1
        reactivateSession()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate   = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-GB.Serena")
                       ?? AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.siri_Nicky_en-US_premium")
                       ?? AVSpeechSynthesisVoice(language: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
                       ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioService: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        activeSpeechCount = max(0, activeSpeechCount - 1)
        if activeSpeechCount == 0 {
            releaseDucking()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Treat a cancelled utterance the same as finished so the count stays accurate.
        activeSpeechCount = max(0, activeSpeechCount - 1)
        if activeSpeechCount == 0 {
            releaseDucking()
        }
    }
}
