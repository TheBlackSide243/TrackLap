import Foundation
import Observation

/// One GPS fix, whatever its source (ESP32 over BLE, the iPhone, the demo).
struct Sample {
    /// Monotonic GPS time in seconds.
    var t: Double
    var coord: Coord
    /// m/s
    var speed: Double
    /// Degrees clockwise from north.
    var heading: Double
    /// When the fix reached the app: lets the timer tick smoothly between fixes.
    var wall = Date()
    /// UTC of the fix in seconds since 1970, when the source gives it (GPS time from the ESP32): the
    /// live group compares two cars by it.
    var utc: Double? = nil
    /// Metres above sea level, when the source gives it: the slope of a drag run.
    var alt: Double? = nil
    /// Measured by the board's accelerometer, when it has one.
    var g: GPoint? = nil
}

enum SectorState { case best, faster, slower }

struct LiveSector: Identifiable {
    let id: Int
    var time: Double? = nil
    var state: SectorState? = nil
    /// The same sector on the previous lap, shown dimmed until this lap gets there.
    var previous: Double? = nil
    var previousState: SectorState? = nil
}

struct LapEvent: Identifiable, Equatable {
    let id = UUID()
    let number: Int
    let time: Double
    let isBest: Bool
    /// Faster than every lap driven on this track in earlier sessions.
    var isRecord = false
    /// Against the best before this lap: negative is faster.
    let gap: Double?
    /// The friend whose lap you are chasing, and this lap against theirs.
    var rival: String? = nil
    var rivalGap: Double? = nil

    static func == (l: LapEvent, r: LapEvent) -> Bool { l.id == r.id }
}

/// Lap timing from a stream of fixes: the crossing of each line is interpolated between two fixes,
/// so at 10 Hz the times come out to a few hundredths. The delta compares where you are now with
/// where you were on the best lap at the same distance.
@Observable
final class LapEngine {
    private(set) var track: Track? = nil
    private(set) var laps: [Lap] = []
    /// 0 while on the out lap, before the first crossing of the start line.
    private(set) var lapNumber = 0
    private(set) var lapStartWall: Date? = nil
    private(set) var delta: Double? = nil
    private(set) var predicted: Double? = nil
    private(set) var sectors: [LiveSector] = []
    private(set) var lastEvent: LapEvent? = nil
    private(set) var speed: Double = 0
    private(set) var position: Coord? = nil
    private(set) var heading: Double = 0
    private(set) var lapDistance: Double = 0

    /// The fastest lap on this track from earlier sessions, if any.
    private(set) var record: Lap? = nil
    /// Compare with the track record instead of the best lap of this session.
    var compareWithRecord = false
    /// A friend's lap to chase: while set, the delta is against it, whatever else is faster.
    private(set) var ghost: Lap? = nil
    private(set) var ghostName: String? = nil

    var minLapTime: Double = 20
    @ObservationIgnored var onLap: ((Lap) -> Void)? = nil

    var bestLap: Lap? { laps.min { $0.time < $1.time } }
    /// The lap the delta is measured against.
    var referenceLap: Lap? {
        if let ghost { return ghost }
        guard compareWithRecord, let record else { return bestLap }
        guard let best = bestLap, best.time < record.time else { return record }
        return best
    }
    var comparesWithRecord: Bool { ghost == nil && compareWithRecord && record != nil }
    var lastLap: Lap? { laps.last }
    var isTiming: Bool { lapStartWall != nil }

    @ObservationIgnored private var frame: LocalFrame? = nil
    @ObservationIgnored private var startGate: (a: Vec, b: Vec)? = nil
    @ObservationIgnored private var splitGates: [(a: Vec, b: Vec)] = []
    @ObservationIgnored private var prev: (s: Sample, xy: Vec)? = nil
    @ObservationIgnored private var lapStartT: Double? = nil
    @ObservationIgnored private var trace: [TracePoint] = []
    @ObservationIgnored private var splits: [Int: Double] = [:]
    @ObservationIgnored private var maxSpeed: Double = 0

