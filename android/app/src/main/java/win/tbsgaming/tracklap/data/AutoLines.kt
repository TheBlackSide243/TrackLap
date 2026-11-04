package win.tbsgaming.tracklap.data

import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.GateLine
import win.tbsgaming.tracklap.model.Geo
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.LocalFrame
import win.tbsgaming.tracklap.model.TracePoint
import win.tbsgaming.tracklap.model.TrackLayout
import win.tbsgaming.tracklap.model.Vec
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min

/**
 * The raceways of a venue as OpenStreetMap has them: every way with its nodes and tags, and the
 * circuit relations, one per layout, with their ways, their pit lane and the node of the finish line.
 */
data class RacewayData(val ways: List<Way> = emptyList(), val circuits: List<Circuit> = emptyList()) {
    data class Way(val id: Long, val nodes: List<Long>, val coords: List<Coord>, val tags: Map<String, String>)
    data class Circuit(val name: String, val lap: List<Long>, val pits: List<Long>, val start: Coord?, val finish: Coord?)

    /** What the map draws: every raceway, longest first. */
    val outline: List<List<Coord>> get() = ways.map { it.coords }.filter { it.size >= 2 }.sortedByDescending { Geo.length(it) }
}

/**
 * Places the start line and two intermediates (three sectors of the same length) on the layouts of
 * a venue: from the circuit relations of OpenStreetMap when there are, else from the longest loops
 * of raceways, beside the pit lane, on a way named for the start, or on the longest straight.
 */
object AutoLines {
    val pitWords = Regex("\\bpit|\\bbox(es|engasse|en)?\\b|corsia box|voie des stands|\\bstands\\b|pitlane|boxenstra", RegexOption.IGNORE_CASE)
    val startWords = Regex(
        "partenza|traguardo|\\bstart|finish|\\bziel|arriv|rettilineo principale|rettifilo principale|main straight|d[ée]part|griglia|\\bgrid\\b",
        RegexOption.IGNORE_CASE,
    )
    val notALap = Regex("long lap|penalty|penalit|run-?off|via di fuga|escape|notausgang", RegexOption.IGNORE_CASE)
    private val gone = listOf("historic", "disused", "abandoned", "razed", "demolished", "construction", "proposed", "was:highway")

    enum class Kind { main, pit, gone }

    fun kind(w: RacewayData.Way): Kind {
        val t = w.tags
        if (gone.any { t[it] != null } || t["area"] == "yes") return Kind.gone
        val name = t["name"] ?: ""
        if (t["pitlane"] == "yes" || (t["raceway"] ?: "") in listOf("pit_lane", "pitlane", "pits") || t["service"] == "pit_lane" ||
            pitWords.containsMatchIn(name)
        ) return Kind.pit
        return Kind.main
    }

    private class Kept(val length: Double, val edges: Set<Int>)

