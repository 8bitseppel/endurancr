import AVFoundation

/// The keys of the run settings in the ⋯ menu on Today. All off until switched on.
enum RunSettings {
    /// The iPhone says out loud where an effort begins or ends (`RunCue.spoken`).
    static let spokenCuesKey = "spokenCues"
    /// The iPhone pauses the run when you stand still, and goes on when you run.
    static let autoPauseKey = "phoneAutoPause"
    /// The watch taps when the heart rate moves into another zone (watchOS 27).
    static let zoneTapsKey = "zoneTaps"

    static var spokenCues: Bool { UserDefaults.standard.bool(forKey: spokenCuesKey) }
    static var autoPause: Bool { UserDefaults.standard.bool(forKey: autoPauseKey) }
}

/// The iPhone's voice for a guided run: "Go.", "Easy.", "Rep 3 of 6 in 70 metres."
/// The iPhone's counterpart of the taps on the wrist, for a phone in a pocket or an
/// armband, where a vibration goes unnoticed.
///
/// Music only dips while it speaks: the audio session is active just for the
/// sentence and lets other audio go back to full volume after it. Spoken over
/// podcasts too, which pause for it rather than talk over it.
@MainActor
final class SpokenCues: NSObject {
    static let shared = SpokenCues()
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Says `text` now, cutting off anything still being said: a cue that's late is
    /// a wrong cue.
    func say(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt,
                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        // The cues are written in English, so they're read by an English voice.
        let language = Locale.current.language.languageCode?.identifier == "en"
            ? AVSpeechSynthesisVoice.currentLanguageCode() : "en-US"
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        synthesizer.speak(utterance)
    }

    private func finished() {
        guard !synthesizer.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension SpokenCues: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }
}
