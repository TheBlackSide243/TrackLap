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
        case .device: L("ESP32-C6 + GPS a 10–25 Hz via Bluetooth: tempi precisi al centesimo.")
        case .phone: L("Circa 1 Hz: va bene per provare e per segnare la linea a piedi.")
        case .demo: L("Un'auto simulata gira sulla pista scelta: prova tutto senza hardware.")
        }
    }
}

enum AppTab: Hashable { case live, tracks, sessions, device }

@Observable
final class AppModel {
    var tab: AppTab = .live
    let tracks = TrackStore()
    let sessions = SessionStore()
    let engine = LapEngine()
    let ble = BLEManager()
    let phone = PhoneGPS()
    let demo = DemoDriver()

    private(set) var source: SourceKind = .demo
    private(set) var selectedTrackID: UUID? = nil
    private(set) var isRunning = false
    private(set) var gpsRate: Double = 0
    private(set) var lastFixWall: Date? = nil
    private(set) var currentSessionID: UUID? = nil
    private(set) var minLapTime: Double = 20
    private(set) var deltaScale: Double = 2
    private(set) var units: Units = Units.current

    @ObservationIgnored private var session: Session? = nil
    @ObservationIgnored private var recentT: [Double] = []

    var selectedTrack: Track? { tracks.track(selectedTrackID) }
    var canStart: Bool { selectedTrack?.isReady == true }

    init() {
        let d = UserDefaults.standard
        source = SourceKind(rawValue: d.string(forKey: "source") ?? "") ?? .demo
        if let v = d.object(forKey: "deltaScale") as? Double { deltaScale = v }
        if let v = d.object(forKey: "minLapTime") as? Double { minLapTime = v }
        if let s = d.string(forKey: "track"), let id = UUID(uuidString: s), tracks.track(id) != nil {
            selectedTrackID = id
        } else {
            selectedTrackID = tracks.tracks.first?.id
        }
        engine.minLapTime = minLapTime
        engine.load(track: selectedTrack)

        ble.onSample = { [weak self] s in self?.receive(s, from: .device) }
        phone.onSample = { [weak self] s in self?.receive(s, from: .phone) }
        demo.onSample = { [weak self] s in self?.receive(s, from: .demo) }
        ble.onConnected = { [weak self] in
            guard let self, let t = self.selectedTrack else { return }
            self.ble.send(track: t)
        }
        engine.onLap = { [weak self] lap in self?.record(lap) }
        activate(source)
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
        case .demo: demo.stop()
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
    }

    // MARK: - Tracks

    func select(track id: UUID) {
        if isRunning { stop() }
        selectedTrackID = id
        UserDefaults.standard.set(id.uuidString, forKey: "track")
        engine.load(track: selectedTrack)
        if let t = selectedTrack { ble.send(track: t) }
    }

    func save(track t: Track) {
        tracks.upsert(t)
        if t.id == selectedTrackID && !isRunning {
            engine.load(track: t)
            ble.send(track: t)
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
        engine.load(track: track)
        let s = Session(trackID: track.id, trackName: track.name, date: Date(),
                        source: source.title, sectorCount: track.sectorCount)
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
        session?.laps.append(lap)
        // Saved after every lap, so nothing is lost if the app is closed mid-session.
        if let s = session { sessions.save(s) }
    }

    // MARK: - Settings

    func setUnits(_ u: Units) {
        units = u
        UserDefaults.standard.set(u.rawValue, forKey: Units.key)
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
