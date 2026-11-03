import Foundation

/// What a drag run measures: the time from one speed to another (from a standstill, or rolling),
/// the time over a distance from a standstill with the speed at its end, or the time and the
/// distance to stop from a speed.
struct DragMeasure: Hashable, Identifiable {
    enum Kind: String, Codable { case speed, distance, braking }

    let kind: Kind
    /// m/s: where a speed or a braking measure begins (0 = from a standstill).
    let from: Double
    /// m/s where a speed measure ends, metres for a distance, 0 for braking.
    let to: Double
    /// "0–100 km/h", "1/4 mi": what it is called everywhere, and the key of its records.
    let name: String
    /// The same in plain ASCII, for the ESP32's screen.
    let short: String
    /// The few that are read out and shown on the ESP32: 0–100 (0–60 mph), the quarter mile, braking.
    let headline: Bool

    var id: String { name }
    /// Timed from the launch, so only in a run from a standstill.
    var standing: Bool { kind == .distance || (kind == .speed && from == 0) }

    private static let kmh = 1 / 3.6
    private static let mph = 0.44704

    /// The measures of a run in the units of the settings.
    static func all(_ units: Units = .current) -> [DragMeasure] {
        let metric = units == .metric
        let f = metric ? kmh : mph
        let unit = metric ? "km/h" : "mph"
        let first = metric ? 100.0 : 60.0
        func speed(_ a: Double, _ b: Double) -> DragMeasure {
            DragMeasure(kind: .speed, from: a * f, to: b * f, name: "\(Int(a))–\(Int(b)) \(unit)",
                        short: "\(Int(a))-\(Int(b))", headline: a == 0 && b == first)
        }
        func distance(_ m: Double, _ name: String, _ short: String, headline: Bool = false) -> DragMeasure {
            DragMeasure(kind: .distance, from: 0, to: m, name: name, short: short, headline: headline)
        }
        let speeds = metric ? [(0.0, 50.0), (0, 100), (0, 150), (0, 200), (80, 120), (100, 200)]
            : [(0.0, 30.0), (0, 60), (0, 100), (0, 130), (50, 70), (60, 130)]
        return speeds.map(speed) + [
            distance(18.288, "60 ft", "60FT"),
            distance(201.168, "1/8 mi", "1/8MI"),
            distance(402.336, "1/4 mi", "1/4MI", headline: true),
            metric ? distance(1000, "1000 m", "1000M") : distance(804.672, "1/2 mi", "1/2MI"),
            DragMeasure(kind: .braking, from: first * f, to: 0, name: "\(Int(first))–0 \(unit)",
                        short: "\(Int(first))-0", headline: true),
        ]
    }
}

/// One measure done in a run.
struct DragResult: Codable, Hashable, Identifiable {
    var name: String
    var kind: DragMeasure.Kind
    /// Seconds.
    var time: Double
    /// m/s at the end: the trap speed of a distance.
    var speed: Double
    /// Metres covered: the stopping distance of a braking measure.
    var distance: Double
    /// Rise over the distance in %, when the GPS gives the altitude and the distance is long enough.
    var slope: Double?
    /// Seconds into the run when it ended, for the chart.
    var at: Double

    var id: String { name }
}

struct DragPoint: Codable {
    /// Seconds since the launch (or since a rolling run began).
    var t: Double
    /// Metres since then.
    var d: Double
    /// m/s
    var v: Double
}

/// A run: from a standstill to a stop, or a rolling one (an overtake, a stop) while already moving.
struct DragRun: Codable, Identifiable {
    var id = UUID()
    var date: Date
    /// SourceKind.rawValue
    var source: String
    var vehicle: String
    var standing: Bool
    var rollout: Bool
    var results: [DragResult]
    var trace: [DragPoint]
    var maxSpeed: Double
    /// The strongest acceleration, in g.
    var peakG: Double
    /// Fixes per second.
    var rate: Double
    var start: Coord?

    var summary: DragSummary {
        DragSummary(id: id, date: date, source: source, vehicle: vehicle, standing: standing, rollout: rollout,
                    results: results, maxSpeed: maxSpeed, peakG: peakG, rate: rate)
    }

    func result(_ name: String) -> DragResult? { results.first { $0.name == name } }
}

/// What the list and the records need, kept apart so the traces load only when a run opens.
struct DragSummary: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var source: String
    var vehicle: String
    var standing: Bool
    var rollout: Bool
    var results: [DragResult]
    var maxSpeed: Double
    var peakG: Double
    var rate: Double

    func result(_ name: String) -> DragResult? { results.first { $0.name == name } }

    /// The road's slope over the longest measure that has one.
    var slope: Double? { results.filter { $0.slope != nil }.max { $0.distance < $1.distance }?.slope }

    /// The measure the list shows first: 0–100 or 0–60, else the quarter mile, else the first one done.
    var headline: DragResult? {
        let names = DragMeasure.all().filter(\.headline).map(\.name)
        return names.lazy.compactMap { n in results.first { $0.name == n } }.first ?? results.first
    }
}
