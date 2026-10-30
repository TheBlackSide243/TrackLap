import Foundation

/// Name search on OpenStreetMap through Photon (komoot): answers in a fraction of a second,
/// worldwide, and forgives typos, so it can run while you type.
enum Photon {
    private struct Response: Decodable { let features: [Feature] }

    struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }

    struct Geometry: Decodable { let coordinates: [Double] }

    struct Properties: Decodable {
        let osm_type: String?
        let osm_id: Int64?
        let osm_key: String?
        let osm_value: String?
        let name: String?
        let city: String?
        let county: String?
        let state: String?
        let country: String?
        let extent: [Double]?
    }

    private static let base = URL(string: "https://photon.komoot.io/api/")!
    private static let trackTags = ["leisure:sports_centre", "leisure:track", "leisure:stadium", "highway:raceway"]
    private static let placeTags = ["place:city", "place:town", "place:village", "place:municipality"]

    /// Photon names things in English, German or French on request; otherwise in the local language.
    private static var language: String? {
        let code = Locale.current.language.languageCode?.identifier ?? ""
        return ["en", "de", "fr"].contains(code) ? code : nil
    }

    static func tracks(matching q: String, in box: GeoBox? = nil, limit: Int = 25) async throws -> [TrackCandidate] {
        var items = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: "\(limit)")]
        items += trackTags.map { URLQueryItem(name: "osm_tag", value: $0) }
        if let box {
            items.append(URLQueryItem(name: "bbox", value: "\(box.minLon),\(box.minLat),\(box.maxLon),\(box.maxLat)"))
        }
        return try await features(items).compactMap(candidate)
    }

    static func places(matching q: String) async throws -> [PlaceCandidate] {
        var items = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "limit", value: "4")]
        items += placeTags.map { URLQueryItem(name: "osm_tag", value: $0) }
        return try await features(items).compactMap { f in
            let p = f.properties
            guard let name = p.name, f.geometry.coordinates.count == 2 else { return nil }
            let detail = [p.state ?? p.county, p.country].compactMap { $0 }.joined(separator: ", ")
            return PlaceCandidate(id: "\(p.osm_type ?? "?")\(p.osm_id ?? 0)", name: name, detail: detail,
                                  center: Coord(f.geometry.coordinates[1], f.geometry.coordinates[0]))
        }
    }

    /// Venues in a box whose names carry the usual words, as a quick first answer for "near me"
    /// while the slower tag search runs.
    static func nearby(in box: GeoBox) async -> [TrackCandidate] {
        await withTaskGroup(of: [TrackCandidate].self, returning: [TrackCandidate].self) { group in
            for word in ["circuit", "autodromo", "kart", "raceway", "ring"] {
                group.addTask { (try? await tracks(matching: word, in: box, limit: 20)) ?? [] }
            }
            var all: [TrackCandidate] = []
            for await found in group { all += found }
            return all
        }
    }

    private static func features(_ items: [URLQueryItem]) async throws -> [Feature] {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.queryItems = items + (language.map { [URLQueryItem(name: "lang", value: $0)] } ?? [])
        var req = URLRequest(url: c.url!, timeoutInterval: 12)
        req.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw FinderError.busy }
        return try JSONDecoder().decode(Response.self, from: data).features
    }

    private static func candidate(_ f: Feature) -> TrackCandidate? {
        let p = f.properties
        guard let name = p.name, !name.isEmpty, f.geometry.coordinates.count == 2 else { return nil }
        var box: GeoBox?
        if let e = p.extent, e.count == 4 {
            box = GeoBox(min(e[1], e[3]), min(e[0], e[2]), max(e[1], e[3]), max(e[0], e[2]))
        }
        guard let kind = TrackWords.kind(name: name, tag: "\(p.osm_key ?? ""):\(p.osm_value ?? "")", box: box) else { return nil }
        let place = [p.city ?? p.county ?? p.state, p.country].compactMap { $0 }.joined(separator: ", ")
        return TrackCandidate(id: "\(p.osm_type ?? "?")\(p.osm_id ?? 0)", name: name, kind: kind,
                              center: Coord(f.geometry.coordinates[1], f.geometry.coordinates[0]),
                              place: place, box: box)
    }
}
