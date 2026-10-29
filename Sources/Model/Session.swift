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
        SessionSummary(id: id, trackName: trackName, date: date, source: source,
                       lapCount: laps.count, best: best?.time, ideal: idealTime)
    }
}

/// What the session list needs, kept apart so the full traces load only when a session opens.
struct SessionSummary: Codable, Identifiable, Hashable {
    var id: UUID
    var trackName: String
    var date: Date
    var source: String
    var lapCount: Int
    var best: Double?
    var ideal: Double?
}

extension Array where Element == TracePoint {
    /// Elapsed time at a distance along the lap, linearly interpolated.
    func time(atDistance d: Double) -> Double {
        guard let first, let last else { return 0 }
        if d <= first.d { return first.t }
        if d >= last.d { return last.t }
        var lo = 0
        var hi = count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if self[mid].d < d { lo = mid } else { hi = mid }
        }
        let a = self[lo]
        let b = self[hi]
        let f = b.d > a.d ? (d - a.d) / (b.d - a.d) : 0
        return a.t + (b.t - a.t) * f
    }
}
