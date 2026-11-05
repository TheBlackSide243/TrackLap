import SwiftUI
import UIKit
import Observation

enum SourceKind: String, CaseIterable, Identifiable {
    case device, phone, demo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: "ESP32 TrackLap"
        case .phone: L("GPS dell'iPhone")
        case .demo: "Demo"
        }
    }

    var short: String {
        switch self {
        case .device: "ESP32"
        case .phone: "iPhone"
        case .demo: "Demo"
        }
    }

    var icon: String {
        switch self {
        case .device: "cpu"
        case .phone: "iphone"
        case .demo: "play.circle.fill"
        }
    }

    var detail: String {
        switch self {
        case .device: L("Qualsiasi ESP32 con Bluetooth + GPS a 10–25 Hz: tempi precisi al centesimo.")
        case .phone: L("Circa 1 Hz: va bene per provare e per segnare la linea a piedi.")
        case .demo: L("Un'auto simulata gira sulla pista scelta: prova tutto senza hardware.")
        }
    }
}

extension SourceKind {
    /// The kind behind the source a session was saved with: its title, in the language of the time.
    init(sessionSource s: String) {
        self = s.contains("ESP32") ? .device : s == SourceKind.demo.title ? .demo : .phone
    }
}

enum AppTab: Hashable { case live, drag, tracks, sessions, garage, friends, device }

/// What the live delta compares with.
enum DeltaReference: String, CaseIterable, Identifiable {
    case session, record

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: L("Best sessione")
        case .record: L("Record pista")
        }
    }
}

@Observable
final class AppModel {
    var tab: AppTab = .live
    let tracks = TrackStore()
    let sessions = SessionStore()
    let engine = LapEngine()
    let ble = BLEManager()
    let phone = PhoneGPS()
    let demo = DemoDriver()
    let profile: DriverProfile
    let friends = FriendLapStore()
    let group: GroupSession
    let drag = DragEngine()
    let drags = DragStore()
    let demoDrag = DemoDrag()
    let account = AccountStore()
    let garage = GarageStore()
    /// The drivers you are friends with on TrackLap (the friends' laps above are files they sent).
    let friendList = FriendStore()

    private(set) var source: SourceKind = .demo
    private(set) var selectedTrackID: UUID? = nil
    private(set) var isRunning = false
    private(set) var gpsRate: Double = 0
    private(set) var lastFixWall: Date? = nil
    private(set) var currentSessionID: UUID? = nil
    private(set) var minLapTime: Double = 20
    private(set) var deltaScale: Double = 2
    private(set) var units: Units = Units.current
    private(set) var deltaReference: DeltaReference = .session
    private(set) var voiceOn = true
    /// The friend's lap chased on the selected track.
    private(set) var challenge: FriendLap? = nil
    /// The Drag tab is open: the fixes go to the drag timer too.
    private(set) var dragOn = false
    private(set) var dragRollout = false
    /// Runs from a standstill start with the button (the default); off, by themselves.
    private(set) var dragManualStart = true
    /// The car of your garage you are driving: sessions remember it, and your laps on the
    /// leaderboards link to it.
    private(set) var activeCarID: UUID? = nil
    /// Someone's public garage opened from a link or a leaderboard.
    var shownGarage: GarageLink? = nil
    /// The setup of the active car you drive with: sessions keep it as it was that day.
    private(set) var activeSetupID: UUID? = nil
    /// A setup file opened from Messages or Files, waiting for you to pick its car.
    var importedSetup: SharedSetup? = nil
    /// A group invitation opened before signing in: Live asks you to sign in, then joins it.
    var pendingJoin: String? = nil
    /// A friend invitation opened from its link, waiting for you to accept it.
    var pendingInvite: String? = nil

    /// Set once the screenshot mode has opened its screen (see Showcase).
    @ObservationIgnored var showcaseStarted = false
    @ObservationIgnored private let voice = LapVoice()
    @ObservationIgnored private var session: Session? = nil
    @ObservationIgnored private var recentT: [Double] = []
    @ObservationIgnored private var sentPlace: [Int] = []

    var selectedTrack: Track? { tracks.track(selectedTrackID) }
    var activeCar: Car? { garage.car(activeCarID) }
    var activeSetup: CarSetup? { garage.setup(activeSetupID).flatMap { $0.carID == activeCarID ? $0 : nil } }
    var canStart: Bool { selectedTrack?.isReady == true }