    /**
     * Every layout found, up to four: the mapped circuits first, then the other laps the raceways make,
     * the one most different from those already taken each time.
     */
    fun layouts(data: RacewayData, width: Double, most: Int = 4): List<TrackLayout> {
        val pts = data.ways.flatMap { it.coords }
        if (pts.isEmpty()) return emptyList()
        val frame = LocalFrame(Coord((pts.minOf { it.lat } + pts.maxOf { it.lat }) / 2, (pts.minOf { it.lon } + pts.maxOf { it.lon }) / 2))
        val byID = data.ways.associateBy { it.id }
        val pits = data.ways.filter { kind(it) == Kind.pit }
        val marks = data.circuits.mapNotNull { it.finish ?: it.start }

        val members = data.circuits.flatMap { it.lap }.toSet()
        val use = data.ways.filter { w ->
            if (w.id in members) true
            else {
                val name = w.tags["name"] ?: ""
                kind(w) == Kind.main && !notALap.containsMatchIn(name) && (data.circuits.isEmpty() || name.isNotEmpty())
            }
        }
        val graph = Loop.graph(use, frame) ?: return emptyList()
        val length = graph.first.map { it.length }

        val kept = ArrayList<Kept>()
        fun gap(l: Double, edges: Set<Int>): Double =
            kept.minOfOrNull { k ->
                val diff = (edges - k.edges) + (k.edges - edges)
                diff.sumOf { length[it] } - max(100.0, 0.02 * max(l, k.length))
            } ?: Double.POSITIVE_INFINITY
        val out = ArrayList<TrackLayout>()

        for (c in data.circuits) {
            if (out.size >= most) break
            val cycle = Loop.longestCycle(graph.first, c.lap.toSet()) ?: continue
            val loop = Loop.make(graph.first, graph.second, cycle, frame) ?: continue
            val edges = cycle.map { it.first }.toSet()
            if (gap(loop.total, edges) <= 0) continue
            var at: Pair<Double, TrackLayout.Source>? = null
            val node = c.finish ?: c.start
            if (node != null) {
                val p = loop.project(frame.xy(node))
                if (p != null && p.second < 40) at = p.first to TrackLayout.Source.mapped
            }
            if (at == null) loop.besidePits(c.pits.mapNotNull { byID[it] } + pits, frame)?.let { at = it to TrackLayout.Source.pits }
            val (s, source) = at ?: (loop.longestStraight() to TrackLayout.Source.straight)
            loop.layout(c.name, s, source, width)?.let {
                out.add(it)
                kept.add(Kept(loop.total, edges))
            }
        }

        val laps = Loop.cycles(graph.first)
        val longest = max(laps.maxOfOrNull { it.first } ?: 0.0, out.maxOfOrNull { it.length } ?: 0.0)
        val pool = laps.filter { it.first >= max(800.0, 0.3 * longest) }.map { it to it.second.map { e -> e.first }.toSet() }.toMutableList()
        while (out.size < most && pool.isNotEmpty()) {
            var bestI = 0
            for (i in pool.indices) {
                val ga = gap(pool[i].first.first, pool[i].second)
                val gb = gap(pool[bestI].first.first, pool[bestI].second)
                if (ga > gb || (ga == gb && pool[i].first.first > pool[bestI].first.first)) bestI = i
            }
            val lap = pool.removeAt(bestI)
            if (gap(lap.first.first, lap.second) <= 0) break
            val loop = Loop.make(graph.first, graph.second, lap.first.second, frame) ?: continue
            var at: Pair<Double, TrackLayout.Source>? = null
            for (m in marks) {
                val p = loop.project(frame.xy(m))
                if (p != null && p.second < 40) {
                    at = p.first to TrackLayout.Source.mapped
                    break
                }
            }
            if (at == null) loop.besidePits(pits, frame)?.let { at = it to TrackLayout.Source.pits }
            if (at == null) loop.alongNamedWay()?.let { at = it to TrackLayout.Source.named }
            val (s, source) = at ?: (loop.longestStraight() to TrackLayout.Source.straight)
            // Named after the stretches only this lap has, next to the first layout.
            val name = kept.firstOrNull()?.let { f -> loop.names(lap.second - f.edges).take(2).joinToString(" · ") } ?: ""
            loop.layout(name, s, source, width)?.let {
                out.add(it)
                kept.add(Kept(loop.total, lap.second))
            }
        }
        return out
    }
}

