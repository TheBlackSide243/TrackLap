import Foundation

/// The raceways of a venue as OpenStreetMap has them: every way with its nodes and tags, and the
/// circuit relations, one per layout, with their ways, their pit lane and the node of the finish line.
struct RacewayData {
    struct Way {
        var id: Int64
        var nodes: [Int64]
        var coords: [Coord]
        var tags: [String: String]
    }

    struct Circuit {
        var name: String
        var lap: [Int64]
        var pits: [Int64]
        /// The nodes mapped as the start and the finish line (often the same place).
        var start: Coord?
        var finish: Coord?
    }

    var ways: [Way] = []
    var circuits: [Circuit] = []

    /// What the map draws: every raceway, longest first.
    var outline: [[Coord]] {
        ways.map(\.coords).filter { $0.count >= 2 }.sorted { Geo.length($0) > Geo.length($1) }
    }
}

/// A layout of a track with its lines placed: from an OpenStreetMap circuit, or worked out from
/// the raceways when there is none.
struct TrackLayout: Codable, Hashable {
    enum Source: String, Codable {
        /// The finish line node of an OSM circuit.
        case mapped
        /// Beside the middle of the pit lane: where the finish line nearly always is.
        case pits
        /// The middle of a way named for the start.
        case named
        /// The middle of the longest straight.
        case straight
    }

    var name: String
    var length: Double
    var start: GateLine
    var sectors: [GateLine]
    var source: Source
    /// The lap as a line every 15 m, to tell which layout a lap was driven on (0.8.2).
    var path: [Coord]? = nil

    /// What sessions and records are filed under: two layouts never share it.
    var key: String { name + "|" + String(Int(length.rounded())) }

    /// "Raccordo Junior · 2.41 km", or the full lap and the variants by number when unnamed.
    func title(_ index: Int) -> String {
        let n = name.isEmpty ? (index == 0 ? L("Giro completo") : L("Variante \(index)")) : name
        return n + " · " + Fmt.distance(length)
    }
}

/// Places the start line and two intermediates (three sectors of the same length) on the layouts of
/// a venue. OpenStreetMap seldom maps a finish line by itself, but its circuit relations list the
/// ways of each layout, the pit lane and often the finish node; without a relation the lap is the
/// longest loop of raceways (old banked ovals and pit lanes left out) and the line goes beside the
/// pit lane, on a way named for the start, or on the longest straight.
enum AutoLines {
    static let pitWords = try! NSRegularExpression(
        pattern: "\\bpit|\\bbox(es|engasse|en)?\\b|corsia box|voie des stands|\\bstands\\b|pitlane|boxenstra", options: .caseInsensitive)
    static let startWords = try! NSRegularExpression(
        pattern: "partenza|traguardo|\\bstart|finish|\\bziel|arriv|rettilineo principale|rettifilo principale|main straight|d[ée]part|griglia|\\bgrid\\b",
        options: .caseInsensitive)
    static let notALap = try! NSRegularExpression(
        pattern: "long lap|penalty|penalit|run-?off|via di fuga|escape|notausgang", options: .caseInsensitive)
    private static let gone = ["historic", "disused", "abandoned", "razed", "demolished", "construction", "proposed", "was:highway"]

