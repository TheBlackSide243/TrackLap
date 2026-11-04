import Foundation

/// Screenshot mode, for the README and the store pages. Launched with `-showcase <screen>`, the app
/// fills itself with demo sessions on the selected track (the screenshot workflow puts real circuits
/// in tracks.json first, and the photos of the demo garage in Documents/garage) and opens that
/// screen; `-introPage <n>` picks the page of the intro. Without the argument nothing here runs.
enum Showcase: String {
    case live, tracks, editor, sessions, session, analysis, device, intro
    case challenge, group, friends, share
    case drag, dragRun
    case garage, car, setup

    static let screen: Showcase? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-showcase"), i + 1 < args.count else { return nil }
        return Showcase(rawValue: args[i + 1])
    }()

    /// The pretend friends: their laps to chase, and the cars of the pretend live group.
    fileprivate static let people = [("Marco", "Clio RS", 0.985), ("Giulia", "Yaris GR", 0.975), ("Davide", "MX-5", 0.95)]
    fileprivate static var cars: [(car: DemoDriver, timer: LapEngine)] = []
}

extension AppModel {
    /// Opens the screen asked for on the command line, after filling the sessions it needs.
    func runShowcase() {
        guard let screen = Showcase.screen, !showcaseStarted else { return }
        showcaseStarted = true
        fillDemoGarage()
        if [.garage, .car, .setup].contains(screen) {
            account.showcase(name: "Luca", garage: "K7P2QX9M")
            garage.setPublic(true)
        }
        if sessions.summaries.isEmpty, let track = selectedTrack, track.isReady {
            fillDemoSessions(on: track)
            select(track: track.id)
        }
        if [.challenge, .group, .friends, .share].contains(screen), let track = selectedTrack, track.isReady {
            profile.set(name: "Luca")
            profile.set(vehicle: "Civic Type R")
            fillFriendLaps(on: track)
        }
        if [.drag, .dragRun].contains(screen) {
            profile.set(vehicle: "Civic Type R")
            setSource(.demo)
            fillDemoDrags()
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
        case .drag:
            tab = .drag
            setDragMode(true)
            startDemoDrag()
        case .dragRun: tab = .drag
        case .garage, .car, .setup: tab = .garage
        }
    }