    func load(track: Track?) {
        self.track = track
        frame = nil
        startGate = nil
        splitGates = []
        if let track, let start = track.start {
            let f = LocalFrame(origin: start.mid)
            frame = f
            startGate = (a: f.xy(start.a), b: f.xy(start.b))
            splitGates = track.sectors.map { (a: f.xy($0.a), b: f.xy($0.b)) }
        }
        record = nil
        ghost = nil
        ghostName = nil
        reset()
    }

    /// Another layout of the same track, found from the lap just driven: its lines from now on, its
    /// record to beat, and the laps of this session on it. When the start line moves too, the timer
    /// waits for the new line before the next lap.
    func switchLayout(start: GateLine, sectors: [GateLine], record: Lap?, laps keep: [Lap]) {
        guard var t = track else { return }
        let moved = t.start.map { Geo.distance($0.mid, start.mid) > 15 } ?? true
        t.start = start
        t.sectors = sectors
        track = t
        let f = LocalFrame(origin: start.mid)
        frame = f
        startGate = (a: f.xy(start.a), b: f.xy(start.b))
        splitGates = sectors.map { (a: f.xy($0.a), b: f.xy($0.b)) }
        if let p = prev { prev = (p.s, f.xy(p.s.coord)) }
        self.record = record
        laps = keep
        splits = [:]
        if moved {
            lapStartT = nil
            lapStartWall = nil
            trace = []
            lapDistance = 0
            delta = nil
            predicted = nil
        }
        self.sectors = makeSectors(carry: [])
    }

    /// Sets the track record after the track is loaded; it lasts until another track is loaded.
    func setRecord(_ lap: Lap?) {
        record = lap
    }

    /// The friend's lap to chase on this track, nil for none; like the record, until another track.
    func setGhost(_ lap: Lap?, name: String?) {
        ghost = lap
        ghostName = lap == nil ? nil : name
    }

    func reset() {
        laps = []
        lapNumber = 0
        lapStartWall = nil
        delta = nil
        predicted = nil
        lastEvent = nil
        prev = nil
        lapStartT = nil
        trace = []
        splits = [:]
        maxSpeed = 0
        lapDistance = 0
        sectors = makeSectors(carry: [])
    }

    /// Position only, while no session is running.
    func observe(_ s: Sample) {
        speed = s.speed
        position = s.coord
        heading = s.heading
    }

    func ingest(_ s: Sample) {
        observe(s)
        guard let frame, let gate = startGate else { return }
        let xy = frame.xy(s.coord)
        let last = prev
        prev = (s, xy)
        guard let p = last else { return }
        let dt = s.t - p.s.t
        // A long gap (signal lost) is not interpolated across.
        guard dt > 0, dt < 5 else { return }
        let step = (xy - p.xy).length

        if let u = Geo.intersect(p.xy, xy, gate.a, gate.b),
           canCross(distance: lapDistance + step * u, elapsed: lapStartT.map { p.s.t + u * dt - $0 }, speed: s.speed) {
            let tc = p.s.t + u * dt
            let crossing = frame.coord(p.xy + (xy - p.xy) * u)
            if lapStartT != nil {
                checkSplits(from: p, to: (s, xy), until: u, dt: dt, step: step)
                lapDistance += step * u
                appendPoint(t: tc, coord: crossing, v: s.speed, g: s.g)
                finishLap(at: tc)
            }
            beginLap(at: tc, wall: s.wall.addingTimeInterval(tc - s.t), coord: crossing, v: s.speed, g: s.g)
            lapDistance = step * (1 - u)
            appendPoint(t: s.t, coord: s.coord, v: s.speed, g: s.g)
        } else if lapStartT != nil {
            checkSplits(from: p, to: (s, xy), until: 1, dt: dt, step: step)
            lapDistance += step
            appendPoint(t: s.t, coord: s.coord, v: s.speed, g: s.g)
        }
        updateDelta(now: s.t)
    }

    // MARK: - Laps