    /// Every layout found, up to four: the mapped circuits first, then the other laps the raceways
    /// make (a short circuit, a chicane for motorcycles), the one most different from those already
    /// taken each time. Laps are compared by the stretches between junctions they do not share.
    static func layouts(_ data: RacewayData, width: Double, most: Int = 4) -> [TrackLayout] {
        let pts = data.ways.flatMap(\.coords)
        guard !pts.isEmpty else { return [] }
        let lat = pts.map(\.lat), lon = pts.map(\.lon)
        let frame = LocalFrame(origin: Coord((lat.min()! + lat.max()!) / 2, (lon.min()! + lon.max()!) / 2))
        let byID = Dictionary(data.ways.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let pits = data.ways.filter { kind($0) == .pit }
        let marks = data.circuits.compactMap { $0.finish ?? $0.start }

        // One graph for everything: the ways of the mapped circuits, and the other raceways (where
        // circuits are mapped, only named ones: the unnamed bits of a driving school make hundreds
        // of laps that are no layout). Penalty loops and run-offs are never a lap.
        let members = Set(data.circuits.flatMap { $0.lap })
        let use = data.ways.filter { w in
            if members.contains(w.id) { return true }
            let name = w.tags["name"] ?? ""
            return kind(w) == .main && !matches(notALap, name) && (data.circuits.isEmpty || !name.isEmpty)
        }
        guard let graph = Loop.graph(use, frame: frame) else { return [] }
        let length = graph.edges.map(\.length)

        var kept: [(length: Double, edges: Set<Int>)] = []
        /// How much more than the threshold a lap differs from the closest one already taken.
        func gap(_ l: Double, _ edges: Set<Int>) -> Double {
            kept.map { k in edges.symmetricDifference(k.edges).reduce(0) { $0 + length[$1] } - max(100, 0.02 * max(l, k.length)) }
                .min() ?? .infinity
        }
        var out: [TrackLayout] = []

        for c in data.circuits where out.count < most {
            guard let cycle = Loop.longestCycle(graph.edges, only: Set(c.lap)),
                  let loop = Loop(edges: graph.edges, coord: graph.coord, cycle: cycle, frame: frame) else { continue }
            let edges = Set(cycle.map(\.0))
            guard gap(loop.total, edges) > 0 else { continue }
            var at: (Double, TrackLayout.Source)?
            if let node = c.finish ?? c.start, let p = loop.project(frame.xy(node)), p.distance < 40 { at = (p.along, .mapped) }
            if at == nil, let s = loop.besidePits(c.pits.compactMap { byID[$0] } + pits, frame: frame) { at = (s, .pits) }
            let (s, source) = at ?? (loop.longestStraight(), .straight)
            if let layout = loop.layout(name: c.name, at: s, source: source, width: width) {
                out.append(layout)
                kept.append((loop.total, edges))
            }
        }

        let laps = Loop.cycles(graph.edges)
        let longest = max(laps.map(\.length).max() ?? 0, out.map(\.length).max() ?? 0)
        var pool = laps.filter { $0.length >= max(800, 0.3 * longest) }.map { (lap: $0, edges: Set($0.path.map(\.0))) }
        while out.count < most, let best = pool.indices.max(by: { a, b in
            let ga = gap(pool[a].lap.length, pool[a].edges), gb = gap(pool[b].lap.length, pool[b].edges)
            return ga == gb ? pool[a].lap.length < pool[b].lap.length : ga < gb
        }) {
            let lap = pool.remove(at: best)
            guard gap(lap.lap.length, lap.edges) > 0 else { break }
            guard let loop = Loop(edges: graph.edges, coord: graph.coord, cycle: lap.lap.path, frame: frame) else { continue }
            var at: (Double, TrackLayout.Source)?
            for m in marks {
                if let p = loop.project(frame.xy(m)), p.distance < 40 {
                    at = (p.along, .mapped)
                    break
                }
            }
            if at == nil, let s = loop.besidePits(pits, frame: frame) { at = (s, .pits) }
            if at == nil, let s = loop.alongNamedWay(frame: frame) { at = (s, .named) }
            let (s, source) = at ?? (loop.longestStraight(), .straight)
            // Named after the stretches only this lap has, next to the first layout.
            let name = kept.first.map { f in loop.names(ofEdges: lap.edges.subtracting(f.edges)).prefix(2).joined(separator: " · ") } ?? ""
            if let layout = loop.layout(name: name, at: s, source: source, width: width) {
                out.append(layout)
                kept.append((loop.total, lap.edges))
            }
        }
        return out
    }

    enum Kind { case main, pit, gone }

    static func kind(_ w: RacewayData.Way) -> Kind {
        let t = w.tags
        if gone.contains(where: { t[$0] != nil }) || t["area"] == "yes" { return .gone }
        let name = t["name"] ?? ""
        if t["pitlane"] == "yes" || ["pit_lane", "pitlane", "pits"].contains(t["raceway"] ?? "") || t["service"] == "pit_lane"
            || matches(pitWords, name) {
            return .pit
        }
        return .main
    }

    static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
}

/// One lap of a layout as a closed polyline in metres, with the junctions along it, found as the
/// longest loop through the raceway ways (variants and chicane bypasses make shorter ones).
private struct Loop {
    struct Edge {
        var from: Int64
        var to: Int64
        var nodes: [Int64]
        var length: Double
        var directed: Bool
        var name: String
        var way: Int64
    }