/** One lap of a layout as a closed polyline in metres, with the junctions along it. */
private class Loop(
    val frame: LocalFrame,
    val edges: List<Edge>,
    val points: List<Vec>,
    val cum: List<Double>,
    /** Metres along the lap of every junction with another way. */
    val junctions: List<Double>,
    /** The edges of the lap, for the way names. */
    val used: List<Int>,
    val coordOf: Map<Long, Vec>,
) {
    class Edge(val from: Long, val to: Long, val nodes: List<Long>, val length: Double, val directed: Boolean, val name: String, val way: Long)

    val total: Double get() = cum.lastOrNull() ?: 0.0

    /** The names of the ways of these edges, in the order the lap meets them. */
    fun names(set: Set<Int>): List<String> {
        val out = ArrayList<String>()
        for (i in used) if (i in set && edges[i].name.isNotEmpty() && edges[i].name !in out) out.add(edges[i].name)
        return out
    }

    /** The point of the lap nearest to p: how far along the lap, and how far from p. */
    fun project(p: Vec): Pair<Double, Double>? {
        var best: Pair<Double, Double>? = null
        for (i in 0 until points.size - 1) {
            val a = points[i]
            val d = points[i + 1] - points[i]
            val l2 = max(1e-9, d.dot(d))
            val u = max(0.0, min(1.0, (p - a).dot(d) / l2))
            val dist = (a + d * u - p).length
            if (dist < (best?.second ?: Double.POSITIVE_INFINITY)) best = (cum[i] + u * Math.sqrt(l2)) to dist
        }
        return best
    }

    /** A point at s metres along the lap and the direction there. */
    fun point(s0: Double): Pair<Vec, Vec> {
        val s = ((s0 % total) + total) % total
        for (i in 0 until points.size - 1) {
            if (cum[i + 1] >= s) {
                val u = (s - cum[i]) / max(1e-9, cum[i + 1] - cum[i])
                val d = points[i + 1] - points[i]
                return (points[i] + d * u) to d.normalized
            }
        }
        return points[points.size - 1] to Vec(1.0, 0.0)
    }

    /** Beside the middle of the longest pit lane way, when it runs along the lap. */
    fun besidePits(pits: List<RacewayData.Way>, frame: LocalFrame): Double? {
        val lines = pits.map { w -> w.coords.map { frame.xy(it) } }.filter { it.size >= 2 }
        val pit = lines.maxByOrNull { length(it) } ?: return null
        val p = project(middle(pit)) ?: return null
        return if (p.second < 150) p.first else null
    }

    /** The middle of the first way of the lap named for the start. */
    fun alongNamedWay(): Double? {
        for (i in used) {
            if (!AutoLines.startWords.containsMatchIn(edges[i].name)) continue
            val pts = edges[i].nodes.mapNotNull { coordOf[it] }
            if (pts.size >= 2) project(middle(pts))?.let { return it.first }
        }
        return null
    }

    /** The middle of the longest stretch whose direction stays within 6° of where it begins. */
    fun longestStraight(): Double {
        val n = points.size
        if (n <= 2) return 0.0
        val heading = (0 until n - 1).map { atan2(points[it + 1].y - points[it].y, points[it + 1].x - points[it].x) }
        val tolerance = 6 * Math.PI / 180
        var bestLen = 0.0
        var bestMid = 0.0
        for (i in heading.indices) {
            var j = i
            while (j + 1 < heading.size && abs(angle(heading[j + 1] - heading[i])) < tolerance) j += 1
            val len = cum[j + 1] - cum[i]
            if (len > bestLen) {
                bestLen = len
                bestMid = (cum[i] + cum[j + 1]) / 2
            }
        }
        return bestMid
    }

    /** The start line at s (moved a little where it would cut another part of the track or sit on a junction). */
    fun layout(name: String, s: Double, source: TrackLayout.Source, width: Double): TrackLayout? {
        if (total <= 150) return null
        val start = fit(s, width, source == TrackLayout.Source.mapped)
        val sectors = listOf(1.0, 2.0).map { fit(start.first + total * it / 3, width, false).second }
        val path = ArrayList<Coord>()
        var x = 0.0
        while (x < total) {
            path.add(frame.coord(point(x).first))
            x += 15
        }
        return TrackLayout(name, total, start.second, sectors, source, path)
    }

    private fun fit(s: Double, width: Double, exact: Boolean): Pair<Double, GateLine> {
        if (!exact) {
            var k = 0.0
            while (k < 60) {
                for (sign in listOf(1.0, -1.0)) {
                    val at = s + sign * k
                    val g = gate(at, width)
                    if (clear(g, at)) return wrap(at) to coords(g)
                }
                k += 3
            }
        }
        return wrap(s) to coords(gate(s, width))
    }

    private fun gate(s: Double, width: Double): Pair<Vec, Vec> {
        val (p, dir) = point(s)
        val n = dir.perpendicular * (width / 2)
        return (p - n) to (p + n)
    }

    /** The line crosses the lap only where it stands, and is not on top of a junction. */
    private fun clear(g: Pair<Vec, Vec>, s0: Double): Boolean {
        val s = wrap(s0)
        for (j in junctions) if (loopDistance(j, s) < 25) return false
        for (i in 0 until points.size - 1) {
            if (Geo.intersect(g.first, g.second, points[i], points[i + 1]) != null && loopDistance(cum[i], s) > 40) return false
        }
        return true
    }

    private fun coords(g: Pair<Vec, Vec>) = GateLine(frame.coord(g.first), frame.coord(g.second))
    private fun wrap(s: Double) = ((s % total) + total) % total
    private fun loopDistance(a: Double, b: Double): Double {
        val d = abs(a - b) % total
        return min(d, total - d)
    }

    companion object {
        private fun angle(a: Double): Double {
            var x = a
            while (x > Math.PI) x -= 2 * Math.PI
            while (x < -Math.PI) x += 2 * Math.PI
            return x
        }

        fun length(pts: List<Vec>): Double = pts.zipWithNext().sumOf { (a, b) -> (b - a).length }

        fun middle(pts: List<Vec>): Vec {
            val half = length(pts) / 2
            var run = 0.0
            for ((a, b) in pts.zipWithNext()) {
                val l = (b - a).length
                if (run + l >= half) return a + (b - a) * ((half - run) / max(l, 1e-9))
                run += l
            }
            return pts[pts.size - 1]
        }

        /** The ways cut at every junction: the edges of the graph between them, and every node's place. */
        fun graph(ways: List<RacewayData.Way>, frame: LocalFrame): Pair<List<Edge>, Map<Long, Vec>>? {
            val usable = ways.filter { it.nodes.size >= 2 && it.nodes.size == it.coords.size }
            if (usable.isEmpty()) return null
            val coord = HashMap<Long, Vec>()
            val count = HashMap<Long, Int>()
            for (w in usable) {
                for ((i, n) in w.nodes.withIndex()) {
                    coord[n] = frame.xy(w.coords[i])
                    count[n] = (count[n] ?: 0) + if (i == 0 || i == w.nodes.size - 1) 2 else 1
                }
            }
            val junction = count.filter { it.value != 2 }.keys.toMutableSet()
            for (w in usable) {
                junction.add(w.nodes[0])
                junction.add(w.nodes[w.nodes.size - 1])
            }
            val edges = ArrayList<Edge>()
            for (w in usable) {
                val oneway = w.tags["oneway"] ?: ""
                val ids = if (oneway == "-1") w.nodes.reversed() else w.nodes
                val directed = oneway in listOf("yes", "-1", "1", "true")
                var seg = arrayListOf(ids[0])
                for (n in ids.drop(1)) {
                    seg.add(n)
                    if (n in junction) {
                        var len = 0.0
                        for (i in 0 until seg.size - 1) len += ((coord[seg[i + 1]] ?: Vec.ZERO) - (coord[seg[i]] ?: Vec.ZERO)).length
                        edges.add(Edge(seg[0], seg[seg.size - 1], seg.toList(), len, directed, w.tags["name"] ?: "", w.id))
                        seg = arrayListOf(n)
                    }
                }
            }
            return if (edges.isEmpty()) null else edges to coord
        }

        /** The lap along a cycle of the graph. */
        fun make(edges: List<Edge>, coord: Map<Long, Vec>, cycle: List<Pair<Int, Boolean>>, frame: LocalFrame): Loop? {
            if (cycle.isEmpty()) return null
            val pts = ArrayList<Vec>()
            val ids = ArrayList<Long>()
            for ((e, reversed) in cycle) {
                val seq = if (reversed) edges[e].nodes.reversed() else edges[e].nodes
                for (n in if (pts.isEmpty()) seq else seq.drop(1)) {
                    pts.add(coord[n] ?: Vec.ZERO)
                    ids.add(n)
                }
            }
            val cum = arrayListOf(0.0)
            for (i in 0 until pts.size - 1) cum.add(cum[i] + (pts[i + 1] - pts[i]).length)
            val total = cum.last()
            if (total <= 150) return null
            val degree = HashMap<Long, Int>()
            for (e in edges) {
                degree[e.from] = (degree[e.from] ?: 0) + 1
                degree[e.to] = (degree[e.to] ?: 0) + 1
            }
            val junctions = ids.indices.filter { (degree[ids[it]] ?: 0) > 2 }.map { cum[it] }
            return Loop(frame, edges, pts, cum, junctions, cycle.map { it.first }, coord)
        }

        private class Step(val node: Long, val path: List<Pair<Int, Boolean>>, val seen: Set<Long>, val length: Double)
        private class Next(val to: Long, val edge: Int, val reversed: Boolean)

        private fun adjacency(edges: List<Edge>, only: Set<Long>?): Map<Long, List<Next>> {
            val adj = HashMap<Long, ArrayList<Next>>()
            for ((i, e) in edges.withIndex()) {
                if (only != null && e.way !in only) continue
                adj.getOrPut(e.from) { ArrayList() }.add(Next(e.to, i, false))
                if (!e.directed) adj.getOrPut(e.to) { ArrayList() }.add(Next(e.from, i, true))
            }
            return adj
        }

        /** Every simple cycle, by depth-first search over the junctions; a budget and a limit keep a huge network short. */
        fun cycles(edges: List<Edge>, budget: Int = 300_000, limit: Int = 3000): List<Pair<Double, List<Pair<Int, Boolean>>>> {
            val adj = adjacency(edges, null)
            val found = ArrayList<Pair<Double, List<Pair<Int, Boolean>>>>()
            var steps = 0
            for (s in adj.keys.sorted()) {
                val stack = arrayListOf(Step(s, emptyList(), setOf(s), 0.0))
                while (steps < budget && found.size < limit && stack.isNotEmpty()) {
                    val top = stack.removeAt(stack.size - 1)
                    steps += 1
                    for (next in adj[top.node] ?: emptyList()) {
                        if (top.path.any { it.first == next.edge }) continue
                        val l = top.length + edges[next.edge].length
                        if (next.to == s) {
                            found.add(l to (top.path + (next.edge to next.reversed)))
                            continue
                        }
                        if (next.to in top.seen || next.to < s) continue
                        stack.add(Step(next.to, top.path + (next.edge to next.reversed), top.seen + next.to, l))
                    }
                }
            }
            return found
        }

        /** The longest simple cycle, by depth-first search over the junctions, keeping the best found within a budget. */
        fun longestCycle(edges: List<Edge>, only: Set<Long>? = null, budget: Int = 300_000): List<Pair<Int, Boolean>>? {
            val adj = adjacency(edges, only)
            var best: Pair<Double, List<Pair<Int, Boolean>>>? = null
            var steps = 0
            for (s in adj.keys.sorted()) {
                val stack = arrayListOf(Step(s, emptyList(), setOf(s), 0.0))
                while (steps < budget && stack.isNotEmpty()) {
                    val top = stack.removeAt(stack.size - 1)
                    steps += 1
                    for (next in adj[top.node] ?: emptyList()) {
                        if (top.path.any { it.first == next.edge }) continue
                        val l = top.length + edges[next.edge].length
                        if (next.to == s) {
                            if (l > (best?.first ?: 0.0)) best = l to (top.path + (next.edge to next.reversed))
                            continue
                        }
                        if (next.to in top.seen || next.to < s) continue
                        stack.add(Step(next.to, top.path + (next.edge to next.reversed), top.seen + next.to, l))
                    }
                }
            }
            return best?.second
        }
    }
}