    private func canCross(distance: Double, elapsed: Double?, speed: Double) -> Bool {
        // The first crossing starts lap 1; GPS jitter while parked on the line must not.
        guard let elapsed else { return speed > 2 }
        return elapsed >= minLapTime && distance >= 200
    }

    private func beginLap(at t: Double, wall: Date, coord: Coord, v: Double, g: GPoint?) {
        lapNumber += 1
        lapStartT = t
        lapStartWall = wall
        lapDistance = 0
        trace = []
        splits = [:]
        maxSpeed = 0
        sectors = makeSectors(carry: sectors)
        appendPoint(t: t, coord: coord, v: v, g: g)
    }

    private func finishLap(at tc: Double) {
        guard let t0 = lapStartT, let wall = lapStartWall else { return }
        let time = tc - t0
        var times: [Double] = []
        let ordered = splits.values.sorted()
        if !splitGates.isEmpty && ordered.count == splitGates.count {
            var last = 0.0
            for e in ordered {
                times.append(e - last)
                last = e
            }
            times.append(time - last)
            setSector(times.count - 1, time: time - last)
        }
        let previousBest = bestLap?.time
        let lap = Lap(number: lapNumber, startedAt: wall, time: time, sectors: times,
                      distance: lapDistance, maxSpeed: maxSpeed, trace: trace)
        let isBest = previousBest.map { time < $0 } ?? true
        let isRecord = record.map { time < min($0.time, previousBest ?? .infinity) } ?? false
        laps.append(lap)
        lastEvent = LapEvent(number: lap.number, time: time, isBest: isBest, isRecord: isRecord,
                             gap: previousBest.map { time - $0 }, rival: ghostName, rivalGap: ghost.map { time - $0.time })
        onLap?(lap)
    }

    private func appendPoint(t: Double, coord: Coord, v: Double, g: GPoint?) {
        guard let t0 = lapStartT else { return }
        maxSpeed = max(maxSpeed, v)
        trace.append(TracePoint(t: t - t0, d: lapDistance, lat: coord.lat, lon: coord.lon, v: v,
                                glat: g?.lateral, glon: g?.longitudinal))
    }

    // MARK: - Sectors

    private func checkSplits(from p: (s: Sample, xy: Vec), to q: (s: Sample, xy: Vec), until limit: Double, dt: Double, step: Double) {
        guard let t0 = lapStartT else { return }
        for (i, g) in splitGates.enumerated() where splits[i] == nil {
            guard let u = Geo.intersect(p.xy, q.xy, g.a, g.b), u <= limit else { continue }
            let elapsed = p.s.t + u * dt - t0
            guard elapsed > 3, lapDistance + step * u > 30 else { continue }
            let before = splits.values.filter { $0 < elapsed }.max() ?? 0
            splits[i] = elapsed
            // Sectors are numbered in the order they are crossed, whatever order the lines were drawn in.
            setSector(splits.count - 1, time: elapsed - before)
        }
    }

    private func setSector(_ k: Int, time: Double) {
        guard k < sectors.count else { return }
        sectors[k].time = time
        sectors[k].state = state(for: k, time: time)
    }

    private func state(for k: Int, time: Double) -> SectorState {
        let previous = laps.compactMap { $0.sectors.count > k ? $0.sectors[k] : nil }
        guard let best = previous.min() else { return .best }
        if time <= best { return .best }
        if let last = laps.last, last.sectors.count > k, time < last.sectors[k] { return .faster }
        return .slower
    }

    private func makeSectors(carry: [LiveSector]) -> [LiveSector] {
        let n = splitGates.isEmpty ? 0 : splitGates.count + 1
        return (0..<n).map { i in
            let old = i < carry.count ? carry[i] : nil
            return LiveSector(id: i, time: nil, state: nil, previous: old?.time, previousState: old?.state)
        }
    }

    // MARK: - Delta

    private func updateDelta(now t: Double) {
        guard let t0 = lapStartT, let ref = referenceLap, ref.trace.count > 1 else {
            delta = nil
            predicted = nil
            return
        }
        let d = (t - t0) - ref.trace.time(atDistance: lapDistance)
        delta = d
        predicted = ref.time + d
    }
}
