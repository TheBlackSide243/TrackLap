import Foundation

/// Screenshot mode, for the README and the store pages. Launched with `-showcase <screen>`, the app
/// fills itself with demo sessions on the selected track (the screenshot workflow puts real circuits
/// in tracks.json first) and opens that screen; `-introPage <n>` picks the page of the intro.
/// Without the argument nothing here runs.
enum Showcase: String {
    case live, tracks, editor, sessions, session, analysis, device, intro

    static let screen: Showcase? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-showcase"), i + 1 < args.count else { return nil }
        return Showcase(rawValue: args[i + 1])
    }()
}

extension AppModel {
    /// Opens the screen asked for on the command line, after filling the sessions it needs.
    func runShowcase() {
        guard let screen = Showcase.screen, !showcaseStarted else { return }
        showcaseStarted = true
        if sessions.summaries.isEmpty, let track = selectedTrack, track.isReady {
            fillDemoSessions(on: track)
            select(track: track.id)
        }
        switch screen {
        case .intro: tab = .live
        case .live:
            setSource(.demo)
            setDeltaReference(.record)
            start()
            tab = .live
        case .tracks, .editor: tab = .tracks
        case .sessions, .session, .analysis: tab = .sessions
        case .device: tab = .device
        }
    }

    /// Three sessions a few days apart, six laps each, a little faster every time.
    private func fillDemoSessions(on track: Track) {
        let now = Date().timeIntervalSince1970
        for (k, pace) in [0.955, 0.968, 0.98].enumerated() {
            let t0 = now - Double(3 - k) * 4 * 86_400
            var session = Session(trackID: track.id, trackName: track.name, date: Date(timeIntervalSince1970: t0),
                                  source: SourceKind.demo.title, sectorCount: track.sectorCount)
            let timer = LapEngine()
            timer.minLapTime = minLapTime
            timer.load(track: track)
            timer.onLap = { session.laps.append($0) }
            let car = DemoDriver()
            car.pace = pace
            let lapGuess = (track.length ?? 3000) / 40
            for s in car.simulate(track: track, seconds: lapGuess * 6.6 + 20, from: t0) { timer.ingest(s) }
            if !session.laps.isEmpty { sessions.save(session) }
        }
    }
}
