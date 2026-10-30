import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// A lap shared from TrackLap, the .tracklap file declared in Info.plist.
    static let trackLap = UTType(exportedAs: "com.local.tracklap.lap")
}

/// A lap sent to a friend as a .tracklap file (JSON): the lap with its whole trace, the track it was
/// driven on, so the friend's app can time against the same start line, and who drove it.
struct SharedLap: Codable, Identifiable {
    static let version = 1

    var format = SharedLap.version
    var driver: String
    var vehicle: String = ""
    /// The SourceKind it was timed with.
    var source: String
    var date: Date
    var track: Track
    var lap: Lap

    var id: UUID { lap.id }

    enum ReadError: LocalizedError {
        case unreadable, newer

        var errorDescription: String? {
            switch self {
            case .unreadable: L("Questo file non è un giro di TrackLap.")
            case .newer: L("Questo giro viene da una versione più nuova di TrackLap: aggiorna l'app.")
            }
        }
    }

    static func read(_ url: URL) throws -> SharedLap {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        if let head = try? JSONDecoder().decode(Head.self, from: data), head.format > version { throw ReadError.newer }
        guard let lap = try? JSONDecoder().decode(SharedLap.self, from: data) else { throw ReadError.unreadable }
        return lap
    }

    /// Written to a temporary file named after the driver, the track and the time.
    func write() throws -> URL {
        let time = Fmt.lap(lap.time).replacingOccurrences(of: ":", with: ".")
        let name = [driver, track.name, time]
            .map { $0.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "." } }
            .joined(separator: " - ")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name + ".tracklap")
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        return url
    }

    private struct Head: Decodable { var format: Int }
}

/// What the share sheet sends: the file is written only once a destination is picked.
struct SharedLapFile: Transferable {
    let shared: SharedLap

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .trackLap) { item in
            SentTransferredFile(try item.shared.write())
        }
    }
}

extension Lap {
    /// When this lap crossed a line, in seconds from its start, interpolated between two points of the
    /// trace: a friend's lap on your sector lines, for the ESP32 that compares at each of them.
    func time(crossing gate: GateLine) -> Double? {
        let f = LocalFrame(origin: gate.mid)
        let a = f.xy(gate.a)
        let b = f.xy(gate.b)
        var prev: (p: TracePoint, xy: Vec)? = nil
        for p in trace {
            let xy = f.xy(Coord(p.lat, p.lon))
            if let q = prev, let u = Geo.intersect(q.xy, xy, a, b), q.p.t > 3 {
                return q.p.t + (p.t - q.p.t) * u
            }
            prev = (p, xy)
        }
        return nil
    }
}
