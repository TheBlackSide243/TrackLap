package win.tbsgaming.tracklap.model

import kotlinx.serialization.Serializable
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

@Serializable
data class Coord(val lat: Double, val lon: Double)

/** A point or a direction in metres, east and north. */
data class Vec(val x: Double, val y: Double) {
    operator fun plus(o: Vec) = Vec(x + o.x, y + o.y)
    operator fun minus(o: Vec) = Vec(x - o.x, y - o.y)
    operator fun times(k: Double) = Vec(x * k, y * k)
    operator fun div(k: Double) = Vec(x / k, y / k)
    val length: Double get() = sqrt(x * x + y * y)
    val normalized: Vec get() = length.let { if (it > 0) this / it else this }
    val perpendicular: Vec get() = Vec(-y, x)
    fun dot(o: Vec) = x * o.x + y * o.y
    fun cross(o: Vec) = x * o.y - y * o.x

    companion object {
        val ZERO = Vec(0.0, 0.0)
    }
}

/** Flat east/north projection in metres around an origin: a few millimetres of error across a race track. */
class LocalFrame(val origin: Coord) {
    val mPerDegLat: Double
    val mPerDegLon: Double

    init {
        val phi = origin.lat * Math.PI / 180
        mPerDegLat = 111_132.92 - 559.82 * cos(2 * phi) + 1.175 * cos(4 * phi)
        mPerDegLon = 111_412.84 * cos(phi) - 93.5 * cos(3 * phi)
    }

    fun xy(c: Coord) = Vec((c.lon - origin.lon) * mPerDegLon, (c.lat - origin.lat) * mPerDegLat)
    fun coord(p: Vec) = Coord(origin.lat + p.y / mPerDegLat, origin.lon + p.x / mPerDegLon)
}

object Geo {
    fun distance(a: Coord, b: Coord): Double {
        val r = 6_371_000.0
        val dLat = (b.lat - a.lat) * Math.PI / 180
        val dLon = (b.lon - a.lon) * Math.PI / 180
        val la1 = a.lat * Math.PI / 180
        val la2 = b.lat * Math.PI / 180
        val h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1.0, sqrt(h)))
    }

    fun length(way: List<Coord>): Double {
        if (way.size < 2) return 0.0
        var total = 0.0
        for (i in 1 until way.size) total += distance(way[i - 1], way[i])
        return total
    }

    /** Where the step p→q crosses the segment a–b, as a fraction of the step (0..<1), or null. */
    fun intersect(p: Vec, q: Vec, a: Vec, b: Vec): Double? {
        val r = q - p
        val s = b - a
        val den = r.cross(s)
        if (abs(den) < 1e-12) return null
        val ap = a - p
        val u = ap.cross(s) / den
        val v = ap.cross(r) / den
        return if (u >= 0 && u < 1 && v >= 0 && v <= 1) u else null
    }
}

/** A latitude/longitude rectangle: a circuit's area on OpenStreetMap, or the box to search in. */
@Serializable
data class GeoBox(val minLat: Double, val minLon: Double, val maxLat: Double, val maxLon: Double) {
    val center: Coord get() = Coord((minLat + maxLat) / 2, (minLon + maxLon) / 2)

    /** In square degrees, which is what the OpenStreetMap API limits. */
    val area: Double get() = (maxLat - minLat) * (maxLon - minLon)

    fun padded(meters: Double): GeoBox {
        val dLat = meters / 111_320
        val dLon = meters / (111_320 * max(0.2, cos(center.lat * Math.PI / 180)))
        return GeoBox(minLat - dLat, minLon - dLon, maxLat + dLat, maxLon + dLon)
    }

    fun contains(c: Coord) = c.lat in minLat..maxLat && c.lon in minLon..maxLon

    companion object {
        fun around(c: Coord, meters: Double): GeoBox {
            val dLat = meters / 111_320
            val dLon = meters / (111_320 * max(0.2, cos(c.lat * Math.PI / 180)))
            return GeoBox(c.lat - dLat, c.lon - dLon, c.lat + dLat, c.lon + dLon)
        }
    }
}
