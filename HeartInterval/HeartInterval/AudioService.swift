import AVFoundation

final class AudioService {

    private let synthesizer = AVSpeechSynthesizer()

    init() {
        configureAudioSession()
    }

    /// Speaks `text` through whatever output the user currently has active
    /// (speaker or Bluetooth headphones). Mixes with any playing audio.
    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        // Use the default voice for the device locale
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
        synthesizer.speak(utterance)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback category with .mixWithOthers so music keeps playing
        try? session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
    }
}
