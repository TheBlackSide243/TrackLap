import Foundation

/// Screenshot mode, for the README and the store pages. Launched with `-showcase <screen>`, the app
/// fills itself with demo sessions on the selected track (the screenshot workflow puts real circuits
/// in tracks.json first) and opens that screen; `-introPage <n>` picks the page of the intro.
/// Without the argument nothing here runs.
enum Showcase: String {
    case live, tracks, editor, sessions, session, analysis, device, intro
    case challenge, group, friends, share

    static let screen: Showcase? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-showcase"), i + 1 < args.count else { return nil }
        return Showcase(rawValue: args[i + 1])
    }()

    /// The pretend friends: their laps to chase, and the cars of the pretend live group.
    fileprivate static let friends = [("Marco", "Clio RS", 0.985), ("Giulia", "Yaris GR", 0.975), ("Davide", "MX-5", 0.95)]
    fileprivate static var cars: [(car: DemoDriver, timer: LapEngine)] = []
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
        if [.challenge, .group, .friends, .share].contains(screen), let track = selectedTrack, track.isReady {
            profile.set(name: "Luca")
            profile.set(vehicle: "Civic Type R")
            fillFriendLaps(on: track)
        }
        switch screen {
        case .intro: tab = .live
        case .live:
            setSource(.demo)
            setDeltaReference(.record)
            start()
            tab = .live
        case .challenge:
            setSource(.demo)
            setChallenge(friends.laps(on: selectedTrackID).first { $0.driver == "Giulia" })
            start()
            tab = .live
        case .group:
            setSource(.demo)
            startPretendGroup()
            start()
            tab = .live
        case .tracks, .editor: tab = .tracks
        case .sessions, .session, .analysis, .friends, .share: tab = .sessions
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
            for lap in demoLaps(on: track, pace: pace, laps: 6.6, from: t0) { session.laps.append(lap) }
            if !session.laps.isEmpty { sessions.save(session) }
        }
    }

    /// The best of three laps of each pretend friend, as if they had sent it.
    private func fillFriendLaps(on track: Track) {
        guard friends.laps(on: track.id).isEmpty else { return }
        for (i, f) in Showcase.friends.enumerated() {
            let t0 = Date().timeIntervalSince1970 - Double(i + 1) * 86_400
            guard let best = demoLaps(on: track, pace: f.2, laps: 3.4, from: t0).min(by: { $0.time < $1.time }) else { continue }
            friends.add(SharedLap(driver: f.0, vehicle: f.1, source: SourceKind.device.rawValue,
                                  date: best.startedAt, track: track, lap: best), on: track)
        }
    }

    private func demoLaps(on track: Track, pace: Double, laps: Double, from t0: Double) -> [Lap] {
        var out: [Lap] = []
        let timer = LapEngine()
        timer.minLapTime = minLapTime
        timer.load(track: track)
        timer.onLap = { out.append($0) }
        let car = DemoDriver()
        car.pace = pace
        let lapGuess = (track.length ?? 3000) / 40
        for s in car.simulate(track: track, seconds: lapGuess * laps + 20, from: t0) { timer.ingest(s) }
        return out
    }

    /// A live group with the pretend friends driving the track with you, a few seconds apart, their
    /// best laps the ones they sent.
    private func startPretendGroup() {
        guard let track = selectedTrack else { return }
        let laps = friends.laps(on: track.id)
        let members = Showcase.friends.enumerated().map { i, f in
            let best = laps.first { $0.driver == f.0 }?.time
            return GroupMember(id: "showcase-\(i)", name: f.0, vehicle: f.1, track: GroupTrack(track), best: best,
                               last: best.map { $0 + 0.6 + Double(i) * 0.3 }, laps: 5 + i, online: true, color: i)
        }
        group.showcase(code: "K7P2Q", members: members, on: track, best: sessions.record(on: track.id)?.lap.time)
        Showcase.cars = []
        // Ahead of you, just ahead, and behind.
        for (i, lead) in [4.0, 1.5, 0].enumerated() {
            let id = "showcase-\(i)"
            let car = DemoDriver()
            car.pace = Showcase.friends[i].2
            let timer = LapEngine()
            timer.minLapTime = minLapTime
            timer.load(track: track)
            var sent = 0.0
            car.onSample = { [weak self] s in
                timer.ingest(s)
                let t = s.wall.timeIntervalSince1970
                guard t - sent >= 1 else { return }
                sent = t
                self?.group.showcaseMove(id, to: GroupPosition(coord: s.coord, lap: timer.lapNumber, distance: timer.lapDistance,
                                                               speed: s.speed, utc: t, received: Date()))
            }
            timer.onLap = { [weak self] lap in self?.group.showcaseLap(id, time: lap.time) }
            car.start(track: track, lead: lead)
            Showcase.cars.append((car, timer))
        }
    }
}
