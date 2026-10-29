import Foundation
import MapKit

enum TrackGeometry {
    /// A line across the track where it was tapped: perpendicular to the nearest raceway segment.
    static func gate(at tap: Coord, outline: [[Coord]], width: Double) -> GateLine? {
        let f = LocalFrame(origin: tap)
        var best: (dist: Double, p: Vec, dir: Vec)?
        for way in outline where way.count >= 2 {
            for i in 1..<way.count {
                let a = f.xy(way[i - 1])
                let b = f.xy(way[i])
                let ab = b - a
                let len2 = ab.dot(ab)
                guard len2 > 0 else { continue }
                let t = min(1, max(0, -a.dot(ab) / len2))
                let p = a + ab * t
                let dist = p.length
                if best == nil || dist < best!.dist { best = (dist, p, ab) }
            }
        }
        guard let best, best.dist < 60 else { return nil }
        let n = best.dir.normalized.perpendicular * (width / 2)
        return GateLine(a: f.coord(best.p - n), b: f.coord(best.p + n))
    }

    /// A line through a point, perpendicular to the direction of travel.
    static func gate(at c: Coord, heading: Double, width: Double) -> GateLine {
        let f = LocalFrame(origin: c)
        let h = heading * .pi / 180
        let n = Vec(sin(h), cos(h)).perpendicular * (width / 2)
        return GateLine(a: f.coord(n * -1), b: f.coord(n))
    }

    static func region(for coords: [Coord], fallback: Coord? = nil, minMeters: Double = 700) -> MKCoordinateRegion {
        guard let minLat = coords.map(\.lat).min(), let maxLat = coords.map(\.lat).max(),
              let minLon = coords.map(\.lon).min(), let maxLon = coords.map(\.lon).max() else {
            let c = fallback ?? Coord(42.5, 12.5)
            return MKCoordinateRegion(center: c.cl, latitudinalMeters: minMeters * 2, longitudinalMeters: minMeters * 2)
        }
        let center = Coord((minLat + maxLat) / 2, (minLon + maxLon) / 2)
        let f = LocalFrame(origin: center)
        let h = (maxLat - minLat) * f.mPerDegLat * 1.35
        let w = (maxLon - minLon) * f.mPerDegLon * 1.35
        return MKCoordinateRegion(center: center.cl, latitudinalMeters: max(h, minMeters), longitudinalMeters: max(w, minMeters))
    }
}