    init() {
        let me = DriverProfile()
        profile = me
        group = GroupSession(profile: me)
        let d = UserDefaults.standard
        source = SourceKind(rawValue: d.string(forKey: "source") ?? "") ?? .demo
        if let v = d.object(forKey: "deltaScale") as? Double { deltaScale = v }
        if let v = d.object(forKey: "minLapTime") as? Double { minLapTime = v }
        if let v = d.object(forKey: "voice") as? Bool { voiceOn = v }
        dragRollout = d.bool(forKey: "dragRollout")
        if let v = d.object(forKey: "dragManualStart") as? Bool { dragManualStart = v }
        deltaReference = DeltaReference(rawValue: d.string(forKey: "deltaReference") ?? "") ?? .session
        if let s = d.string(forKey: "track"), let id = UUID(uuidString: s), tracks.track(id) != nil {
            selectedTrackID = id
        } else {
            selectedTrackID = tracks.tracks.first?.id
        }
        if let s = d.string(forKey: "activeCar"), let id = UUID(uuidString: s), garage.car(id) != nil { activeCarID = id }
        if let s = d.string(forKey: "activeSetup"), let id = UUID(uuidString: s), garage.setup(id)?.carID == activeCarID { activeSetupID = id }
        garage.account = account
        friendList.account = account
        account.onChange = { [weak self] in self?.accountChanged() }
        engine.minLapTime = minLapTime
        prepareEngine(selectedTrack)

        ble.onSample = { [weak self] s in self?.receive(s, from: .device) }
        phone.onSample = { [weak self] s in self?.receive(s, from: .phone) }
        demo.onSample = { [weak self] s in self?.receive(s, from: .demo) }
        demoDrag.onSample = { [weak self] s in self?.receive(s, from: .demo) }
        ble.onConnected = { [weak self] in
            guard let self else { return }
            self.sendDragToDevice()
            guard let t = self.selectedTrack else { return }
            self.ble.send(track: t)
            self.sendChallengeToDevice()
            self.sendGroupToDevice(force: true)
        }
        drag.onPhase = { [weak self] _ in self?.sendDragToDevice() }
        drag.onEvent = { [weak self] e in self?.dragResult(e) }
        drag.onFinish = { [weak self] r in self?.drags.save(r) }
        engine.onLap = { [weak self] lap in self?.record(lap) }
        group.onStandingsChange = { [weak self] in self?.sendGroupToDevice() }
        activate(source)
        group.resume(on: selectedTrack)
    }

    // MARK: - Source

    func setSource(_ k: SourceKind) {
        guard k != source else { return }
        if isRunning { stop() }
        deactivate(source)
        source = k
        UserDefaults.standard.set(k.rawValue, forKey: "source")
        recentT = []
        gpsRate = 0
        lastFixWall = nil
        drag.reset()
        drag.source = k.rawValue
        activate(k)
    }

    private func activate(_ k: SourceKind) {
        switch k {
        case .device: ble.activate()
        case .phone: phone.start()
        case .demo: break
        }
    }

    private func deactivate(_ k: SourceKind) {
        switch k {
        case .device: ble.deactivate()
        case .phone: phone.stop()
        case .demo:
            demo.stop()
            demoDrag.stop()
        }
    }

    private func receive(_ s: Sample, from kind: SourceKind) {
        guard kind == source else { return }
        lastFixWall = s.wall
        recentT.append(s.t)
        if recentT.count > 20 { recentT.removeFirst(recentT.count - 20) }
        if let f = recentT.first, let l = recentT.last, l > f {
            gpsRate = Double(recentT.count - 1) / (l - f)
        }
        if isRunning { engine.ingest(s) } else { engine.observe(s) }
        if dragOn && !isRunning { drag.ingest(s) }
        if group.isOn { group.report(s, lap: isRunning ? engine.lapNumber : 0, distance: engine.lapDistance) }
    }

    // MARK: - Tracks

    func select(track id: UUID) {
        if isRunning { stop() }
        selectedTrackID = id
        UserDefaults.standard.set(id.uuidString, forKey: "track")
        prepareEngine(selectedTrack)
        if let t = selectedTrack { ble.send(track: t) }
        sendChallengeToDevice()
        group.setTrack(selectedTrack)
    }

    func save(track t: Track) {
        tracks.upsert(t)
        if t.id == selectedTrackID && !isRunning {
            prepareEngine(t)
            ble.send(track: t)
            sendChallengeToDevice()
            group.setTrack(t)
        }
    }

    func deleteTrack(_ id: UUID) {
        if id == selectedTrackID && isRunning { stop() }
        tracks.delete(id)
        guard id == selectedTrackID else { return }
        if let first = tracks.tracks.first {
            select(track: first.id)
        } else {
            selectedTrackID = nil
            engine.load(track: nil)
        }
    }

