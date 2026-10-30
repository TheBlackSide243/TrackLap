import Foundation

/// A virtual line across the track: the start/finish or an intermediate.
struct GateLine: Codable, Hashable {
    var a: Coord
    var b: Coord

    var mid: Coord { Coord((a.lat + b.lat) / 2, (a.lon + b.lon) / 2) }
    var width: Double { Geo.distance(a, b) }

    func resized(_ w: Double) -> GateLine {
        let f = LocalFrame(origin: mid)
        let dir = (f.xy(b) - f.xy(a)).normalized
        return GateLine(a: f.coord(dir * (-w / 2)), b: f.coord(dir * (w / 2)))
    }
}

struct Track: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var place: String = ""
    var center: Coord
    /// The raceway ways downloaded from OpenStreetMap, each one a polyline.
    var outline: [[Coord]] = []
    var start: GateLine? = nil
    /// Intermediate lines: n intermediates make n + 1 sectors.
    var sectors: [GateLine] = []
    var isDemo = false
    var created = Date()

    var isReady: Bool { start != nil }
    var sectorCount: Int { sectors.isEmpty ? 0 : sectors.count + 1 }
    var length: Double? { outline.map(Geo.length).max() }

    var allPoints: [Coord] {
        var pts = outline.flatMap { $0 }
        if let start { pts += [start.a, start.b] }
        for g in sectors { pts += [g.a, g.b] }
        return pts
    }
}

/// The built-in demo circuit, so the whole app can be tried without hardware.
enum DemoCircuit {
    static let center = Coord(45.1585, 8.8350)

    static func track() -> Track {
        let f = LocalFrame(origin: center)
        let pts = DemoDriver.syntheticLoop(through: nil)
        let n = pts.count
        let coords = pts.map { f.coord($0) }

        func gate(_ i: Int) -> GateLine {
            let dir = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized.perpendicular * 12
            return GateLine(a: f.coord(pts[i] - dir), b: f.coord(pts[i] + dir))
        }

        var t = Track(name: L("Circuito Demo"), place: L("Pista simulata"), center: center, outline: [coords + [coords[0]]])
        t.start = gate(0)
        t.sectors = [gate(n / 3), gate(2 * n / 3)]
        t.isDemo = true
        return t
    }
}
