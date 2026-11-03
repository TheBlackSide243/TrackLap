import AVFoundation

/// Reads the lap time and the gap out loud at the end of each lap, with the friend's lap you chase and
/// your place in the live group, and the main measures of a drag run, turning the music down meanwhile.
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

        say(parts.joined(separator: ", "), voice: voice)
    }

    /// 0–100, the quarter mile and the stop of a drag run, as they are done.
    func announce(_ e: DragEvent) {
        let voice = Self.voice
        let numbers = NumberFormatter()
        numbers.locale = Locale(identifier: voice?.language ?? "en")
        numbers.minimumFractionDigits = 1
        numbers.maximumFractionDigits = e.result.time < 10 ? 2 : 1
        let seconds = numbers.string(from: NSNumber(value: e.result.time)) ?? ""
        let m = e.measure
        var parts: [String] = []
        if e.isRecord { parts.append(L("Nuovo record")) }
        switch m.kind {
        case .speed:
            parts.append(L("da \(Int((m.from * Fmt.speedFactor).rounded())) a \(Int((m.to * Fmt.speedFactor).rounded())): \(seconds) secondi"))
        case .distance:
            let speed = Int((e.result.speed * Fmt.speedFactor).rounded())
            parts.append(L("\(Self.spoken(m)): \(seconds) secondi a \(speed)"))
        case .braking:
            let from = Int((m.from * Fmt.speedFactor).rounded())
            if Units.current == .metric {
                numbers.maximumFractionDigits = 1
                let metres = numbers.string(from: NSNumber(value: e.result.distance)) ?? ""
                parts.append(L("frenata da \(from): \(metres) metri"))
            } else {
                parts.append(L("frenata da \(from): \(Int((e.result.distance * 3.28084).rounded())) piedi"))
            }
        }
        say(parts.joined(separator: ", "), voice: voice)
    }

    private static func spoken(_ m: DragMeasure) -> String {
        switch m.name {
        case "1/4 mi": L("quarto di miglio")
        case "1/8 mi": L("ottavo di miglio")
        case "1/2 mi": L("mezzo miglio")
        default: m.name
        }
    }

    private func say(_ text: String, voice: AVSpeechSynthesisVoice?) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        synth.stopSpeaking(at: .immediate)
        synth.speak(u)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A voice in the language the app is shown in, looked up once: going through the voices can
    /// hold up the main thread for seconds.
    private static let voice: AVSpeechSynthesisVoice? = {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let current = AVSpeechSynthesisVoice.currentLanguageCode()
        if current.hasPrefix(code) { return AVSpeechSynthesisVoice(language: current) }
        return AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(code) }
    }()
}