    // MARK: - Session

    func start() {
        guard let track = selectedTrack, track.isReady else { return }
        engine.minLapTime = minLapTime
        prepareEngine(track)
        var s = Session(trackID: track.id, trackName: track.name, date: Date(),
                        source: source.title, sectorCount: track.sectorCount)
        s.carID = activeCar?.id
        s.carName = activeCar?.displayName
        s.layout = track.layout?.key
        s.setup = activeSetup?.snapshot
        session = s
        currentSessionID = s.id
        isRunning = true
        UIApplication.shared.isIdleTimerDisabled = true
        switch source {
        case .demo: demo.start(track: track)
        case .device: ble.resetDeviceSession()
        case .phone: phone.start()
        }
    }

    func stop() {
        isRunning = false
        UIApplication.shared.isIdleTimerDisabled = false
        if source == .demo { demo.stop() }
        if let s = session, !s.laps.isEmpty { sessions.save(s) }
        session = nil
        currentSessionID = nil
    }

    private func record(_ lap: Lap) {
        let lap = layoutSwitch(after: lap) ?? lap
        session?.laps.append(lap)
        // Saved after every lap, so nothing is lost if the app is closed mid-session.
        if let s = session { sessions.save(s) }
        group.finished(lap)
        if voiceOn, let e = engine.lastEvent { voice.announce(e, place: group.isOn ? group.place : nil) }
        // The best lap of each session goes to the leaderboard, which keeps it if it is your best there.
        if profile.publishLaps, source != .demo, engine.lastEvent?.isBest == true, let track = selectedTrack,
           let token = account.token {
            let kind = source
            let car = session?.carID
            Task { try? await Server.submit(lap, source: kind, track: track, car: car, token: token) }
        }
    }

    /// Loads the track into the timer together with its record from earlier sessions and the friend's
    /// lap chased there.
    private func prepareEngine(_ track: Track?) {
        engine.load(track: track)
        engine.compareWithRecord = deltaReference == .record
        engine.setRecord(sessions.record(on: track)?.lap)
        applyChallenge(savedChallenge(for: track))
    }

