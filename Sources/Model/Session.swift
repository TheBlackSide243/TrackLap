import Foundation

struct TracePoint: Codable {
    /// Seconds since the start of the lap.
    var t: Double
    /// Metres since the start of the lap.
    var d: Double
    var lat: Double
    var lon: Double
    /// Speed in m/s.
    var v: Double
}

struct Lap: Codable, Identifiable {
    var id = UUID()
    var number: Int
    var startedAt: Date
    var time: Double
    var sectors: [Double]
    var distance: Double
    var maxSpeed: Double
    var trace: [TracePoint]
}

struct Session: Codable, Identifiable {
    var id = UUID()
    var trackID: UUID?
    var trackName: String
    var date: Date
    var source: String
    var sectorCount: Int
    var laps: [Lap] = []
    /// The car of your garage driven in this session (added in 0.8.0).
    var carID: UUID? = nil
    var carName: String? = nil
    /// The layout of the track it was driven on (TrackLayout.key, 0.8.2).
    var layout: String? = nil
    /// The car's setup, as it was that day (0.9.0).
    var setup: SessionSetup? = nil

    var best: Lap? { laps.min { $0.time < $1.time } }

    /// Best time for each sector, over the laps that recorded all of them.
    var bestSectors: [Double] {
        guard sectorCount > 0 else { return [] }
        let full = laps.filter { $0.sectors.count == sectorCount }
        guard !full.isEmpty else { return [] }
        return (0..<sectorCount).map { k in full.map { $0.sectors[k] }.min() ?? 0 }
    }

    var idealTime: Double? {
        let b = bestSectors
        return b.isEmpty ? nil : b.reduce(0, +)
    }

    var averageTime: Double? {
        laps.isEmpty ? nil : laps.map(\.time).reduce(0, +) / Double(laps.count)
    }

    var summary: SessionSummary {
        SessionSummary(id: id, trackID: trackID, trackName: trackName, date: date, source: source,
                       lapCount: laps.count, best: best?.time, ideal: idealTime, carID: carID, carName: carName,
                       layout: layout, setupID: setup?.id, setupName: setup?.name, setupWeather: setup?.weather,
                       setupVersion: setup?.version)
    }
}

/// What the session list needs, kept apart so the full traces load only when a session opens.
struct SessionSummary: Codable, Identifiable, Hashable {
    var id: UUID
    /// Missing in indexes written before 0.3.0: the store fills it in from the session file.
    var trackID: UUID?
    var trackName: String
    var date: Date
    var source: String
    var lapCount: Int
    var best: Double?
    var ideal: Double?
    var carID: UUID? = nil
    var carName: String? = nil
    var layout: String? = nil
    var setupID: UUID? = nil
    var setupName: String? = nil
    var setupWeather: SetupWeather? = nil
    var setupVersion: Int? = nil

    /// The layout's name, when it has one.
    var layoutName: String? {
        guard let layout, let name = layout.split(separator: "|", omittingEmptySubsequences: false).first, !name.isEmpty else { return nil }
        return String(name)
    }
}

extension Array where Element == TracePoint {
    /// The two points around a distance along the lap and how far between them it falls.
    private func bracket(_ d: Double) -> (a: TracePoint, b: TracePoint, f: Double)? {
        guard let first, let last else { return nil }
        if d <= first.d { return (first, first, 0) }
        if d >= last.d { return (last, last, 0) }
        var lo = 0
        var hi = count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if self[mid].d < d { lo = mid } else { hi = mid }
        }
        let a = self[lo]
        let b = self[hi]
        return (a, b, b.d > a.d ? (d - a.d) / (b.d - a.d) : 0)
    }

    /// Elapsed time at a distance along the lap, linearly interpolated.
    func time(atDistance d: Double) -> Double {
        guard let x = bracket(d) else { return 0 }
        return x.a.t + (x.b.t - x.a.t) * x.f
    }

    /// Time, position and speed at a distance along the lap.
    func point(atDistance d: Double) -> TracePoint? {
        guard let x = bracket(d) else { return nil }
        let (a, b, f) = (x.a, x.b, x.f)
        return TracePoint(t: a.t + (b.t - a.t) * f, d: d,
                          lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f,
                          v: a.v + (b.v - a.v) * f)
    }

    /// Index of the last point at or before a distance.
    func index(atDistance d: Double) -> Int {
        var lo = 0
        var hi = count - 1
        guard hi > 0, d > self[0].d else { return 0 }
        if d >= self[hi].d { return hi }
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if self[mid].d <= d { lo = mid } else { hi = mid }
        }
        return lo
    }
}

/// A lap against a reference lap, matched by the share of the lap driven: a slightly longer or
/// shorter line does not pile up as delta, and at the line the delta is the difference of the times.
struct LapComparison {
    let lap: Lap
    let ref: Lap

    /// Reference distance per metre of this lap.
    var scale: Double { lap.distance > 0 && ref.distance > 0 ? ref.distance / lap.distance : 1 }

    func delta(at d: Double) -> Double {
        lap.trace.time(atDistance: d) - ref.trace.time(atDistance: d * scale)
    }

    func refPoint(at d: Double) -> TracePoint? { ref.trace.point(atDistance: d * scale) }
}
