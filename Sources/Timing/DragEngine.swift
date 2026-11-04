import Foundation
import Observation

/// A measure just done, for the banner, the voice and the ESP32.
struct DragEvent: Identifiable, Equatable {
    let id = UUID()
    let result: DragResult
    let measure: DragMeasure
    /// The best ever for this measure (the first one is, too).
    let isBest: Bool
    /// Better than an earlier best.
    let isRecord: Bool

    static func == (l: DragEvent, r: DragEvent) -> Bool { l.id == r.id }
}

/// Drag timing from a stream of fixes, the way a performance meter does it: stop, and the run
/// starts by itself when the car moves off; it ends when the car stops again or stops accelerating.
/// Times come from the GPS speed (Doppler, far steadier than positions) and the distance from
/// integrating it, each threshold interpolated between the two fixes around it. While moving, an
/// overtake (80–120) or a stop from 100 is a rolling run of its own.
@Observable
final class DragEngine {
    enum Phase { case moving, ready, running }

    private(set) var phase: Phase = .moving
    private(set) var speed: Double = 0
    /// m/s² over the last half second.
    private(set) var accel: Double = 0
    /// Metres since the launch of the run in progress.
    private(set) var distance: Double = 0
    /// The run in progress, then the last one until the next begins.
    private(set) var run: DragRun? = nil
    private(set) var inProgress = false
    /// When the run in progress started, for the clock between fixes.
    private(set) var startWall: Date? = nil
    private(set) var lastEvent: DragEvent? = nil

    /// The best time of each measure in earlier runs (the shortest distance for braking): what
    /// makes a result purple.
    var bests: [String: Double] = [:]
    /// Standing times count from when the car has moved a foot, like on a drag strip.
    var rollout = false
    var source = SourceKind.demo.rawValue
    var vehicle = ""
    /// The car of your garage the run is driven with.
    var carID: UUID? = nil

    @ObservationIgnored var onEvent: ((DragEvent) -> Void)? = nil
    @ObservationIgnored var onFinish: ((DragRun) -> Void)? = nil
    @ObservationIgnored var onPhase: ((Phase) -> Void)? = nil

    /// m/s: slower than this the car is stopped; a run starts above `launchSpeed` and counts once
    /// it reaches `confirmSpeed`, so creeping forward at a light is not one.
    static let stillSpeed = 0.5
    static let launchSpeed = 0.8
    static let confirmSpeed = 3.0
    static let rolloutDistance = 0.3048

    private struct Fix {
        var t: Double
        var v: Double
        var alt: Double?
        var coord: Coord
        var wall: Date
    }

    private struct Mark {
        var t: Double
        var d: Double
        var alt: Double?
    }

    /// The run being timed.
    private final class Live {
        let id = UUID()
        let standing: Bool
        let t0: Double
        let wall: Date
        let start: Coord
        let rollout: Bool
        let measures = DragMeasure.all()
        var confirmed: Bool
        /// Where standing measures count from: the launch, or the end of the rollout.
        var zero: Mark? = nil
        var d = 0.0
        var done: Set<String> = []
        /// A lower speed crossed, waiting for the upper one.
        var rolling: [String: Mark] = [:]
        /// A speed crossed slowing down, waiting for the stop.
        var braking: [String: Mark] = [:]
        var results: [DragResult] = []
        var trace: [DragPoint] = []
        var maxSpeed = 0.0
        var peakG = 0.0
        var lastActivity: Double
        var lastT: Double
        var fixes = 1

        init(standing: Bool, t0: Double, wall: Date, start: Coord, rollout: Bool) {
            self.standing = standing
            self.t0 = t0
            self.wall = wall
            self.start = start
            self.rollout = rollout
            confirmed = !standing
            lastActivity = t0
            lastT = t0
        }

        var counts: Bool { confirmed && (standing || !results.isEmpty) }
    }

    @ObservationIgnored private var prev: Fix? = nil
    @ObservationIgnored private var recent: [Fix] = []
    @ObservationIgnored private var stillSince: Double? = nil
    @ObservationIgnored private var live: Live? = nil
    @ObservationIgnored private var shownBefore: DragRun? = nil