    let frame: LocalFrame
    let edges: [Edge]
    let points: [Vec]
    let cum: [Double]
    /// Metres along the lap of every junction with another way.
    let junctions: [Double]
    /// The edges of the lap, for the way names.
    let used: [Int]
    let coordOf: [Int64: Vec]

    var total: Double { cum.last ?? 0 }
    /// The OSM ways the lap goes along.
    var wayIDs: Set<Int64> { Set(used.map { edges[$0].way }) }

    /// The longest lap through these ways.
    init?(ways: [RacewayData.Way], frame: LocalFrame, keepAll: Bool) {
        guard let graph = Self.graph(ways.filter { keepAll || AutoLines.kind($0) == .main }, frame: frame),
              let cycle = Self.longestCycle(graph.edges), !cycle.isEmpty else { return nil }
        self.init(edges: graph.edges, coord: graph.coord, cycle: cycle, frame: frame)
    }

    /// The names of the ways of these edges, in the order the lap meets them.
    func names(ofEdges set: Set<Int>) -> [String] {
        var out: [String] = []
        for i in used where set.contains(i) && !edges[i].name.isEmpty && !out.contains(edges[i].name) {
            out.append(edges[i].name)
        }
        return out
    }

    /// The ways cut at every junction: the edges of the graph between them, and every node's place.
    static func graph(_ ways: [RacewayData.Way], frame: LocalFrame) -> (edges: [Edge], coord: [Int64: Vec])? {
        let usable = ways.filter { $0.nodes.count >= 2 && $0.nodes.count == $0.coords.count }
        guard !usable.isEmpty else { return nil }
        var coord: [Int64: Vec] = [:]
        var count: [Int64: Int] = [:]
        for w in usable {
            for (i, n) in w.nodes.enumerated() {
                coord[n] = frame.xy(w.coords[i])
                count[n, default: 0] += (i == 0 || i == w.nodes.count - 1) ? 2 : 1
            }
        }
        var junction = Set(count.filter { $0.value != 2 }.keys)
        for w in usable {
            junction.insert(w.nodes[0])
            junction.insert(w.nodes[w.nodes.count - 1])
        }
        // Ways cut at every junction: the edges of the graph between them.
        var edges: [Edge] = []
        for w in usable {
            let oneway = w.tags["oneway"] ?? ""
            let ids = oneway == "-1" ? Array(w.nodes.reversed()) : w.nodes
            let directed = ["yes", "-1", "1", "true"].contains(oneway)
            var seg = [ids[0]]
            for n in ids.dropFirst() {
                seg.append(n)
                if junction.contains(n) {
                    var len = 0.0
                    for i in 0..<(seg.count - 1) { len += ((coord[seg[i + 1]] ?? .zero) - (coord[seg[i]] ?? .zero)).length }
                    edges.append(Edge(from: seg[0], to: seg[seg.count - 1], nodes: seg, length: len, directed: directed,
                                      name: w.tags["name"] ?? "", way: w.id))
                    seg = [n]
                }
            }
        }
        return edges.isEmpty ? nil : (edges, coord)
    }

    /// The lap along a cycle of the graph.
    init?(edges: [Edge], coord: [Int64: Vec], cycle: [(Int, Bool)], frame: LocalFrame) {
        self.frame = frame
        guard !cycle.isEmpty else { return nil }
        var pts: [Vec] = []
        var ids: [Int64] = []
        for (e, reversed) in cycle {
            let seq = reversed ? Array(edges[e].nodes.reversed()) : edges[e].nodes
            for n in (pts.isEmpty ? seq[...] : seq.dropFirst()) {
                pts.append(coord[n] ?? .zero)
                ids.append(n)
            }
        }
        var cum = [0.0]
        for i in 0..<(pts.count - 1) { cum.append(cum[i] + (pts[i + 1] - pts[i]).length) }
        guard let total = cum.last, total > 150 else { return nil }
        var degree: [Int64: Int] = [:]
        for e in edges {
            degree[e.from, default: 0] += 1
            degree[e.to, default: 0] += 1
        }
        self.edges = edges
        points = pts
        self.cum = cum
        junctions = ids.indices.filter { degree[ids[$0], default: 0] > 2 }.map { cum[$0] }
        used = cycle.map(\.0)
        coordOf = coord
    }