    /// A lap on another layout of the track (the Junior at Monza instead of the full circuit): the
    /// track takes that layout's lines, the session so far is closed and a new one goes on for this
    /// layout, and the timer compares with its laps and its record. The lap comes back with its
    /// sectors on the new lines; nil when the layout has not changed.
    private func layoutSwitch(after lap: Lap) -> Lap? {
        guard var track = selectedTrack, let layouts = track.layouts, layouts.count > 1,
              let found = LayoutMatch.best(lap.trace, among: layouts), found.key != track.activeLayout else { return nil }
        track.use(found)
        tracks.upsert(track)
        var moved = lap
        moved.sectors = LayoutMatch.sectors(of: lap, on: found.sectors)
        if let s = session, !s.laps.isEmpty {
            sessions.save(s)
            var next = Session(trackID: track.id, trackName: track.name, date: Date(), source: s.source,
                               sectorCount: track.sectorCount)
            next.carID = s.carID
            next.carName = s.carName
            next.setup = s.setup
            next.layout = found.key
            session = next
            currentSessionID = next.id
        } else {
            session?.layout = found.key
            session?.sectorCount = track.sectorCount
        }
        let record = sessions.record(on: track)?.lap
        // After the timer has finished with this crossing: it is still inside it now.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.engine.switchLayout(start: found.start, sectors: found.sectors, record: record, laps: [moved])
            self.ble.send(track: track)
        }
        return moved
    }

    // MARK: - Friends' laps

    /// A .tracklap file opened from Messages, WhatsApp, AirDrop or Files. The lap goes with the
    /// friends' laps, on your track with the same start line, or else on the friend's track, added to yours.
    @discardableResult
    func importLap(from url: URL) throws -> FriendLap {
        let shared = try SharedLap.read(url)
        return friends.add(shared, on: matchingTrack(for: shared.track) ?? adding(shared.track))
    }

    /// The same circuit among your tracks: the same one, or a start line within 40 m.
    private func matchingTrack(for t: Track) -> Track? {
        if let same = tracks.track(t.id) { return same }
        guard let start = t.start else { return nil }
        return tracks.tracks.first { mine in mine.start.map { Geo.distance($0.mid, start.mid) < 40 } ?? false }
    }

    private func adding(_ t: Track) -> Track {
        var copy = t
        copy.created = Date()
        tracks.upsert(copy)
        return copy
    }

    /// Chase a friend's lap: its track is selected (added back if it was deleted), Live opens, and the
    /// delta is measured against their lap.
    func chase(_ f: FriendLap) {
        var lap = f
        if tracks.track(f.trackID) == nil, let s = friends.shared(f.id) {
            let t = matchingTrack(for: s.track) ?? adding(s.track)
            friends.move(f.id, to: t)
            lap.trackID = t.id
            lap.trackName = t.name
        }
        if lap.trackID != selectedTrackID { select(track: lap.trackID) }
        setChallenge(lap)
        tab = .live
    }

    /// The friend's lap to chase on the selected track, nil for none.
    func setChallenge(_ f: FriendLap?) {
        guard let track = selectedTrack else { return }
        let lap = f?.trackID == track.id ? f : nil
        UserDefaults.standard.set(lap?.id.uuidString, forKey: "challenge." + track.id.uuidString)
        applyChallenge(lap)
    }

    func deleteFriendLap(_ id: UUID) {
        friends.delete(id)
        if challenge?.id == id { setChallenge(nil) }
    }

    private func applyChallenge(_ f: FriendLap?) {
        let lap = f.flatMap { friends.lap($0.id) }
        challenge = lap == nil ? nil : f
        engine.setGhost(lap, name: f?.driver)
        sendChallengeToDevice()
    }

    private func savedChallenge(for track: Track?) -> FriendLap? {
        guard let track, let s = UserDefaults.standard.string(forKey: "challenge." + track.id.uuidString) else { return nil }
        return friends.laps.first { $0.id.uuidString == s && $0.trackID == track.id }
    }

    /// The ESP32 compares at every line with the friend's lap too: its time at each of your sector lines.
    private func sendChallengeToDevice() {
        guard let ghost = engine.ghost, let track = selectedTrack else {
            ble.setRival(time: nil, splits: [])
            return
        }
        ble.setRival(time: ghost.time, splits: track.sectors.map { ghost.time(crossing: $0) ?? 0 })
    }

    /// Your place in the live group on the ESP32's screen, sent when it changes.
    private func sendGroupToDevice(force: Bool = false) {
        let p = group.place
        let packet = [p?.position ?? 0, p?.count ?? 0, Int(((p?.gap ?? 0) * 1000).rounded())]
        guard force || packet != sentPlace else { return }
        sentPlace = packet
        ble.setGroup(position: p?.position ?? 0, count: p?.count ?? 0, gap: p?.gap)
    }

    // MARK: - Drag

    /// The Drag tab opened or closed: the drag timer starts afresh, with the records to beat, and the
    /// ESP32 switches dashboard.
    func setDragMode(_ on: Bool) {
        guard on != dragOn else { return }
        dragOn = on
        drag.reset()
        if on {
            drag.bests = drags.bests(car: activeCarID)
            drag.rollout = dragRollout
            drag.needsArming = dragManualStart
            drag.source = source.rawValue
            drag.vehicle = profile.displayVehicle
            drag.carID = activeCarID
            if drag.run == nil, let last = drags.summaries.first, let r = drags.load(last.id) { drag.show(r) }
        } else {
            demoDrag.stop()
        }
        sendDragToDevice()
    }

    /// A simulated run on a straight road by the selected track, for the Demo.
    func startDemoDrag() {
        guard source == .demo, dragOn else { return }
        // The demo car presses the button for you.
        drag.arm()
        demoDrag.start(at: selectedTrack.map { $0.start?.mid ?? $0.center } ?? Coord(43.9975, 11.3719))
    }

    func setDragManualStart(_ on: Bool) {
        dragManualStart = on
        drag.needsArming = on
        if !on { drag.disarm() }
        UserDefaults.standard.set(on, forKey: "dragManualStart")
    }

    func setDragRollout(_ on: Bool) {
        dragRollout = on
        drag.rollout = on
        UserDefaults.standard.set(on, forKey: "dragRollout")
    }

    func deleteDragRun(_ id: UUID) {
        drags.delete(id)
        drag.bests = drags.bests(car: activeCarID)
        if drag.run?.id == id && !drag.inProgress {
            drag.show(nil)
            if let last = drags.summaries.first, let r = drags.load(last.id) { drag.show(r) }
        }
    }

    /// The voice reads the main measures; the ESP32 shows them for a few seconds.
    private func dragResult(_ e: DragEvent) {
        guard e.measure.headline else { return }
        if voiceOn { voice.announce(e) }
        let braking = e.result.kind == .braking
        ble.showDrag(label: e.measure.short, time: braking ? nil : e.result.time,
                     distance: braking ? e.result.distance : nil, best: e.isBest)
    }

    /// The ESP32's drag dashboard while the Drag tab is open (not during a lap session), the lap one otherwise.
    private func sendDragToDevice() {
        guard dragOn && !isRunning else {
            ble.setDrag(state: nil)
            return
        }
        let state: UInt8 = drag.phase == .ready ? 1 : drag.phase == .running ? 2 : 0
        ble.setDrag(state: state, elapsed: drag.startWall.map { Date().timeIntervalSince($0) } ?? 0)
    }

    // MARK: - Live group

    /// tracklap://join/<code>, from the QR code of a group or an invitation; tracklap://garage/…
    /// for someone's garage; tracklap://friend/<code> for a friend invitation.
    func open(_ url: URL) -> Bool {
        if let link = GarageLink(url: url) {
            shownGarage = link
            return true
        }
        if url.scheme == "tracklap", url.host == "friend" {
            let code = url.lastPathComponent.uppercased()
            if FriendStore.isInviteCode(code) { pendingInvite = code }
            return true
        }
        guard url.scheme == "tracklap", url.host == "join" else { return false }
        if account.isSignedIn {
            group.join(url.lastPathComponent, on: selectedTrack)
        } else {
            let code = GroupSession.clean(url.lastPathComponent)
            pendingJoin = code.isEmpty ? nil : code
        }
        tab = .live
        return true
    }

    /// The invitation that waited for you to sign in.
    func joinPending() {
        guard let code = pendingJoin, account.isSignedIn else { return }
        pendingJoin = nil
        group.join(code, on: selectedTrack)
        tab = .live
    }

    // MARK: - Garage

    /// The car you drive from now on; its name becomes the vehicle the others see.
    func setActiveCar(_ id: UUID?) {
        let car = garage.car(id)
        if car?.id != activeCarID {
            // Another car: the setup it was last driven with, if any.
            let last = sessions.summaries.first { $0.carID == car?.id && $0.setupID != nil }?.setupID
            setActiveSetup(garage.setup(last)?.carID == car?.id ? last : nil)
        }
        activeCarID = car?.id
        UserDefaults.standard.set(car?.id.uuidString, forKey: "activeCar")
        if let car {
            profile.set(vehicle: String(car.displayName.prefix(DriverProfile.maxLength)))
            group.profileChanged()
        }
        // The Drag tab open: the next run is with this car, and its records are the ones to beat.
        if dragOn && !drag.inProgress {
            drag.vehicle = profile.displayVehicle
            drag.carID = car?.id
            drag.bests = drags.bests(car: car?.id)
        }
    }

    /// The setup you drive with from now on: the next sessions keep it as it is when they start.
    func setActiveSetup(_ id: UUID?) {
        activeSetupID = garage.setup(id)?.id
        UserDefaults.standard.set(activeSetupID?.uuidString, forKey: "activeSetup")
    }

    /// The setup you drive with, and the car it is for.
    func drive(setup: CarSetup) {
        setActiveCar(setup.carID)
        setActiveSetup(setup.id)
    }

    func deleteSetup(_ id: UUID) {
        if id == activeSetupID { setActiveSetup(nil) }
        garage.delete(setup: id)
    }

    func deleteCar(_ id: UUID) {
        if id == activeCarID { setActiveCar(nil) }
        garage.delete(id)
    }

    /// Signed in or out: the garage and the friends follow the account, and your name for the live
    /// groups is the account's when you had none.
    private func accountChanged() {
        if let name = account.name, !profile.hasName {
            profile.set(name: String(name.prefix(DriverProfile.maxLength)))
            group.profileChanged()
        }
        garage.accountChanged()
        friendList.accountChanged()
        PushNotifications.shared.sync()
    }

    // MARK: - Settings

    func setUnits(_ u: Units) {
        units = u
        UserDefaults.standard.set(u.rawValue, forKey: Units.key)
    }

    func setDeltaReference(_ r: DeltaReference) {
        deltaReference = r
        engine.compareWithRecord = r == .record
        UserDefaults.standard.set(r.rawValue, forKey: "deltaReference")
    }

    func setVoice(_ on: Bool) {
        voiceOn = on
        UserDefaults.standard.set(on, forKey: "voice")
    }

    func setMinLapTime(_ v: Double) {
        minLapTime = v
        engine.minLapTime = v
        UserDefaults.standard.set(v, forKey: "minLapTime")
    }

    func setDeltaScale(_ v: Double) {
        deltaScale = v
        UserDefaults.standard.set(v, forKey: "deltaScale")
    }
}