    func reset() {
        live = nil
        prev = nil
        recent = []
        stillSince = nil
        inProgress = false
        startWall = nil
        distance = 0
        accel = 0
        speed = 0
        setPhase(.moving)
    }

    /// Puts a finished run on screen, as if just driven (the last one saved, or none).
    func show(_ r: DragRun?) {
        run = r
    }

    func ingest(_ s: Sample) {
        let f = Fix(t: s.t, v: max(0, s.speed), alt: s.alt, coord: s.coord, wall: s.wall)
        speed = f.v
        guard let p = prev, f.t > p.t else {
            if prev == nil { prev = f }
            return
        }
        prev = f
        let dt = f.t - p.t
        if dt > 2 {
            // The signal was lost: nothing is interpolated across the gap.
            finish()
            stillSince = nil
            recent = [f]
            setPhase(.moving)
            return
        }
        recent.append(f)
        recent.removeAll { f.t - $0.t > 3 }
        accel = acceleration()

        if let r = live { advance(r, p, f, dt) }
        if live == nil {
            if phase == .ready && f.v >= Self.launchSpeed {
                launch(p, f, dt)
            } else if phase == .moving {
                rollingStart(p, f, dt)
            }
        }

        if f.v < Self.stillSpeed {
            if stillSince == nil { stillSince = f.t }
            // A second still, give or take a fix of the iPhone's.
            if live == nil, let s = stillSince, f.t - s >= 0.9 { setPhase(.ready) }
        } else {
            stillSince = nil
            if live == nil && (phase != .ready || f.v >= Self.launchSpeed) { setPhase(.moving) }
        }
    }

    // MARK: - Runs

    private func launch(_ p: Fix, _ f: Fix, _ dt: Double) {
        // Back to the moment the car moved off: the line through the speeds since it was last still
        // (one pair of fixes is too noisy at 25 Hz), down to zero; not before it was last still.
        let still = recent.last { $0.v <= 0.1 && $0.t <= p.t }?.t
        let moving = recent.filter { $0.t > (still ?? -.infinity) && $0.v > 0.1 }
        var guess = f.t - dt * f.v / max(f.v - p.v, 0.01)
        if moving.count >= 2 {
            let n = Double(moving.count)
            let tm = moving.map(\.t).reduce(0, +) / n
            let vm = moving.map(\.v).reduce(0, +) / n
            let num = moving.map { ($0.t - tm) * ($0.v - vm) }.reduce(0, +)
            let den = moving.map { ($0.t - tm) * ($0.t - tm) }.reduce(0, +)
            if den > 0 && num / den > 0.5 { guess = tm - vm / (num / den) }
        }
        let t0 = min(f.t, max(max(still ?? p.t - dt, f.t - max(2 * dt, 0.5)), guess))
        let r = Live(standing: true, t0: t0, wall: f.wall.addingTimeInterval(t0 - f.t), start: p.coord, rollout: rollout)
        r.d = f.v / 2 * (f.t - t0)
        r.lastT = f.t
        r.maxSpeed = f.v
        r.trace = [DragPoint(t: 0, d: 0, v: 0), DragPoint(t: f.t - t0, d: r.d, v: f.v)]
        if !rollout {
            r.zero = Mark(t: t0, d: 0, alt: p.alt ?? f.alt)
        } else if r.d >= Self.rolloutDistance {
            // At a steady acceleration the distance grows with the square of the time.
            r.zero = Mark(t: t0 + (f.t - t0) * (Self.rolloutDistance / r.d).squareRoot(), d: Self.rolloutDistance, alt: f.alt)
        }
        live = r
        distance = r.d
        if f.v >= Self.confirmSpeed { confirm(r) }
    }

    private func confirm(_ r: Live) {
        r.confirmed = true
        shownBefore = run
        inProgress = true
        startWall = r.wall
        publish(r)
        setPhase(.running)
    }