    /// Every simple cycle, by depth-first search over the junctions; a budget and a limit keep a huge
    /// network from taking long.
    static func cycles(_ edges: [Edge], budget: Int = 300_000, limit: Int = 3000) -> [(length: Double, path: [(Int, Bool)])] {
        var adj: [Int64: [(to: Int64, edge: Int, reversed: Bool)]] = [:]
        for (i, e) in edges.enumerated() {
            adj[e.from, default: []].append((e.to, i, false))
            if !e.directed { adj[e.to, default: []].append((e.from, i, true)) }
        }
        var found: [(length: Double, path: [(Int, Bool)])] = []
        var steps = 0
        for s in adj.keys.sorted() {
            var stack: [(node: Int64, path: [(Int, Bool)], seen: Set<Int64>, length: Double)] = [(s, [], [s], 0)]
            while steps < budget, found.count < limit, let top = stack.popLast() {
                let (u, path, seen, length) = top
                steps += 1
                for next in adj[u] ?? [] {
                    if path.contains(where: { $0.0 == next.edge }) { continue }
                    let l = length + edges[next.edge].length
                    if next.to == s {
                        found.append((l, path + [(next.edge, next.reversed)]))
                        continue
                    }
                    if seen.contains(next.to) || next.to < s { continue }
                    var more = seen
                    more.insert(next.to)
                    stack.append((next.to, path + [(next.edge, next.reversed)], more, l))
                }
            }
        }
        return found
    }

    /// The longest simple cycle, by depth-first search over the junctions (a venue has a few dozen);
    /// a budget keeps a huge network from taking long, keeping the best found so far.
    static func longestCycle(_ edges: [Edge], only ways: Set<Int64>? = nil, budget: Int = 300_000) -> [(Int, Bool)]? {
        var adj: [Int64: [(to: Int64, edge: Int, reversed: Bool)]] = [:]
        for (i, e) in edges.enumerated() where ways?.contains(e.way) ?? true {
            adj[e.from, default: []].append((e.to, i, false))
            if !e.directed { adj[e.to, default: []].append((e.from, i, true)) }
        }
        var best: (length: Double, path: [(Int, Bool)])? = nil
        var steps = 0
        for s in adj.keys.sorted() {
            var stack: [(node: Int64, path: [(Int, Bool)], seen: Set<Int64>, length: Double)] = [(s, [], [s], 0)]
            while steps < budget, let top = stack.popLast() {
                let (u, path, seen, length) = top
                steps += 1
                for next in adj[u] ?? [] {
                    if path.contains(where: { $0.0 == next.edge }) { continue }
                    let l = length + edges[next.edge].length
                    if next.to == s {
                        if l > (best?.length ?? 0) { best = (l, path + [(next.edge, next.reversed)]) }
                        continue
                    }
                    if seen.contains(next.to) || next.to < s { continue }
                    var more = seen
                    more.insert(next.to)
                    stack.append((next.to, path + [(next.edge, next.reversed)], more, l))
                }
            }
        }
        return best?.path
    }

    /// The point of the lap nearest to p: how far along the lap, and how far from p.
    func project(_ p: Vec) -> (along: Double, distance: Double)? {
        var best: (Double, Double)?
        for i in 0..<(points.count - 1) {
            let a = points[i], d = points[i + 1] - points[i]
            let l2 = max(1e-9, d.dot(d))
            let u = max(0, min(1, (p - a).dot(d) / l2))
            let dist = (a + d * u - p).length
            if dist < (best?.1 ?? .infinity) { best = (cum[i] + u * l2.squareRoot(), dist) }
        }
        return best.map { (along: $0.0, distance: $0.1) }
    }

