import AVFoundation

/// Reads the lap time and the gap out loud at the end of each lap, turning the music down meanwhile.
final class LapVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func announce(_ e: LapEvent) {
        let voice = Self.voice
        let numbers = NumberFormatter()
        numbers.locale = Locale(identifier: voice?.language ?? "en")
        numbers.minimumFractionDigits = 1
        numbers.maximumFractionDigits = 1

        var parts: [String] = []
        if e.isRecord {
            parts.append(L("Nuovo record della pista"))
        } else if e.isBest {
            parts.append(L("Nuovo best"))
        }
        // "1 32.4" is read as one, thirty-two point four.
        let minutes = Int(e.time) / 60
        let seconds = numbers.string(from: NSNumber(value: e.time - Double(minutes * 60))) ?? ""
        parts.append(minutes > 0 ? "\(minutes) \(seconds)" : seconds)
        if let gap = e.gap {
            numbers.maximumFractionDigits = abs(gap) < 1 ? 2 : 1
            let value = numbers.string(from: NSNumber(value: abs(gap))) ?? ""
            parts.append(gap < 0 ? L("meno \(value)") : L("più \(value)"))
        }

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: parts.joined(separator: ", "))
        u.voice = voice
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A voice in the language the app is shown in.
    private static var voice: AVSpeechSynthesisVoice? {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let current = AVSpeechSynthesisVoice.currentLanguageCode()
        if current.hasPrefix(code) { return AVSpeechSynthesisVoice(language: current) }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(code) }
    }
}