    /// While moving: crossing the lower speed of an overtake, or slowing through the speed a stop is
    /// timed from, starts a rolling run, with the fixes of the last two seconds before it.
    private func rollingStart(_ p: Fix, _ f: Fix, _ dt: Double) {
        let starts = DragMeasure.all().contains { m in
            (m.kind == .speed && m.from > 0 && p.v < m.from && f.v >= m.from)
                || (m.kind == .braking && p.v > m.from && f.v <= m.from)
        }
        guard starts else { return }
        let seed = recent.filter { $0.t <= p.t && f.t - $0.t <= 2 }
        guard let first = seed.first else { return }
        let r = Live(standing: false, t0: first.t, wall: first.wall, start: first.coord, rollout: false)
        for (i, x) in seed.enumerated() {
            if i > 0 { r.d += (seed[i - 1].v + x.v) / 2 * (x.t - seed[i - 1].t) }
            r.trace.append(DragPoint(t: x.t - first.t, d: r.d, v: x.v))
            r.maxSpeed = max(r.maxSpeed, x.v)
        }
        r.fixes = seed.count
        r.lastT = p.t
        r.lastActivity = f.t
        live = r
        advance(r, p, f, dt)
    }

    private func advance(_ r: Live, _ p: Fix, _ f: Fix, _ dt: Double) {
        let pd = r.d
        r.d += (p.v + f.v) / 2 * dt
        r.lastT = f.t
        r.fixes += 1
        r.maxSpeed = max(r.maxSpeed, f.v)
        r.trace.append(DragPoint(t: f.t - r.t0, d: r.d, v: f.v))
        if r.confirmed { r.peakG = max(r.peakG, accel / 9.80665) }
        if accel > 0.5 { r.lastActivity = f.t }
        distance = r.d

        // Time, speed, distance and altitude a fraction u of the way from p to f.
        func at(_ u: Double) -> (t: Double, v: Double, d: Double, alt: Double?) {
            let u = min(1, max(0, u))
            let v = p.v + (f.v - p.v) * u
            let alt = p.alt.flatMap { a in f.alt.map { a + ($0 - a) * u } }
            return (p.t + dt * u, v, pd + (p.v + v) / 2 * dt * u, alt)
        }
        func speedCrossing(_ x: Double) -> (t: Double, v: Double, d: Double, alt: Double?) {
            at(f.v == p.v ? 1 : (x - p.v) / (f.v - p.v))
        }

        if r.standing && !r.confirmed {
            if f.v >= Self.confirmSpeed {
                confirm(r)
            } else if f.v < Self.stillSpeed * 0.6 || f.t - r.t0 > 4 {
                // Creeping forward, not a launch: still ready if it stopped, else wait for a stop.
                live = nil
                distance = 0
                if f.v >= Self.stillSpeed * 0.6 { setPhase(.moving) }
                return
            }
        }
        if r.standing && r.zero == nil && r.d >= Self.rolloutDistance {
            let x = at((Self.rolloutDistance - pd) / max(r.d - pd, 1e-6))
            r.zero = Mark(t: x.t, d: Self.rolloutDistance, alt: x.alt)
        }

        for m in r.measures where !r.done.contains(m.name) {
            switch m.kind {
            case .speed where m.from == 0:
                guard r.standing, let z = r.zero, p.v < m.to, f.v >= m.to else { continue }
                let x = speedCrossing(m.to)
                add(r, m, time: x.t - z.t, speed: m.to, distance: x.d - z.d, slope: slope(z.alt, x.alt, x.d - z.d), end: x.t)
            case .speed:
                if p.v < m.from && f.v >= m.from {
                    let x = speedCrossing(m.from)
                    r.rolling[m.name] = Mark(t: x.t, d: x.d, alt: x.alt)
                    r.lastActivity = f.t
                } else if f.v < m.from {
                    r.rolling[m.name] = nil
                }
                guard let s = r.rolling[m.name] else { continue }
                if p.v < m.to && f.v >= m.to {
                    let x = speedCrossing(m.to)
                    r.rolling[m.name] = nil
                    add(r, m, time: x.t - s.t, speed: m.to, distance: x.d - s.d, slope: slope(s.alt, x.alt, x.d - s.d), end: x.t)
                } else if f.t - s.t > 30 {
                    r.rolling[m.name] = nil
                }
            case .distance:
                guard r.standing, let z = r.zero, pd - z.d < m.to, r.d - z.d >= m.to else { continue }
                let x = at((m.to + z.d - pd) / max(r.d - pd, 1e-6))
                add(r, m, time: x.t - z.t, speed: x.v, distance: m.to, slope: slope(z.alt, x.alt, m.to), end: x.t)
            case .braking:
                if p.v > m.from && f.v <= m.from {
                    let x = speedCrossing(m.from)
                    r.braking[m.name] = Mark(t: x.t, d: x.d, alt: x.alt)
                    r.lastActivity = f.t
                } else if f.v > m.from {
                    r.braking[m.name] = nil
                }
                guard let s = r.braking[m.name] else { continue }
                if f.v < Self.stillSpeed {
                    // On to zero at the deceleration between the two fixes.
                    let tStop = f.t + min(dt, f.v * dt / max(p.v - f.v, 0.01))
                    let dStop = r.d + f.v / 2 * (tStop - f.t)
                    r.braking[m.name] = nil
                    if tStop - s.t < 15 {
                        add(r, m, time: tStop - s.t, speed: 0, distance: dStop - s.d, slope: slope(s.alt, f.alt, dStop - s.d), end: tStop)
                    }
                } else if f.t - s.t > 15 {
                    // Coasting down, not braking.
                    r.braking[m.name] = nil
                }
            }
        }

        if r.confirmed && f.v < Self.stillSpeed {
            finish()
        } else if f.t - r.t0 > 120 {
            finish()
        } else if r.confirmed && r.braking.isEmpty && f.t - r.lastActivity > 6 {
            finish()
        }
    }