    /// Four cars with the photos the workflow put in the garage folder, the first in use, and two
    /// setups for it: one for the dry, changed once, and one for the wet.
    private func fillDemoGarage() {
        guard garage.cars.isEmpty, garage.image("civic") != nil else { return }
        let cars = [
            Car(id: UUID(uuidString: "C1A1C000-0000-4000-8000-000000000001")!, name: "Honda Civic Type R", year: 2016, power: 310, weight: 1382,
                mods: [L("Scarico Milltek"), L("Centralina Hondata"), L("Pastiglie Ferodo DS2500"), L("Tubi freno in treccia"),
                       L("Gomme Michelin Pilot Sport Cup 2"), L("Assetto KW V3")],
                notes: L("Solo pista: Mugello, Misano e Imola. Su strada torna con le gomme di serie."), photo: "civic"),
            Car(id: UUID(uuidString: "C1A1C000-0000-4000-8000-000000000002")!, name: "Toyota GR Yaris Circuit", year: 2022, power: 261, weight: 1280,
                mods: [L("Freni Brembo GT"), L("Intercooler maggiorato"), L("Sedili Recaro")], photo: "yaris"),
            Car(id: UUID(uuidString: "C1A1C000-0000-4000-8000-000000000003")!, name: "Porsche 911 GT3", year: 2018, power: 500, weight: 1413,
                mods: [L("Pacchetto Clubsport"), L("Gomme Michelin Pilot Sport Cup 2 R")], photo: "gt3"),
            Car(id: UUID(uuidString: "C1A1C000-0000-4000-8000-000000000004")!, name: "Mazda MX-5 NA", year: 1989, power: 115, weight: 960,
                mods: [L("Roll-bar"), L("Assetto regolabile"), L("Differenziale autobloccante")], photo: "mx5"),
        ]
        for car in cars.reversed() { garage.save(car) }
        let civic = cars[0].id
        var dry = CarSetup(carID: civic, name: L("Mugello asciutto"), weather: .dry, track: "Mugello")
        dry.values = SetupValues(tyres: "Michelin Pilot Sport Cup 2", pressureFrontCold: 2.0, pressureRearCold: 1.9,
                                 pressureFrontHot: 2.4, pressureRearHot: 2.3, camberFront: -2.2, camberRear: -1.8,
                                 toeFront: 0, toeRear: 1.5, heightFront: 120, heightRear: 125, bumpFront: 8, bumpRear: 10,
                                 reboundFront: 12, reboundRear: 14, springFront: 120, springRear: 100,
                                 barFront: L("Rigida"), barRear: L("Intermedia"), brakeBias: 62)
        garage.save(setup: dry)
        // Changed after a day on track: the first version stays in the history.
        dry.values.pressureFrontCold = 1.9
        dry.values.pressureRearCold = 1.8
        dry.values.camberFront = -2.5
        dry.values.notes = L("Sottosterzo all'Arrabbiata: -0,1 bar e più campanatura davanti. Ora gira bene.")
        garage.save(setup: dry)
        var wet = CarSetup(carID: civic, name: L("Mugello bagnato"), weather: .wet, track: "Mugello")
        wet.values = SetupValues(tyres: "Michelin Pilot Sport 4S", pressureFrontCold: 2.1, pressureRearCold: 2.0,
                                 camberFront: -1.8, camberRear: -1.2, bumpFront: 4, bumpRear: 5, reboundFront: 8, reboundRear: 9,
                                 barFront: L("Morbida"), barRear: L("Morbida"), brakeBias: 58,
                                 notes: L("Più morbido e pressioni più alte: con l'acqua le gomme scaldano poco."))
        garage.save(setup: wet)
        setActiveCar(civic)
        setActiveSetup(dry.id)
    }

    /// Three runs from a standstill a few days apart, the car a little quicker every time.
    private func fillDemoDrags() {
        guard drags.summaries.isEmpty else { return }
        let origin = selectedTrack.map { $0.start?.mid ?? $0.center } ?? Coord(43.9975, 11.3719)
        let now = Date().timeIntervalSince1970
        for (k, power) in [0.94, 0.97, 1.0].enumerated() {
            let timer = DragEngine()
            timer.source = SourceKind.demo.rawValue
            timer.vehicle = profile.displayVehicle
            timer.onFinish = { [weak self] in self?.drags.save($0) }
            for s in DemoDrag.simulate(at: origin, power: power, from: now - Double(3 - k) * 2 * 86_400) { timer.ingest(s) }
        }
    }

    /// Three sessions a few days apart, six laps each, a little faster every time.
    private func fillDemoSessions(on track: Track) {
        let now = Date().timeIntervalSince1970
        for (k, pace) in [0.955, 0.968, 0.98].enumerated() {
            let t0 = now - Double(3 - k) * 4 * 86_400
            var session = Session(trackID: track.id, trackName: track.name, date: Date(timeIntervalSince1970: t0),
                                  source: SourceKind.demo.title, sectorCount: track.sectorCount)
            session.carID = activeCar?.id
            session.carName = activeCar?.displayName
            session.setup = activeSetup?.snapshot
            for lap in demoLaps(on: track, pace: pace, laps: 6.6, from: t0) { session.laps.append(lap) }
            if !session.laps.isEmpty { sessions.save(session) }
        }
    }

    /// The best of three laps of each pretend friend, as if they had sent it.
    private func fillFriendLaps(on track: Track) {
        guard friends.laps(on: track.id).isEmpty else { return }
        for (i, f) in Showcase.people.enumerated() {
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
        let members = Showcase.people.enumerated().map { i, f in
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
            car.pace = Showcase.people[i].2
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
