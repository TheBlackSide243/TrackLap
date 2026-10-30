import Foundation
import Observation

/// A friend's lap in the list: enough to show and pick it, the trace stays in its file.
struct FriendLap: Codable, Identifiable, Hashable {
    var id: UUID
    /// Your track it was matched to, or the friend's track added to yours.
    var trackID: UUID
    var trackName: String
    var driver: String
    var vehicle: String
    var source: String
    var date: Date
    var time: Double
    var added = Date()

    var title: String { driver + " · " + Fmt.lap(time) }
    var sourceTitle: String { SourceKind(rawValue: source)?.short ?? source }
}

/// The laps friends sent, as .tracklap files: one file each, plus an index for the lists.
@Observable
final class FriendLapStore {
    private(set) var laps: [FriendLap] = []

    private var dir: URL { Files.docs.appendingPathComponent("friends", isDirectory: true) }
    private var indexURL: URL { Files.docs.appendingPathComponent("friends.json") }

    init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        laps = Files.read([FriendLap].self, from: indexURL) ?? []
    }

    /// The same lap sent twice replaces the first.
    @discardableResult
    func add(_ s: SharedLap, on track: Track) -> FriendLap {
        Files.write(s, to: file(s.id))
        let f = FriendLap(id: s.id, trackID: track.id, trackName: track.name, driver: s.driver, vehicle: s.vehicle,
                          source: s.source, date: s.date, time: s.lap.time)
        laps.removeAll { $0.id == f.id }
        laps.insert(f, at: 0)
        save()
        return f
    }

    func shared(_ id: UUID) -> SharedLap? { Files.read(SharedLap.self, from: file(id)) }

    func lap(_ id: UUID) -> Lap? { shared(id)?.lap }

    /// The lap's track was deleted and added back.
    func move(_ id: UUID, to track: Track) {
        guard let i = laps.firstIndex(where: { $0.id == id }) else { return }
        laps[i].trackID = track.id
        laps[i].trackName = track.name
        save()
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(id))
        laps.removeAll { $0.id == id }
        save()
    }

    /// The friends' laps on a track, fastest first.
    func laps(on track: UUID?) -> [FriendLap] {
        laps.filter { $0.trackID == track }.sorted { $0.time < $1.time }
    }

    private func save() { Files.write(laps, to: indexURL) }

    private func file(_ id: UUID) -> URL { dir.appendingPathComponent(id.uuidString + ".tracklap") }
}
