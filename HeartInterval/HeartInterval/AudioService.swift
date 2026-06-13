import AVFoundation

enum SpeechMood {
    case neutral
    case energetic
    case calm
}

/// Abstraction over audio output so the ViewModel can be tested with a spy.
@MainActor
protocol AudioServiceProtocol {
    func speak(_ text: String)
    func speak(_ text: String, mood: SpeechMood)
    func playTick()
    func playGo()
    func startSilentLoop()
    func stopSilentLoop()
    func reactivateSession()
}

@MainActor
final class AudioService: NSObject, AudioServiceProtocol {

    private let synthesizer = AVSpeechSynthesizer()
    private var silentPlayer: AVAudioPlayer?

    /// Tracks how many utterances are active or pending.
    /// Incremented before each speak; decremented in didFinish.
    /// Only releases ducking when it reaches zero.
    private var activeSpeechCount = 0
    private var resolvedVoice: AVSpeechSynthesisVoice?
    private var voiceResolved = false

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

    private var tonePlayer: AVAudioPlayer?

    func playTick() {
        playTone(frequency: 880, duration: 0.08)
    }

    func playGo() {
        playTone(frequency: 1175, duration: 0.25)
    }

    private func playTone(frequency: Double, duration: Double) {
        let sampleRate: Double = 44100
        let frameCount = Int(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))
        else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let fadeFrames = min(frameCount / 4, Int(sampleRate * 0.01))
        for i in 0..<frameCount {
            var sample = Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
            // Fade in
            if i < fadeFrames {
                sample *= Float(i) / Float(fadeFrames)
            }
            // Fade out
            let tail = frameCount - i
            if tail < fadeFrames {
                sample *= Float(tail) / Float(fadeFrames)
            }
            channelData[i] = sample * 0.85
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("tone_\(Int(frequency))_\(Int(duration * 1000)).caf")
        if !FileManager.default.fileExists(atPath: tmp.path) {
            guard let file = try? AVAudioFile(forWriting: tmp, settings: format.settings) else { return }
            try? file.write(from: buffer)
        }
        guard let player = try? AVAudioPlayer(contentsOf: tmp) else { return }
        player.volume = 1.0
        player.prepareToPlay()
        player.play()
        tonePlayer = player
    }

    func speak(_ text: String) {
        speak(text, mood: .neutral)
    }

    func speak(_ text: String, mood: SpeechMood) {
        activeSpeechCount += 1
        reactivateSession()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        let utterance = AVSpeechUtterance(string: text)
        utterance.volume = 1.0
        utterance.voice  = resolveVoice()

        switch mood {
        case .energetic:
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.15
            utterance.pitchMultiplier = 1.15
        case .calm:
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
            utterance.pitchMultiplier = 0.9
        case .neutral:
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.pitchMultiplier = 1.0
        }

        synthesizer.speak(utterance)
    }

    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        if voiceResolved { return resolvedVoice }
        voiceResolved = true

        if let v = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-GB.Serena") {
            resolvedVoice = v; return v
        }

        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let voices = AVSpeechSynthesisVoice.speechVoices()

        if let v = voices.first(where: {
            $0.identifier.lowercased().contains("siri") && $0.language.hasPrefix(lang)
        }) {
            resolvedVoice = v; return v
        }

        if let v = voices.first(where: {
            let id = $0.identifier.lowercased()
            return (id.contains("premium") || id.contains("enhanced")) && $0.language.hasPrefix(lang)
        }) {
            resolvedVoice = v; return v
        }

        let localeId = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
        if let v = AVSpeechSynthesisVoice(language: localeId) {
            resolvedVoice = v; return v
        }

        resolvedVoice = AVSpeechSynthesisVoice(language: "en-US")

        #if DEBUG
        if let v = resolvedVoice {
            print("[BeatZone Voice] Selected: \(v.name) (\(v.identifier))")
        } else {
            print("[BeatZone Voice] No voice resolved — system will use default")
        }
        #endif

        return resolvedVoice
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension AudioService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.activeSpeechCount = max(0, self.activeSpeechCount - 1)
            if self.activeSpeechCount == 0 {
                self.releaseDucking()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.activeSpeechCount = max(0, self.activeSpeechCount - 1)
            if self.activeSpeechCount == 0 {
                self.releaseDucking()
            }
        }
    }
}
