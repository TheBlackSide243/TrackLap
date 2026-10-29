import Foundation

struct TrackCandidate: Identifiable, Hashable {
    enum Kind: String { case circuit, karting, other }

    let id: String
    let name: String
    let kind: Kind
    let center: Coord
    var distanceKm: Double? = nil
    /// How far from the centre to look for the raceway ways.
    var radius: Double = 2500

    var icon: String { kind == .karting ? "flag.2.crossed.fill" : "flag.checkered" }

    var subtitle: String {
        let k: String
        switch kind {
        case .circuit: k = "Autodromo"
        case .karting: k = "Kartodromo"
        case .other: k = "Pista"
        }
        guard let distanceKm else { return k }
        return k + " · " + (distanceKm < 10 ? String(format: "%.1f km", distanceKm) : "\(Int(distanceKm)) km")
    }
}

enum OverpassError: LocalizedError {
    case busy

    var errorDescription: String? { "OpenStreetMap non risponde in questo momento: riprova tra poco." }
}

/// Track search and layouts from OpenStreetMap, through the public Overpass API.
enum Overpass {
    struct Response: Decodable { let elements: [Element] }

    struct Element: Decodable {
        let type: String
        let id: Int64
        let lat: Double?
        let lon: Double?
        let center: Point?
        let tags: [String: String]?
        let geometry: [Point?]?
    }

    struct Point: Decodable {
        let lat: Double
        let lon: Double
    }

    private static let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.private.coffee/api/interpreter")!,
    ]

    private static let formSafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func run(_ query: String) async throws -> [Element] {
        let body = "data=" + (query.addingPercentEncoding(withAllowedCharacters: formSafe) ?? "")
        var lastError: Error = OverpassError.busy
        for url in endpoints {
            var req = URLRequest(url: url, timeoutInterval: 35)
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.setValue("TrackLap/0.1 (iOS lap timer)", forHTTPHeaderField: "User-Agent")
            req.httpBody = Data(body.utf8)
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                    lastError = OverpassError.busy
                    continue
                }
                return try JSONDecoder().decode(Response.self, from: data).elements
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func search(name: String) async throws -> [TrackCandidate] {
        let q = sanitize(name)
        guard !q.isEmpty else { return [] }
        let query = """
        [out:json][timeout:25];
        area["ISO3166-1"="IT"][admin_level=2]->.it;
        (
          nwr["sport"~"motor|karting|motocross"]["name"~"\(q)",i](area.it);
          way["highway"="raceway"]["name"~"\(q)",i](area.it);
        );
        out tags center 40;
        """
        return candidates(try await run(query), near: nil)
    }

    static func nearby(_ c: Coord, radiusKm: Double = 60) async throws -> [TrackCandidate] {
        let r = Int(radiusKm * 1000)
        let query = """
        [out:json][timeout:25];
        (
          nwr["sport"~"motor|karting"]["name"](around:\(r),\(c.lat),\(c.lon));
          way["highway"="raceway"]["name"](around:\(r),\(c.lat),\(c.lon));
        );
        out tags center 60;
        """
        return candidates(try await run(query), near: c)
    }

    /// The raceway ways around a point, longest first.
    static func outline(around c: Coord, radius: Double) async throws -> [[Coord]] {
        let query = """
        [out:json][timeout:25];
        way["highway"="raceway"](around:\(Int(radius)),\(c.lat),\(c.lon));
        out geom;
        """
        let ways = try await run(query).compactMap { e -> [Coord]? in
            let pts = (e.geometry ?? []).compactMap { $0.map { Coord($0.lat, $0.lon) } }
            return pts.count >= 2 ? pts : nil
        }
        return ways.sorted { Geo.length($0) > Geo.length($1) }
    }

    private static func candidates(_ elements: [Element], near: Coord?) -> [TrackCandidate] {
        var seen = Set<String>()
        var out: [TrackCandidate] = []
        for e in elements {
            guard let name = e.tags?["name"], !name.isEmpty, !seen.contains(name.lowercased()) else { continue }
            let center: Coord
            if let c = e.center {
                center = Coord(c.lat, c.lon)
            } else if let lat = e.lat, let lon = e.lon {
                center = Coord(lat, lon)
            } else {
                continue
            }
            seen.insert(name.lowercased())
            let sport = e.tags?["sport"] ?? ""
            let kind: TrackCandidate.Kind = sport.contains("karting") ? .karting
                : (sport.contains("motor") || e.tags?["highway"] == "raceway") ? .circuit : .other
            var cand = TrackCandidate(id: "\(e.type)/\(e.id)", name: name, kind: kind, center: center,
                                      radius: kind == .karting ? 700 : 2500)
            if let near { cand.distanceKm = Geo.distance(near, center) / 1000 }
            out.append(cand)
        }
        if near != nil { out.sort { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) } }
        return out
    }

    /// Keeps the name usable inside an Overpass regex string: anything unusual matches any character.
    private static func sanitize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        return String(trimmed.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "." })
    }
}

/// Quick picks: the best-known Italian circuits, downloaded from OpenStreetMap when tapped.
enum ItalianCircuits {
    static let all: [TrackCandidate] = [
        pick("monza", "Autodromo Nazionale Monza", 45.6190, 9.2840),
        pick("mugello", "Mugello Circuit", 43.9975, 11.3719),
        pick("imola", "Autodromo Enzo e Dino Ferrari", 44.3439, 11.7167),
        pick("misano", "Misano World Circuit", 43.9614, 12.6850),
        pick("vallelunga", "Autodromo di Vallelunga", 42.1597, 12.3697),
        pick("varano", "Autodromo Riccardo Paletti", 44.6807, 10.0215),
        pick("franciacorta", "Autodromo di Franciacorta", 45.5139, 9.9600),
        pick("adria", "Adria International Raceway", 45.0447, 12.1470),
        pick("magione", "Autodromo dell'Umbria", 43.1340, 12.2280),
        pick("cremona", "Cremona Circuit", 45.0850, 10.3120),
        pick("modena", "Autodromo di Modena", 44.6390, 10.8350),
        pick("pergusa", "Autodromo di Pergusa", 37.5160, 14.3050),
        TrackCandidate(id: "it-lonato", name: "South Garda Karting", kind: .karting,
                       center: Coord(45.4436, 10.4889), radius: 1500),
    ]

    private static func pick(_ id: String, _ name: String, _ lat: Double, _ lon: Double) -> TrackCandidate {
        TrackCandidate(id: "it-" + id, name: name, kind: .circuit, center: Coord(lat, lon), radius: 3000)
    }
}
