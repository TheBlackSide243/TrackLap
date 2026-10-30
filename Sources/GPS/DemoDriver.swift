import Foundation
import Observation

/// A simulated car lapping the selected track at 10 Hz: it follows the OpenStreetMap layout when that
/// closes into a loop through the start line, otherwise a generated circuit through the line.
@Observable
final class DemoDriver {
    /// Driver pace, 1 = on the limit.
    var pace: Double = 0.97
    private(set) var isRunning = false
    @ObservationIgnored var onSample: ((Sample) -> Void)? = nil

    @ObservationIgnored private var timer: Timer? = nil
    @ObservationIgnored private var frame = LocalFrame(origin: Coord(0, 0))
    @ObservationIgnored private var path: [Vec] = []
    @ObservationIgnored private var cum: [Double] = []
    @ObservationIgnored private var vmax: [Double] = []
    @ObservationIgnored private var total: Double = 1
    @ObservationIgnored private var s: Double = 0
    @ObservationIgnored private var v: Double = 15
    @ObservationIgnored private var t: Double = 0
    @ObservationIgnored private var lapNoise: [Double] = [1]

    /// `lead` seconds of driving done at once first: the screenshot mode spreads its cars with it.
    func start(track: Track, lead: Double = 0) {
        stop()
        build(track)
        t = Date().timeIntervalSince1970
        newLapNoise()
        for _ in 0..<Int(lead * 10) { _ = advance(dt: 0.1, at: t) }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// `seconds` of driving at 10 Hz worked out at once, with GPS times from `t0`: the screenshot
    /// mode fills its sessions with it.
    func simulate(track: Track, seconds: Double, from t0: Double) -> [Sample] {
        stop()
        build(track)
        newLapNoise()
        return stride(from: t0 + 0.1, through: t0 + seconds, by: 0.1).map { advance(dt: 0.1, at: $0) }
    }

    private func tick() {
        let nowT = Date().timeIntervalSince1970
        let dt = min(0.3, max(0.01, nowT - t))
        t = nowT
        onSample?(advance(dt: dt, at: nowT))
    }

    /// Moves the car on by `dt` seconds and returns its fix at `time`.
    private func advance(dt: Double, at time: Double) -> Sample {
        let i = index(at: s)
        let section = min(lapNoise.count - 1, Int(s / total * Double(lapNoise.count)))
        let target = vmax[i] * pace * lapNoise[section]
        if target > v { v = min(target, v + 6.5 * dt) } else { v = max(target, v - 14 * dt) }
        s += v * dt
        if s >= total {
            s -= total
            newLapNoise()
        }
        let (pos, dir) = point(at: s)
        let jitter = Vec(Double.random(in: -0.3...0.3), Double.random(in: -0.3...0.3))
        let heading = (atan2(dir.x, dir.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return Sample(t: time, coord: frame.coord(pos + jitter), speed: v, heading: heading,
                      wall: Date(timeIntervalSince1970: time))
    }

    private func newLapNoise() {
        let form = Double.random(in: 0.985...1.01)
        lapNoise = (0..<6).map { _ in form * Double.random(in: 0.98...1.02) }
    }

    // MARK: - Path

    private func build(_ track: Track) {
        frame = LocalFrame(origin: track.start?.mid ?? track.center)
        var gate: (Vec, Vec)? = nil
        if let st = track.start { gate = (frame.xy(st.a), frame.xy(st.b)) }
        let raw = Self.osmLoop(track, frame: frame, gate: gate) ?? Self.syntheticLoop(through: gate)
        path = Self.resample(raw, spacing: 2)
        let n = path.count
        cum = [0]
        for i in 1..<n { cum.append(cum[i - 1] + (path[i] - path[i - 1]).length) }
        total = cum[n - 1] + (path[0] - path[n - 1]).length
        vmax = Self.speedProfile(path, spacing: 2)

        // Start 150 m before the line, so the first lap begins almost at once.
        var crossing = 0
        if let gate {
            for i in 0..<n where Geo.intersect(path[i], path[(i + 1) % n], gate.0, gate.1) != nil {
                crossing = i
                break
            }
        }
        s = (cum[crossing] - 150 + total).truncatingRemainder(dividingBy: total)
        v = vmax[index(at: s)] * 0.9
    }

    private func index(at s: Double) -> Int {
        var lo = 0
        var hi = cum.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cum[mid] <= s { lo = mid } else { hi = mid }
        }
        return cum[hi] <= s ? hi : lo
    }

    private func point(at s: Double) -> (Vec, Vec) {
        let n = path.count
        let i = index(at: s)
        let j = (i + 1) % n
        let segLen = i == n - 1 ? total - cum[i] : cum[i + 1] - cum[i]
        let f = segLen > 0 ? (s - cum[i]) / segLen : 0
        let dir = path[j] - path[i]
        return (path[i] + dir * f, dir.normalized)
    }

    /// The OpenStreetMap ways chained into one closed loop that crosses the start line, if they make one.
    static func osmLoop(_ track: Track, frame: LocalFrame, gate: (Vec, Vec)?) -> [Vec]? {
        guard let gate else { return nil }
        let ways = track.outline.filter { $0.count >= 2 }.sorted { Geo.length($0) > Geo.length($1) }
        for (i, seed) in ways.enumerated() {
            var others = ways
            others.remove(at: i)
            guard let loop = chain(seed, others) else { continue }
            let pts = loop.map { frame.xy($0) }
            for k in 1..<pts.count where Geo.intersect(pts[k - 1], pts[k], gate.0, gate.1) != nil {
                return pts
            }
        }
        return nil
    }

    private static func chain(_ seed: [Coord], _ pool: [[Coord]]) -> [Coord]? {
        var line = seed
        var pool = pool
        for _ in 0..<80 {
            if line.count > 10, let f = line.first, let l = line.last, Geo.distance(f, l) < 40, Geo.length(line) > 500 {
                return line
            }
            guard let end = line.last else { return nil }
            guard let i = pool.firstIndex(where: { Geo.distance(end, $0[0]) < 8 || Geo.distance(end, $0[$0.count - 1]) < 8 }) else {
                return nil
            }
            let w = pool.remove(at: i)
            if Geo.distance(end, w[0]) < 8 { line += w.dropFirst() } else { line += w.reversed().dropFirst() }
        }
        return nil
    }

    /// A twisty closed circuit of about 2.8 km, placed so it crosses the gate at its midpoint.
    static func syntheticLoop(through gate: (Vec, Vec)?) -> [Vec] {
        let n = 1600
        var raw: [Vec] = []
        for i in 0..<n {
            let th = 2 * Double.pi * Double(i) / Double(n)
            let r = 360 * (1 + 0.22 * sin(2 * th) + 0.12 * cos(3 * th + 0.6) + 0.07 * sin(5 * th + 1.1))
            raw.append(Vec(r * cos(th), r * sin(th)))
        }
        let p0 = raw[0]
        let t0 = (raw[1] - raw[n - 1]).normalized
        var mid = Vec(0, 0)
        var dir = Vec(0, 1)
        if let g = gate {
            mid = (g.0 + g.1) * 0.5
            dir = (g.1 - g.0).normalized.perpendicular
        }
        let ang = atan2(dir.y, dir.x) - atan2(t0.y, t0.x)
        let c = cos(ang)
        let sn = sin(ang)
        return raw.map { p in
            let q = p - p0
            return Vec(q.x * c - q.y * sn, q.x * sn + q.y * c) + mid
        }
    }

    static func resample(_ pts: [Vec], spacing: Double) -> [Vec] {
        guard pts.count > 2, let first = pts.first, let last = pts.last else { return pts }
        var closed = pts
        if (first - last).length > 0.5 { closed.append(first) }
        var out: [Vec] = [closed[0]]
        var carry = 0.0
        for i in 1..<closed.count {
            let a = closed[i - 1]
            let b = closed[i]
            let seg = (b - a).length
            guard seg > 0 else { continue }
            var pos = spacing - carry
            while pos <= seg {
                out.append(a + (b - a) * (pos / seg))
                pos += spacing
            }
            carry = seg - (pos - spacing)
        }
        if let end = out.last, (end - out[0]).length < spacing * 0.5 { out.removeLast() }
        return out
    }

    /// Cornering speed from the curvature (about 1.1 g), then acceleration and braking limits around the loop.
    static func speedProfile(_ p: [Vec], spacing ds: Double) -> [Double] {
        let n = p.count
        var v = [Double](repeating: 72, count: n)
        let k = 6
        for i in 0..<n {
            let a = p[(i - k + n) % n]
            let b = p[i]
            let c = p[(i + k) % n]
            let ab = (b - a).length
            let bc = (c - b).length
            let ca = (a - c).length
            let den = ab * bc * ca
            let curvature = den > 0 ? 2 * abs((b - a).cross(c - a)) / den : 0
            v[i] = min(72, (11.0 / max(curvature, 1e-5)).squareRoot())
        }
        for _ in 0..<2 {
            for i in 1..<(2 * n) {
                let j = i % n
                let pj = (i - 1) % n
                v[j] = min(v[j], (v[pj] * v[pj] + 2 * 6.5 * ds).squareRoot())
            }
            for i in stride(from: 2 * n - 2, through: 0, by: -1) {
                let j = i % n
                let nj = (i + 1) % n
                v[j] = min(v[j], (v[nj] * v[nj] + 2 * 13 * ds).squareRoot())
            }
        }
        return v
    }
}