    private func add(_ r: Live, _ m: DragMeasure, time: Double, speed: Double, distance: Double, slope: Double?, end: Double) {
        guard time > 0 else { return }
        let result = DragResult(name: m.name, kind: m.kind, time: time, speed: speed, distance: distance,
                                slope: slope, at: end - r.t0)
        r.done.insert(m.name)
        r.results.append(result)
        r.lastActivity = max(r.lastActivity, end)
        let value = m.kind == .braking ? distance : time
        let earlier = bests[m.name]
        let isBest = earlier.map { value < $0 } ?? true
        if isBest { bests[m.name] = value }
        if !r.standing && r.results.count == 1 {
            // A rolling run shows up with its first result.
            shownBefore = run
            inProgress = true
            startWall = r.wall
            setPhase(.running)
        }
        publish(r)
        let e = DragEvent(result: result, measure: m, isBest: isBest, isRecord: isBest && earlier != nil)
        lastEvent = e
        onEvent?(e)
    }

    private func finish() {
        guard let r = live else { return }
        live = nil
        inProgress = false
        startWall = nil
        if r.counts && !r.results.isEmpty {
            let done = makeRun(r)
            run = done
            onFinish?(done)
        } else if r.counts {
            // Off and stopped again before any measure: the last run goes back on screen.
            run = shownBefore
        }
        setPhase(.moving)
    }

    private func publish(_ r: Live) {
        run = makeRun(r)
    }

    private func makeRun(_ r: Live) -> DragRun {
        let span = r.lastT - r.t0
        return DragRun(id: r.id, date: r.wall, source: source, vehicle: vehicle, standing: r.standing,
                       rollout: r.standing && r.rollout, results: r.results, trace: r.trace, maxSpeed: r.maxSpeed,
                       peakG: r.peakG, rate: span > 0 ? Double(r.fixes - 1) / span : 0, start: r.start, carID: carID)
    }

    // MARK: - Helpers

    private func setPhase(_ p: Phase) {
        guard p != phase else { return }
        phase = p
        onPhase?(p)
    }

    /// Over the last half second, or between the last two fixes when they are further apart.
    private func acceleration() -> Double {
        guard let last = recent.last, recent.count > 1 else { return 0 }
        let first = recent.last { last.t - $0.t >= 0.45 } ?? recent[0]
        return last.t > first.t ? (last.v - first.v) / (last.t - first.t) : 0
    }

    /// Rise over run in %: the altitude of a GPS is good for that only over 50 m or more.
    private func slope(_ a: Double?, _ b: Double?, _ d: Double) -> Double? {
        guard let a, let b, d >= 50 else { return nil }
        return (b - a) / d * 100
    }
}