    /// A point at s metres along the lap and the direction there.
    func point(at s: Double) -> (p: Vec, dir: Vec) {
        let s = (s.truncatingRemainder(dividingBy: total) + total).truncatingRemainder(dividingBy: total)
        for i in 0..<(points.count - 1) where cum[i + 1] >= s {
            let u = (s - cum[i]) / max(1e-9, cum[i + 1] - cum[i])
            let d = points[i + 1] - points[i]
            return (points[i] + d * u, d.normalized)
        }
        return (points[points.count - 1], Vec(1, 0))
    }

    /// Beside the middle of the longest pit lane way, when it runs along the lap.
    func besidePits(_ pits: [RacewayData.Way], frame: LocalFrame) -> Double? {
        let lines = pits.map { $0.coords.map(frame.xy) }.filter { $0.count >= 2 }
        guard let pit = lines.max(by: { Self.length($0) < Self.length($1) }) else { return nil }
        guard let p = project(Self.middle(pit)), p.distance < 150 else { return nil }
        return p.along
    }

    /// The middle of the first way of the lap named for the start.
    func alongNamedWay(frame: LocalFrame) -> Double? {
        for i in used where AutoLines.matches(AutoLines.startWords, edges[i].name) {
            let pts = edges[i].nodes.compactMap { coordOf[$0] }
            if pts.count >= 2, let p = project(Self.middle(pts)) { return p.along }
        }
        return nil
    }

    /// The middle of the longest stretch whose direction stays within 6° of where it begins.
    func longestStraight() -> Double {
        let n = points.count
        guard n > 2 else { return 0 }
        let heading = (0..<(n - 1)).map { atan2(points[$0 + 1].y - points[$0].y, points[$0 + 1].x - points[$0].x) }
        let tolerance = 6 * Double.pi / 180
        var best = (length: 0.0, middle: 0.0)
        for i in heading.indices {
            var j = i
            while j + 1 < heading.count, abs(Self.angle(heading[j + 1] - heading[i])) < tolerance { j += 1 }
            let len = cum[j + 1] - cum[i]
            if len > best.length { best = (len, (cum[i] + cum[j + 1]) / 2) }
        }
        return best.middle
    }

    /// The start line at s (moved a little where it would cut another part of the track or sit on
    /// a junction, unless it is the mapped one), and two intermediates a third and two thirds on.
    func layout(name: String, at s: Double, source: TrackLayout.Source, width: Double) -> TrackLayout? {
        guard total > 150 else { return nil }
        let start = fit(s, width: width, exact: source == .mapped)
        let sectors = [1.0, 2.0].map { fit(start.at + total * $0 / 3, width: width, exact: false).gate }
        let path = stride(from: 0.0, to: total, by: 15).map { frame.coord(point(at: $0).p) }
        return TrackLayout(name: name, length: total, start: start.gate, sectors: sectors, source: source, path: path)
    }

    private func fit(_ s: Double, width: Double, exact: Bool) -> (at: Double, gate: GateLine) {
        if !exact {
            for k in stride(from: 0.0, to: 60, by: 3) {
                for sign in [1.0, -1.0] {
                    let at = s + sign * k
                    let g = gate(at, width: width)
                    if clear(g, at: at) { return (wrap(at), coords(g)) }
                }
            }
        }
        return (wrap(s), coords(gate(s, width: width)))
    }

    private func gate(_ s: Double, width: Double) -> (Vec, Vec) {
        let (p, dir) = point(at: s)
        let n = dir.perpendicular * (width / 2)
        return (p - n, p + n)
    }

    /// The line crosses the lap only where it stands, and is not on top of a junction.
    private func clear(_ g: (Vec, Vec), at s: Double) -> Bool {
        let s = wrap(s)
        for j in junctions where loopDistance(j, s) < 25 { return false }
        for i in 0..<(points.count - 1) where Geo.intersect(g.0, g.1, points[i], points[i + 1]) != nil {
            if loopDistance(cum[i], s) > 40 { return false }
        }
        return true
    }

    private func coords(_ g: (Vec, Vec)) -> GateLine { GateLine(a: frame.coord(g.0), b: frame.coord(g.1)) }

    private func wrap(_ s: Double) -> Double { (s.truncatingRemainder(dividingBy: total) + total).truncatingRemainder(dividingBy: total) }

