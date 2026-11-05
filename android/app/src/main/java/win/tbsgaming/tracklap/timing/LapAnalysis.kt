package win.tbsgaming.tracklap.timing

import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.LocalFrame
import win.tbsgaming.tracklap.model.TracePoint
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** Lateral and longitudinal acceleration in g at one point of a lap. */
data class GPoint(val lateral: Double = 0.0, val longitudinal: Double = 0.0) {
    val total: Double get() = sqrt(lateral * lateral + longitudinal * longitudinal)
}

object GForce {
    /**
     * One value per trace point, from the GPS alone so it works with every source: the turn rate
     * times the speed for the lateral, the change of speed for the longitudinal, each over about
     * half a second around the point. Points it cannot work out are zero.
     */
    fun along(trace: List<TracePoint>): List<GPoint> {
        val n = trace.size
        val out = MutableList(n) { GPoint() }
        if (n <= 4) return out
        val f = LocalFrame(Coord(trace[0].lat, trace[0].lon))
        val xy = trace.map { f.xy(Coord(it.lat, it.lon)) }
        val window = 0.3
        var j = 0
        var l = 0
        for (i in 0 until n) {
            while (j + 1 < i && trace[i].t - trace[j + 1].t >= window) j += 1
            l = max(l, i)
            while (l + 1 < n && trace[l].t - trace[i].t < window) l += 1
            if (j >= i || l <= i) continue
            val a = xy[i] - xy[j]
            val b = xy[l] - xy[i]
            val span = trace[l].t - trace[j].t
            if (a.length <= 0.5 || b.length <= 0.5 || span <= 0) continue
            // Counter-clockwise is a left turn in the east/north frame.
            val turn = atan2(a.cross(b), a.dot(b))
            val lateral = -trace[i].v * turn / (span / 2) / 9.81
            val longitudinal = (trace[l].v - trace[j].v) / span / 9.81
            out[i] = GPoint(clamp(lateral), clamp(longitudinal))
        }
        return smooth(out)
    }

    private fun clamp(g: Double) = max(-3.0, min(3.0, g))

    private fun smooth(g: List<GPoint>): List<GPoint> {
        if (g.size <= 2) return g
        val out = g.toMutableList()
        for (i in 1 until g.size - 1) {
            out[i] = GPoint(
                (g[i - 1].lateral + 2 * g[i].lateral + g[i + 1].lateral) / 4,
                (g[i - 1].longitudinal + 2 * g[i].longitudinal + g[i + 1].longitudinal) / 4,
            )
        }
        return out
    }
}

object Corners {
    /**
     * The slowest point of each corner: a speed minimum over 80 m either side, with at least
     * 3 m/s (about 11 km/h) more speed both on the way in and on the way out.
     */
    fun apexes(trace: List<TracePoint>): List<TracePoint> {
        val n = trace.size
        if (n <= 10) return emptyList()
        val near = 80.0
        val far = 250.0
        val drop = 3.0
        val out = ArrayList<TracePoint>()
        for (i in 0 until n) {
            val p = trace[i]
            var isMin = true
            var before = p.v
            var after = p.v
            var k = i - 1
            while (k >= 0 && p.d - trace[k].d <= far) {
                if (p.d - trace[k].d <= near && trace[k].v < p.v) { isMin = false; break }
                before = max(before, trace[k].v)
                k -= 1
            }
            if (!isMin) continue
            k = i + 1
            while (k < n && trace[k].d - p.d <= far) {
                // Ties go to the first point, so a flat minimum gives one apex.
                if (trace[k].d - p.d <= near && trace[k].v <= p.v) { isMin = false; break }
                after = max(after, trace[k].v)
                k += 1
            }
            if (isMin && before >= p.v + drop && after >= p.v + drop) out.add(p)
        }
        return out
    }
}
