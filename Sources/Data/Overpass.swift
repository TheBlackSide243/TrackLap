import Foundation

/// Tag-based search and track layouts from the public Overpass API (OpenStreetMap). Its servers
/// are often slow or busy, so every query goes to all mirrors at once and the first answer wins.
enum Overpass {
    struct Response: Decodable {
        let elements: [Element]
        let remark: String?
    }

    struct Element: Decodable {
        let type: String
        let id: Int64
        let lat: Double?
        let lon: Double?
        let bounds: Bounds?
        let tags: [String: String]?
        let geometry: [Point?]?
    }

    struct Point: Decodable {
        let lat: Double
        let lon: Double
    }

    struct Bounds: Decodable {
        let minlat: Double
        let minlon: Double
        let maxlat: Double
        let maxlon: Double
    }

    private static let endpoints = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.private.coffee/api/interpreter")!,
    ]

    private static let formSafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func run(_ query: String, timeout: TimeInterval) async throws -> [Element] {
        let body = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: formSafe) ?? "")).utf8)
        return try await withThrowingTaskGroup(of: [Element]?.self, returning: [Element].self) { group in
            for url in endpoints {
                group.addTask { try? await fetch(url, body: body, timeout: timeout) }
            }
            for try await answer in group {
                if let answer {
                    group.cancelAll()
                    return answer
                }
            }
            throw FinderError.busy
        }
    }

    private static func fetch(_ url: URL, body: Data, timeout: TimeInterval) async throws -> [Element] {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw FinderError.busy }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        // A busy server answers 200 with a timeout remark and whatever it found so far.
        if let remark = decoded.remark, remark.localizedCaseInsensitiveContains("error") { throw FinderError.busy }
        return decoded.elements
    }

    /// Motorsport venues around a point, from their tags.
    static func nearby(_ c: Coord, radiusKm: Double) async throws -> [TrackCandidate] {
        let r = Int(radiusKm * 1000)
        let query = """
        [out:json][timeout:40];
        (
          nwr["sport"~"motor|karting|motocross|speedway"]["name"](around:\(r),\(c.lat),\(c.lon));
          way["highway"="raceway"]["name"](around:\(r),\(c.lat),\(c.lon));
        );
        out tags bb 150;
        """
        return try await run(query, timeout: 45).compactMap(candidate)
    }

    /// The raceway ways inside a box.
    static func raceways(in box: GeoBox) async throws -> [[Coord]] {
        let query = """
        [out:json][timeout:25];
        way["highway"="raceway"](\(box.minLat),\(box.minLon),\(box.maxLat),\(box.maxLon));
        out geom;
        """
        return try await run(query, timeout: 30).compactMap { e -> [Coord]? in
            let pts = (e.geometry ?? []).compactMap { $0.map { Coord($0.lat, $0.lon) } }
            return pts.count >= 2 ? pts : nil
        }
    }

    private static func candidate(_ e: Element) -> TrackCandidate? {
        guard let tags = e.tags, let name = tags["name"], !name.isEmpty else { return nil }
        var box: GeoBox?
        let center: Coord
        if let b = e.bounds {
            box = GeoBox(b.minlat, b.minlon, b.maxlat, b.maxlon)
            center = box!.center
        } else if let lat = e.lat, let lon = e.lon {
            center = Coord(lat, lon)
        } else {
            return nil
        }
        let sport = tags["sport"] ?? ""
        let kind: TrackCandidate.Kind
        if tags["highway"] == "raceway" {
            guard let k = TrackWords.kind(name: name, tag: "highway:raceway", box: box) else { return nil }
            kind = k
        } else if sport.contains("karting") || name.localizedCaseInsensitiveContains("kart") {
            kind = .karting
        } else if sport.contains("motocross") {
            kind = .other
        } else {
            kind = .circuit
        }
        let place = tags["addr:city"] ?? ""
        return TrackCandidate(id: "\(e.type)/\(e.id)", name: name, kind: kind, center: center, place: place, box: box)
    }
}

/// The main OpenStreetMap API: fast for a small box, used for a track layout when every Overpass
/// server is busy. Only the raceway ways are kept from the answer.
enum OSMMap {
    static func raceways(in box: GeoBox) async throws -> [[Coord]] {
        // The API refuses boxes over 0.25 square degrees; a circuit needs far less.
        guard box.area < 0.02 else { throw FinderError.busy }
        let url = URL(string: "https://api.openstreetmap.org/api/0.6/map?bbox=\(box.minLon),\(box.minLat),\(box.maxLon),\(box.maxLat)")!
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw FinderError.busy }
        let reader = RacewayReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw FinderError.busy }
        return reader.ways
    }
}

private final class RacewayReader: NSObject, XMLParserDelegate {
    private var nodes: [Int64: Coord] = [:]
    private var refs: [Int64] = []
    private var inWay = false
    private var isRaceway = false
    private var found: [[Int64]] = []

    var ways: [[Coord]] {
        found.compactMap { ids in
            let pts = ids.compactMap { nodes[$0] }
            return pts.count >= 2 ? pts : nil
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "node":
            if let id = attributeDict["id"].flatMap({ Int64($0) }),
               let lat = attributeDict["lat"].flatMap({ Double($0) }),
               let lon = attributeDict["lon"].flatMap({ Double($0) }) {
                nodes[id] = Coord(lat, lon)
            }
        case "way":
            inWay = true
            isRaceway = false
            refs = []
        case "nd":
            if inWay, let ref = attributeDict["ref"].flatMap({ Int64($0) }) { refs.append(ref) }
        case "tag":
            if inWay, attributeDict["k"] == "highway", attributeDict["v"] == "raceway" { isRaceway = true }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "way" else { return }
        if isRaceway { found.append(refs) }
        inWay = false
    }
}
