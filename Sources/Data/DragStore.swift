import Foundation
import Observation

/// The drag runs: one JSON file per run, plus an index with the results for the list and the records.
@Observable
final class DragStore {
    private(set) var summaries: [DragSummary] = []

    private var dir: URL { Files.docs.appendingPathComponent("drags", isDirectory: true) }
    private var indexURL: URL { Files.docs.appendingPathComponent("drags.json") }

    init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        summaries = Files.read([DragSummary].self, from: indexURL) ?? []
    }

    func save(_ r: DragRun) {
        Files.write(r, to: file(r.id))
        if let i = summaries.firstIndex(where: { $0.id == r.id }) {
            summaries[i] = r.summary
        } else {
            summaries.append(r.summary)
        }
        summaries.sort { $0.date > $1.date }
        Files.write(summaries, to: indexURL)
    }

    func load(_ id: UUID) -> DragRun? {
        Files.read(DragRun.self, from: file(id))
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(id))
        summaries.removeAll { $0.id == id }
        Files.write(summaries, to: indexURL)
    }

    /// The best of every measure: the shortest time, or the shortest stop for braking. With a car,
    /// only the runs driven with it; without, all of them.
    func records(car: UUID? = nil) -> [String: DragRecord] {
        var out: [String: DragRecord] = [:]
        for s in summaries where car == nil || s.carID == car {
            for r in s.results {
                let v = r.kind == .braking ? r.distance : r.time
                if let old = out[r.name], old.value <= v { continue }
                out[r.name] = DragRecord(result: r, run: s)
            }
        }
        return out
    }

    /// What the timer compares with to colour a best.
    func bests(car: UUID? = nil) -> [String: Double] { records(car: car).mapValues(\.value) }

    /// Some run was driven with this car.
    func hasRuns(car: UUID) -> Bool { summaries.contains { $0.carID == car } }

    private func file(_ id: UUID) -> URL { dir.appendingPathComponent(id.uuidString + ".json") }
}

/// The best result of a measure and the run it was done in.
struct DragRecord {
    let result: DragResult
    let run: DragSummary

    var value: Double { result.kind == .braking ? result.distance : result.time }
}
