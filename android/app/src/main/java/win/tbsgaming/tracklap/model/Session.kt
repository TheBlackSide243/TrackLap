package win.tbsgaming.tracklap.model

import kotlinx.serialization.Serializable

@Serializable
data class TracePoint(
    /** Seconds since the start of the lap. */
    val t: Double,
    /** Metres since the start of the lap. */
    val d: Double,
    val lat: Double,
    val lon: Double,
    /** Speed in m/s. */
    val v: Double,
)

@Serializable
data class Lap(
    val id: String = newID(),
    val number: Int,
    val startedAt: Double,
    val time: Double,
    val sectors: List<Double>,
    val distance: Double,
    val maxSpeed: Double,
    val trace: List<TracePoint>,
) {
    /** When the lap crossed a line, from its trace (not before the first 3 s). */
    fun timeCrossing(gate: GateLine): Double? {
        val f = LocalFrame(gate.mid)
        val a = f.xy(gate.a)
        val b = f.xy(gate.b)
        var prev: Pair<TracePoint, Vec>? = null
        for (p in trace) {
            val xy = f.xy(Coord(p.lat, p.lon))
            val q = prev
            if (q != null && q.first.t > 3) {
                val u = Geo.intersect(q.second, xy, a, b)
                if (u != null) return q.first.t + (p.t - q.first.t) * u
            }
            prev = p to xy
        }
        return null
    }
}

@Serializable
data class Session(
    val id: String = newID(),
    val trackID: String?,
    val trackName: String,
    val date: Double,
    val source: String,
    val sectorCount: Int,
    val laps: List<Lap> = emptyList(),
    val carID: String? = null,
    val carName: String? = null,
    /** The layout of the track it was driven on (TrackLayout.key). */
    val layout: String? = null,
) {
    val best: Lap? get() = laps.minByOrNull { it.time }

    /** Best time for each sector, over the laps that recorded all of them. */
    val bestSectors: List<Double>
        get() {
            if (sectorCount == 0) return emptyList()
            val full = laps.filter { it.sectors.size == sectorCount }
            if (full.isEmpty()) return emptyList()
            return (0 until sectorCount).map { k -> full.minOf { it.sectors[k] } }
        }

    val idealTime: Double? get() = bestSectors.takeIf { it.isNotEmpty() }?.sum()
    val averageTime: Double? get() = if (laps.isEmpty()) null else laps.sumOf { it.time } / laps.size

    val summary: SessionSummary
        get() = SessionSummary(id, trackID, trackName, date, source, laps.size, best?.time, idealTime, carID, carName, layout)
}

/** What the session list needs, kept apart so the full traces load only when a session opens. */
@Serializable
data class SessionSummary(
    val id: String,
    val trackID: String?,
    val trackName: String,
    val date: Double,
    val source: String,
    val lapCount: Int,
    val best: Double?,
    val ideal: Double?,
    val carID: String? = null,
    val carName: String? = null,
    val layout: String? = null,
) {
    /** The layout's name, when it has one. */
    val layoutName: String? get() = layout?.split("|")?.firstOrNull()?.takeIf { it.isNotEmpty() }
}

/** The two points around a distance along the lap and how far between them it falls. */
private fun List<TracePoint>.bracket(d: Double): Triple<TracePoint, TracePoint, Double>? {
    if (isEmpty()) return null
    val first = first()
    val last = last()
    if (d <= first.d) return Triple(first, first, 0.0)
    if (d >= last.d) return Triple(last, last, 0.0)
    var lo = 0
    var hi = size - 1
    while (hi - lo > 1) {
        val mid = (lo + hi) / 2
        if (this[mid].d < d) lo = mid else hi = mid
    }
    val a = this[lo]
    val b = this[hi]
    return Triple(a, b, if (b.d > a.d) (d - a.d) / (b.d - a.d) else 0.0)
}

/** Elapsed time at a distance along the lap, linearly interpolated. */
fun List<TracePoint>.timeAtDistance(d: Double): Double {
    val (a, b, f) = bracket(d) ?: return 0.0
    return a.t + (b.t - a.t) * f
}

/** Time, position and speed at a distance along the lap. */
fun List<TracePoint>.pointAtDistance(d: Double): TracePoint? {
    val (a, b, f) = bracket(d) ?: return null
    return TracePoint(a.t + (b.t - a.t) * f, d, a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f, a.v + (b.v - a.v) * f)
}

/** Index of the last point at or before a distance. */
fun List<TracePoint>.indexAtDistance(d: Double): Int {
    var lo = 0
    var hi = size - 1
    if (hi <= 0 || d <= this[0].d) return 0
    if (d >= this[hi].d) return hi
    while (hi - lo > 1) {
        val mid = (lo + hi) / 2
        if (this[mid].d <= d) lo = mid else hi = mid
    }
    return lo
}

/**
 * A lap against a reference lap, matched by the share of the lap driven: a slightly longer or
 * shorter line does not pile up as delta, and at the line the delta is the difference of the times.
 */
class LapComparison(val lap: Lap, val ref: Lap) {
    val scale: Double get() = if (lap.distance > 0 && ref.distance > 0) ref.distance / lap.distance else 1.0
    fun delta(d: Double) = lap.trace.timeAtDistance(d) - ref.trace.timeAtDistance(d * scale)
    fun refPoint(d: Double) = ref.trace.pointAtDistance(d * scale)
}