/**
 * Which layout a lap was driven on: the one nearest the lap, measured both ways, taken only when it
 * is clearly nearer than the next. Layouts too alike to call keep the one chosen in the editor.
 */
object LayoutMatch {
    fun best(trace: List<TracePoint>, layouts: List<TrackLayout>): TrackLayout? {
        if (trace.size <= 20) return null
        val f = LocalFrame(Coord(trace[0].lat, trace[0].lon))
        val lap = trace.map { f.xy(Coord(it.lat, it.lon)) }
        val scored = layouts.mapNotNull { l ->
            val path = l.path ?: return@mapNotNull null
            if (path.size <= 3) return@mapNotNull null
            val p = path.map { f.xy(it) } + f.xy(path[0])
            l to (meanDistance(lap, p) + meanDistance(p, lap))
        }.sortedBy { it.second }
        val first = scored.firstOrNull() ?: return null
        if (first.second >= 10) return null
        if (scored.size > 1 && scored[1].second - first.second < 0.6) return null
        return first.first
    }

    /** The mean distance of line a from line b, every 5 m of a, each at most 50 m. */
    fun meanDistance(a: List<Vec>, b: List<Vec>, cap: Double = 50.0): Double {
        var sum = 0.0
        var count = 0
        for ((p, q) in a.zipWithNext()) {
            val n = max(1, ((q - p).length / 5).toInt())
            for (k in 0 until n) {
                val m = p + (q - p) * (k.toDouble() / n)
                var near = cap
                for ((u, v) in b.zipWithNext()) {
                    val d = v - u
                    val t = max(0.0, min(1.0, (m - u).dot(d) / max(1e-9, d.dot(d))))
                    near = min(near, (u + d * t - m).length)
                    if (near < 1) break
                }
                sum += near
                count += 1
            }
        }
        return if (count == 0) cap else sum / count
    }

    /** A lap's sector times on other lines, from its trace; empty when it does not cross them all. */
    fun sectors(lap: Lap, gates: List<GateLine>): List<Double> {
        if (gates.isEmpty()) return emptyList()
        val at = gates.mapNotNull { lap.timeCrossing(it) }.sorted()
        if (at.size != gates.size) return emptyList()
        val out = ArrayList<Double>()
        var last = 0.0
        for (t in at) {
            out.add(t - last)
            last = t
        }
        out.add(lap.time - last)
        return out
    }
}
