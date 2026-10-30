import Foundation

/// The TrackLap server (server/ in the repository, a Cloudflare Worker): new live groups and the
/// online leaderboards. `-server <url>` on the command line points the app at another one.
enum Server {
    static var base: URL {
        URL(string: UserDefaults.standard.string(forKey: "server") ?? "https://tracklap.tbsgaming.win")!
    }

    enum Failure: LocalizedError {
        case offline, refused

        var errorDescription: String? {
            switch self {
            case .offline: L("Il server di TrackLap non risponde: controlla la connessione e riprova.")
            case .refused: L("Il server ha rifiutato la richiesta.")
            }
        }
    }

    /// A new group: its five-letter code.
    static func createGroup() async throws -> String {
        var req = URLRequest(url: base.appendingPathComponent("v1/rooms"))
        req.httpMethod = "POST"
        struct Created: Decodable { var code: String }
        return try await send(req, as: Created.self).code
    }

    static func groupURL(_ code: String) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("v1/rooms/\(code)/ws"), resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        return c.url!
    }

    /// The leaderboard of a track, found by its start line and the length of a lap.
    static func board(for track: Track, length: Double?, driver: UUID) async throws -> Leaderboard {
        guard let start = track.start else { return Leaderboard(track: nil, laps: []) }
        var c = URLComponents(url: base.appendingPathComponent("v1/boards"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.6f", start.mid.lat)),
            URLQueryItem(name: "lon", value: String(format: "%.6f", start.mid.lon)),
            URLQueryItem(name: "len", value: String(Int(length ?? 0))),
        ]
        var req = URLRequest(url: c.url!)
        req.setValue(driver.uuidString, forHTTPHeaderField: "X-TrackLap-Driver")
        return try await send(req, as: Leaderboard.self)
    }

    /// A lap for the leaderboard: the server keeps it if it is your best there with that GPS.
    @discardableResult
    static func submit(_ lap: Lap, source: SourceKind, track: Track, profile: DriverProfile) async throws -> Submitted {
        guard let start = track.start, source != .demo else { throw Failure.refused }
        struct Body: Encodable {
            struct T: Encodable { var name: String; var lat: Double; var lon: Double }
            var name, vehicle, source: String
            var time, distance: Double
            var sectors: [Double]
            var date: Double
            var track: T
        }
        let body = Body(name: profile.displayName, vehicle: profile.displayVehicle, source: source.rawValue,
                        time: lap.time, distance: lap.distance, sectors: lap.sectors,
                        date: (lap.startedAt.timeIntervalSince1970 * 1000).rounded(),
                        track: .init(name: track.name, lat: start.mid.lat, lon: start.mid.lon))
        var req = URLRequest(url: base.appendingPathComponent("v1/laps"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(profile.id.uuidString, forHTTPHeaderField: "X-TrackLap-Driver")
        req.httpBody = try JSONEncoder().encode(body)
        return try await send(req, as: Submitted.self)
    }

    private static func send<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        var req = req
        req.timeoutInterval = 15
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure.offline
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let value = try? JSONDecoder().decode(T.self, from: data) else { throw Failure.refused }
        return value
    }
}

struct Leaderboard: Decodable {
    struct BoardTrack: Decodable {
        var id: String
        var name: String
    }

    struct Entry: Decodable, Identifiable {
        var rank: Int
        var name: String
        var vehicle: String
        var source: String
        var time: Double
        /// Milliseconds since 1970.
        var date: Double
        var mine: Bool

        var id: String { source + String(rank) }
        var day: Date { Date(timeIntervalSince1970: date / 1000) }
        var kind: SourceKind? { SourceKind(rawValue: source) }
    }

    var track: BoardTrack?
    var laps: [Entry]
}

struct Submitted: Decodable {
    var rank: Int
    var of: Int
}
