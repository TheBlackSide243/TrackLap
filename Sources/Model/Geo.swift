import Foundation
import CoreLocation

struct Coord: Codable, Hashable {
    var lat: Double
    var lon: Double

    init(_ lat: Double, _ lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ c: CLLocationCoordinate2D) {
        self.init(c.latitude, c.longitude)
    }

    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

typealias Vec = SIMD2<Double>

extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: Vec {
        let l = length
        return l > 0 ? self / l : self
    }
    var perpendicular: Vec { Vec(-y, x) }
    func dot(_ o: Vec) -> Double { x * o.x + y * o.y }
    func cross(_ o: Vec) -> Double { x * o.y - y * o.x }
}

/// Flat east/north projection in metres around an origin: a few millimetres of error across a race track.
struct LocalFrame {
    let origin: Coord
    let mPerDegLat: Double
    let mPerDegLon: Double

    init(origin: Coord) {
        self.origin = origin
        let phi = origin.lat * .pi / 180
        mPerDegLat = 111_132.92 - 559.82 * cos(2 * phi) + 1.175 * cos(4 * phi)
        mPerDegLon = 111_412.84 * cos(phi) - 93.5 * cos(3 * phi)
    }

    func xy(_ c: Coord) -> Vec {
        Vec((c.lon - origin.lon) * mPerDegLon, (c.lat - origin.lat) * mPerDegLat)
    }

    func coord(_ p: Vec) -> Coord {
        Coord(origin.lat + p.y / mPerDegLat, origin.lon + p.x / mPerDegLon)
    }
}

enum Geo {
    static func distance(_ a: Coord, _ b: Coord) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let la1 = a.lat * .pi / 180
        let la2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, h.squareRoot()))
    }

    static func length(_ way: [Coord]) -> Double {
        guard way.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<way.count { total += distance(way[i - 1], way[i]) }
        return total
    }

    /// Where the step p→q crosses the segment a–b, as a fraction of the step (0..<1), or nil.
    static func intersect(_ p: Vec, _ q: Vec, _ a: Vec, _ b: Vec) -> Double? {
        let r = q - p
        let s = b - a
        let den = r.cross(s)
        if abs(den) < 1e-12 { return nil }
        let ap = a - p
        let u = ap.cross(s) / den
        let v = ap.cross(r) / den
        return (u >= 0 && u < 1 && v >= 0 && v <= 1) ? u : nil
    }
}

/// A latitude/longitude rectangle: a circuit's area on OpenStreetMap, or the box to search in.
struct GeoBox: Codable, Hashable {
    var minLat: Double
    var minLon: Double
    var maxLat: Double
    var maxLon: Double

    init(_ minLat: Double, _ minLon: Double, _ maxLat: Double, _ maxLon: Double) {
        self.minLat = minLat
        self.minLon = minLon
        self.maxLat = maxLat
        self.maxLon = maxLon
    }

    init(around c: Coord, meters: Double) {
        let dLat = meters / 111_320
        let dLon = meters / (111_320 * max(0.2, cos(c.lat * .pi / 180)))
        self.init(c.lat - dLat, c.lon - dLon, c.lat + dLat, c.lon + dLon)
    }

    var center: Coord { Coord((minLat + maxLat) / 2, (minLon + maxLon) / 2) }

    /// In square degrees, which is what the OpenStreetMap API limits.
    var area: Double { (maxLat - minLat) * (maxLon - minLon) }

    func padded(meters: Double) -> GeoBox {
        let dLat = meters / 111_320
        let dLon = meters / (111_320 * max(0.2, cos(center.lat * .pi / 180)))
        return GeoBox(minLat - dLat, minLon - dLon, maxLat + dLat, maxLon + dLon)
    }

    func contains(_ c: Coord) -> Bool {
        c.lat >= minLat && c.lat <= maxLat && c.lon >= minLon && c.lon <= maxLon
    }
}
