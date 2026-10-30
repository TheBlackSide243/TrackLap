import Foundation
import Observation

enum Files {
    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    static func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            print("TrackLap: saving \(url.lastPathComponent) failed: \(error)")
        }
    }

    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

@Observable
final class TrackStore {
    private(set) var tracks: [Track] = []

    private var url: URL { Files.docs.appendingPathComponent("tracks.json") }

    init() {
        tracks = Files.read([Track].self, from: url) ?? []
        if tracks.isEmpty {
            tracks = [DemoCircuit.track()]
            save()
        }
    }

    func track(_ id: UUID?) -> Track? {
        guard let id else { return nil }
        return tracks.first { $0.id == id }
    }

    func upsert(_ t: Track) {
        if let i = tracks.firstIndex(where: { $0.id == t.id }) {
            tracks[i] = t
        } else {
            tracks.insert(t, at: 0)
        }
        save()
    }

    func delete(_ id: UUID) {
        tracks.removeAll { $0.id == id }
        save()
    }

    private func save() { Files.write(tracks, to: url) }
}

/// One JSON file per session, plus a small index for the list.
@Observable
final class SessionStore {
    private(set) var summaries: [SessionSummary] = []

    private var dir: URL { Files.docs.appendingPathComponent("sessions", isDirectory: true) }
    private var indexURL: URL { Files.docs.appendingPathComponent("sessions.json") }

    init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        summaries = Files.read([SessionSummary].self, from: indexURL) ?? []
        // Indexes written before 0.3.0 have no track: read it once from each session file.
        var changed = false
        for i in summaries.indices where summaries[i].trackID == nil {
            if let track = load(summaries[i].id)?.trackID {
                summaries[i].trackID = track
                changed = true
            }
        }
        if changed { Files.write(summaries, to: indexURL) }
    }

    func save(_ s: Session) {
        Files.write(s, to: file(s.id))
        if let i = summaries.firstIndex(where: { $0.id == s.id }) {
            summaries[i] = s.summary
        } else {
            summaries.append(s.summary)
        }
        summaries.sort { $0.date > $1.date }
        Files.write(summaries, to: indexURL)
    }

    func load(_ id: UUID) -> Session? {
        Files.read(Session.self, from: file(id))
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(id))
        summaries.removeAll { $0.id == id }
        Files.write(summaries, to: indexURL)
    }

    /// The best lap of the fastest sessions on a track, fastest first.
    func bestLaps(on track: UUID?, excluding: UUID? = nil, limit: Int = 12) -> [SessionLap] {
        sessions(on: track, excluding: excluding).prefix(limit).compactMap { s in
            load(s.id)?.best.map { SessionLap(lap: $0, session: s) }
        }
    }

    /// The fastest lap ever driven on a track.
    func record(on track: UUID?, excluding: UUID? = nil) -> SessionLap? {
        bestLaps(on: track, excluding: excluding, limit: 1).first
    }

    private func sessions(on track: UUID?, excluding: UUID?) -> [SessionSummary] {
        guard let track else { return [] }
        return summaries
            .filter { $0.trackID == track && $0.id != excluding && $0.best != nil }
            .sorted { ($0.best ?? 0) < ($1.best ?? 0) }
    }

    private func file(_ id: UUID) -> URL { dir.appendingPathComponent(id.uuidString + ".json") }
}

/// A lap together with the session it was driven in.
struct SessionLap: Identifiable {
    let lap: Lap
    let session: SessionSummary

    var id: UUID { lap.id }
}

enum Export {
    static func url(_ s: Session, _ ext: String) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm"
        let safe = s.trackName.filter { $0.isLetter || $0.isNumber }
        return FileManager.default.temporaryDirectory.appendingPathComponent("TrackLap_\(safe)_\(df.string(from: s.date)).\(ext)")
    }
}

/// Every point of every lap with speed and g, for spreadsheets and analysis tools.
enum CSV {
    static func write(_ s: Session) throws -> URL {
        var x = "lap,lap_time_s,elapsed_s,distance_m,latitude,longitude,speed_kmh,lateral_g,longitudinal_g\n"
        for lap in s.laps {
            let g = GForce.along(lap.trace)
            for (i, p) in lap.trace.enumerated() {
                x += "\(lap.number),"
                x += String(format: "%.3f,%.3f,%.1f,%.7f,%.7f,%.2f,%.2f,%.2f\n",
                            lap.time, p.t, p.d, p.lat, p.lon, p.v * 3.6, g[i].lateral, g[i].longitudinal)
            }
        }
        let url = Export.url(s, "csv")
        try x.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

enum GPX {
    static func write(_ s: Session) throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var x = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TrackLap" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>\(escape(s.trackName))</name>

        """
        for lap in s.laps {
            x += "<trkseg>\n"
            for p in lap.trace {
                let time = iso.string(from: lap.startedAt.addingTimeInterval(p.t))
                x += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><time>\(time)</time></trkpt>\n"
            }
            x += "</trkseg>\n"
        }
        x += "</trk>\n</gpx>\n"
        let url = Export.url(s, "gpx")
        try x.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
