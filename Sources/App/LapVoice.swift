import AVFoundation

/// Reads the lap time and the gap out loud at the end of each lap, with the friend's lap you chase and
/// your place in the live group, turning the music down meanwhile.
final class LapVoice: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func announce(_ e: LapEvent, place: (position: Int, count: Int, gap: Double, rival: String)? = nil) {
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
        func amount(_ gap: Double) -> String {
            numbers.maximumFractionDigits = abs(gap) < 1 ? 2 : 1
            return numbers.string(from: NSNumber(value: abs(gap))) ?? ""
        }
        if let gap = e.gap {
            let value = amount(gap)
            parts.append(gap < 0 ? L("meno \(value)") : L("più \(value)"))
        }
        if let rival = e.rival, let gap = e.rivalGap {
            let value = amount(gap)
            parts.append(gap < 0 ? L("\(rival): meno \(value)") : L("\(rival): più \(value)"))
        }
        if let place {
            parts.append(place.position == 1 ? L("primo nel gruppo")
                         : L("posizione \(place.position), a \(amount(place.gap)) da \(place.rival)"))
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
