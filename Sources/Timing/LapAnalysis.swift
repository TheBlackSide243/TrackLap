import Foundation

/// Lateral and longitudinal acceleration in g at one point of a lap.
struct GPoint {
    /// Positive when turning right.
    var lateral: Double = 0
    /// Positive when accelerating, negative when braking.
    var longitudinal: Double = 0

    var total: Double { (lateral * lateral + longitudinal * longitudinal).squareRoot() }
}

enum GForce {
    /// One value per trace point, from the GPS alone so it works with every source: the turn rate
    /// times the speed for the lateral, the change of speed for the longitudinal, each over about
    /// half a second around the point. Points it cannot work out (standing still, the ends) are zero.
    static func along(_ trace: [TracePoint]) -> [GPoint] {
        let n = trace.count
        var out = [GPoint](repeating: GPoint(), count: n)
        guard n > 4 else { return out }
        let f = LocalFrame(origin: Coord(trace[0].lat, trace[0].lon))
        let xy = trace.map { f.xy(Coord($0.lat, $0.lon)) }
        let window = 0.3
        var j = 0
        var l = 0
        for i in 0..<n {
            while j + 1 < i && trace[i].t - trace[j + 1].t >= window { j += 1 }
            l = max(l, i)
            while l + 1 < n && trace[l].t - trace[i].t < window { l += 1 }
            guard j < i, l > i else { continue }
            let a = xy[i] - xy[j]
            let b = xy[l] - xy[i]
            let span = trace[l].t - trace[j].t
            guard a.length > 0.5, b.length > 0.5, span > 0 else { continue }
            // Counter-clockwise is a left turn in the east/north frame.
            let turn = atan2(a.cross(b), a.dot(b))
            let lateral = -trace[i].v * turn / (span / 2) / 9.81
            let longitudinal = (trace[l].v - trace[j].v) / span / 9.81
            out[i] = GPoint(lateral: clamp(lateral), longitudinal: clamp(longitudinal))
        }
        return smooth(out)
    }

    private static func clamp(_ g: Double) -> Double { max(-3, min(3, g)) }

    private static func smooth(_ g: [GPoint]) -> [GPoint] {
        guard g.count > 2 else { return g }
        var out = g
        for i in 1..<(g.count - 1) {
            out[i].lateral = (g[i - 1].lateral + 2 * g[i].lateral + g[i + 1].lateral) / 4
            out[i].longitudinal = (g[i - 1].longitudinal + 2 * g[i].longitudinal + g[i + 1].longitudinal) / 4
        }
        return out
    }
}

enum Corners {
    /// The slowest point of each corner: a speed minimum over 80 m either side, with at least
    /// 3 m/s (about 11 km/h) more speed both on the way in and on the way out.
    static func apexes(_ trace: [TracePoint]) -> [TracePoint] {
        let n = trace.count
        guard n > 10 else { return [] }
        let near = 80.0
        let far = 250.0
        let drop = 3.0
        var out: [TracePoint] = []
        for i in 0..<n {
            let p = trace[i]
            var isMin = true
            var before = p.v
            var after = p.v
            var k = i - 1
            while k >= 0 && p.d - trace[k].d <= far {
                if p.d - trace[k].d <= near && trace[k].v < p.v { isMin = false; break }
                before = max(before, trace[k].v)
                k -= 1
            }
            guard isMin else { continue }
            k = i + 1
            while k < n && trace[k].d - p.d <= far {
                // Ties go to the first point, so a flat minimum gives one apex.
                if trace[k].d - p.d <= near && trace[k].v <= p.v { isMin = false; break }
                after = max(after, trace[k].v)
                k += 1
            }
            if isMin && before >= p.v + drop && after >= p.v + drop { out.append(p) }
        }
        return out
    }
}
