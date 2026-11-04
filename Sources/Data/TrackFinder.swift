import Foundation

struct TrackCandidate: Identifiable, Hashable {
    enum Kind: String { case circuit, karting, other }

    let id: String
    let name: String
    let kind: Kind
    let center: Coord
    var place = ""
    /// The venue's area on OpenStreetMap, when known: the raceway ways are looked for inside it.
    var box: GeoBox? = nil
    /// ISO country code, for the catalog.
    var country = ""
    var distanceKm: Double? = nil

    var icon: String { kind == .karting ? "flag.2.crossed.fill" : "flag.checkered" }

    var kindTitle: String {
        switch kind {
        case .circuit: L("Autodromo")
        case .karting: L("Kartodromo")
        case .other: L("Pista")
        }
    }

    var subtitle: String {
        var parts = [kindTitle]
        if !place.isEmpty { parts.append(place) }
        if let distanceKm { parts.append(Fmt.distance(distanceKm * 1000)) }
        return parts.joined(separator: " · ")
    }

    var searchBox: GeoBox {
        if let box, box.area > 1e-6 { return box.padded(meters: 350) }
        return GeoBox(around: center, meters: kind == .karting ? 700 : 2500)
    }
}

struct PlaceCandidate: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let center: Coord
}

enum FinderError: LocalizedError {
    case busy

    var errorDescription: String? { L("OpenStreetMap non risponde in questo momento: riprova tra poco.") }
}

enum Net {
    static let userAgent: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "TrackLap/\(v) (iOS lap timer)"
    }()
}

/// Tells motorsport venues from other sports centres, and whole circuits from their named corners,
/// by tag and by the words OpenStreetMap names use in many languages.
enum TrackWords {
    private static let motor = ["autodrom", "autódrom", "circuit", "raceway", "speedway", "racetrack", "race track",
                                "motodrom", "motódrom", "kart", "rennstrecke", "motorsport", "motocross", "rallycross",
                                "autocross", "motorpark", "motor park", "racing", "drift", "minimoto", "supermotard",
                                "okruh", "sirkuit", "サーキット", "スピードウェイ", "赛车", "賽車", "حلبة"]
    private static let corners = ["curva", "curve", "turn", "virage", "kurve", "corner", "chicane", "variante", "tornante",
                                  "hairpin", "épingle", "pit", "pitlane", "box", "rettilineo", "straight", "esse", "s"]
    private static let notRing = ["spring", "springs", "string", "boxring", "eisring"]

    static func kind(name: String, tag: String, box: GeoBox?) -> TrackCandidate.Kind? {
        let n = name.lowercased()
        let motorName = isMotor(n)
        switch tag {
        case "highway:raceway":
            if isCorner(n) { return nil }
            // A short named raceway is a corner or a pit lane, unless the name says otherwise.
            if let box, !motorName, diagonal(box) < 300 { return nil }
        case "leisure:sports_centre", "leisure:track", "leisure:stadium":
            if !motorName { return nil }
        default:
            return nil
        }
        if n.contains("kart") { return .karting }
        if n.contains("cross") || n.hasPrefix("mx ") { return .other }
        return .circuit
    }

    private static func isMotor(_ n: String) -> Bool {
        if motor.contains(where: { n.contains($0) }) { return true }
        let words = n.split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains { $0.hasSuffix("ring") && !notRing.contains($0) }
    }

    private static func isCorner(_ n: String) -> Bool {
        let first = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).first.map(String.init) ?? n
        if corners.contains(first) { return true }
        // "T1", "T12": turn numbers.
        return first.count <= 3 && first.hasPrefix("t") && first.dropFirst().allSatisfy(\.isNumber) && first.count > 1
    }

    private static func diagonal(_ b: GeoBox) -> Double {
        Geo.distance(Coord(b.minLat, b.minLon), Coord(b.maxLat, b.maxLon))
    }
}

enum TrackFinder {
    /// One entry per venue: a circuit found both as an area and as its raceway, or by two searches,
    /// shows once, keeping the one with the larger area.
    static func merge(_ list: [TrackCandidate]) -> [TrackCandidate] {
        var out: [TrackCandidate] = []
        for c in list {
            if let i = out.firstIndex(where: { same($0, c) }) {
                if (c.box?.area ?? 0) > (out[i].box?.area ?? 0) { out[i] = c }
                continue
            }
            out.append(c)
        }
        return out
    }

    static func same(_ a: TrackCandidate, _ b: TrackCandidate) -> Bool {
        guard a.kind == b.kind else { return false }
        let d = Geo.distance(a.center, b.center)
        if a.name.lowercased() == b.name.lowercased() { return d < 5000 }
        if d < 400 { return true }
        return (a.box?.padded(meters: 200).contains(b.center) ?? false) || (b.box?.padded(meters: 200).contains(a.center) ?? false)
    }

    static func sorted(_ list: [TrackCandidate], from c: Coord) -> [TrackCandidate] {
        list.map { var x = $0; x.distanceKm = Geo.distance(c, $0.center) / 1000; return x }
            .sorted { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }
    }

    /// The raceways of a venue with its circuit relations. Overpass and the OpenStreetMap API race
    /// each other (the API a moment later, to leave it alone when Overpass is quick); the first
    /// answer wins. Empty when neither answers or there is no raceway mapped.
    static func raceways(in box: GeoBox) async -> RacewayData {
        await withTaskGroup(of: RacewayData?.self, returning: RacewayData.self) { group in
            group.addTask { try? await Overpass.raceways(in: box) }
            group.addTask {
                try? await Task.sleep(for: .seconds(1.5))
                if Task.isCancelled { return nil }
                return try? await OSMMap.raceways(in: box)
            }
            for await answer in group {
                if let answer {
                    group.cancelAll()
                    return answer
                }
            }
            return RacewayData()
        }
    }

    /// A new track from what OpenStreetMap has in the box: the outline, and the start line and
    /// sectors put in place when a lap can be found.
    static func track(name: String, place: String, center: Coord, box: GeoBox, karting: Bool) async -> Track {
        let data = await raceways(in: box)
        var t = Track(name: name, place: place, center: center, outline: data.outline)
        t.applyAuto(AutoLines.layouts(data, width: karting ? 14 : 24))
        return t
    }
}
