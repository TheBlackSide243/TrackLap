import Foundation

/// A driver you are friends with on TrackLap: friends both ways, from an invitation link.
struct Friend: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    /// Their garage's code, once they have shown a car (to friends or to everyone).
    var garage: String?
    /// Milliseconds since 1970: when you became friends.
    var since: Double?

    var sinceDate: Date? { since.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var initial: String { String(name.prefix(1)).uppercased() }
}

/// A friend as the server sends them when you open them: their best lap on every track, from the
/// online leaderboards, and a few numbers worked out from those.
struct FriendProfile: Decodable {
    struct Best: Decodable, Identifiable {
        struct BestTrack: Decodable {
            var id: String
            var name: String
            var length: Double?
        }

        var track: BestTrack
        var source: String
        var time: Double
        /// Milliseconds since 1970: the day of the lap, and of the last session on that track.
        var date: Double
        var last: Double
        var sessions: Int
        var vehicle: String
        var garage: String
        var car: String
        var rank: Int
        var of: Int
        /// "car", "motorcycle" or "scooter"; nil for laps from before 0.10.0.
        var vehicleType: String?

        enum CodingKeys: String, CodingKey {
            case track, source, time, date, last, sessions, vehicle, garage, car, rank, of
            case vehicleType = "kind"
        }

        var vehicleKind: VehicleKind? { vehicleType.flatMap(VehicleKind.init(rawValue:)) }
        var id: String { track.id + "/" + source }
        var kind: SourceKind? { SourceKind(rawValue: source) }
        var lastDay: Date { Date(timeIntervalSince1970: last / 1000) }
    }

    struct Stats: Decodable {
        var tracks: Int
        var sessions: Int
        var wins: Int
        var favourite: String?
        var last: Double?

        var lastDay: Date? { last.map { Date(timeIntervalSince1970: $0 / 1000) } }
    }

    var id: String
    var name: String
    var garage: String?
    var since: Double?
    var laps: [Best]
    var stats: Stats?
}

/// Your invitation link's code and when it stops working.
struct FriendInvite: Decodable {
    var code: String
    /// Milliseconds since 1970.
    var expires: Double

    var expiry: Date { Date(timeIntervalSince1970: expires / 1000) }
}