    private func loopDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: total)
        return min(d, total - d)
    }

    private static func angle(_ a: Double) -> Double {
        var x = a
        while x > .pi { x -= 2 * .pi }
        while x < -.pi { x += 2 * .pi }
        return x
    }

    private static func length(_ pts: [Vec]) -> Double {
        zip(pts, pts.dropFirst()).reduce(0) { $0 + ($1.1 - $1.0).length }
    }

    private static func middle(_ pts: [Vec]) -> Vec {
        let half = length(pts) / 2
        var run = 0.0
        for (a, b) in zip(pts, pts.dropFirst()) {
            let l = (b - a).length
            if run + l >= half { return a + (b - a) * ((half - run) / max(l, 1e-9)) }
            run += l
        }
        return pts[pts.count - 1]
    }
}

extension Track {
    /// The lines of the first layout found, and the others kept for the editor to switch to.
    mutating func applyAuto(_ found: [TrackLayout]) {
        guard let first = found.first else { return }
        layouts = found
        use(first)
    }

    /// The layout the lines come from now, when the track has several.
    var layout: TrackLayout? { layouts?.first { $0.key == activeLayout } }

    /// The lines of this layout from now on.
    mutating func use(_ l: TrackLayout) {
        start = l.start
        sectors = l.sectors
        autoLines = l.source
        activeLayout = l.key
    }

    /// Lines moved by hand stay with their layout, for when it comes back.
    mutating func keepLinesInLayout() {
        guard let i = layouts?.firstIndex(where: { $0.key == activeLayout }), let start else { return }
        layouts?[i].start = start
        layouts?[i].sectors = sectors
    }
}

/// Which layout a lap was driven on: the one nearest the lap, measured both ways (how far the lap
/// runs from the layout, and the layout from the lap, every 5 m and at most 50 m), taken only when
/// it is clearly nearer than the next. At Monza the Junior is told from the full circuit lap after
/// lap even with the iPhone's GPS; the full circuit and its motorcycle chicane are too close to call,
/// so there the layout chosen in the editor stays.
enum LayoutMatch {
    static func best(_ trace: [TracePoint], among layouts: [TrackLayout]) -> TrackLayout? {
        guard trace.count > 20 else { return nil }
        let f = LocalFrame(origin: Coord(trace[0].lat, trace[0].lon))
        let lap = trace.map { f.xy(Coord($0.lat, $0.lon)) }
        let scored = layouts.compactMap { l -> (layout: TrackLayout, score: Double)? in
            guard let path = l.path, path.count > 3 else { return nil }
            let p = path.map(f.xy) + [f.xy(path[0])]
            return (l, meanDistance(lap, to: p) + meanDistance(p, to: lap))
        }.sorted { $0.score < $1.score }
        guard let first = scored.first, first.score < 10 else { return nil }
        if scored.count > 1, scored[1].score - first.score < 0.6 { return nil }
        return first.layout
    }

    /// The mean distance of line a from line b, every 5 m of a, each at most 50 m.
    static func meanDistance(_ a: [Vec], to b: [Vec], cap: Double = 50) -> Double {
        var sum = 0.0
        var count = 0
        for (p, q) in zip(a, a.dropFirst()) {
            let n = max(1, Int((q - p).length / 5))
            for k in 0..<n {
                let m = p + (q - p) * (Double(k) / Double(n))
                var near = cap
                for (u, v) in zip(b, b.dropFirst()) {
                    let d = v - u
                    let t = max(0, min(1, (m - u).dot(d) / max(1e-9, d.dot(d))))
                    near = min(near, (u + d * t - m).length)
                    if near < 1 { break }
                }
                sum += near
                count += 1
            }
        }
        return count == 0 ? cap : sum / Double(count)
    }

    /// A lap's sector times on other lines, from its trace; empty when it does not cross them all.
    static func sectors(of lap: Lap, on gates: [GateLine]) -> [Double] {
        guard !gates.isEmpty else { return [] }
        let at = gates.compactMap { lap.time(crossing: $0) }.sorted()
        guard at.count == gates.count else { return [] }
        var out: [Double] = []
        var last = 0.0
        for t in at {
            out.append(t - last)
            last = t
        }
        out.append(lap.time - last)
        return out
    }
}
