package win.tbsgaming.tracklap.gps

import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.Geo
import win.tbsgaming.tracklap.model.LocalFrame
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.model.Vec
import win.tbsgaming.tracklap.timing.Sample
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/** A clock of 10 Hz on the main thread, for the simulated cars. */
internal class Ticker(private val step: () -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private var running = false
    private val tick = object : Runnable {
        override fun run() {
            if (!running) return
            step()
            if (running) handler.postDelayed(this, 100)
        }
    }

    fun start() {
        stop()
        running = true
        handler.postDelayed(tick, 100)
    }

    fun stop() {
        running = false
        handler.removeCallbacks(tick)
    }
}

/**
 * A simulated car lapping the selected track at 10 Hz: it follows the OpenStreetMap layout when that
 * closes into a loop through the start line, otherwise a generated circuit through the line.
 */
class DemoDriver {
    /** Driver pace, 1 = on the limit. */
    var pace by mutableStateOf(0.97)
    var isRunning by mutableStateOf(false); private set
    var onSample: ((Sample) -> Unit)? = null

    private val ticker = Ticker { tick() }
    private var frame = LocalFrame(Coord(0.0, 0.0))
    private var path: List<Vec> = emptyList()
    private var cum: List<Double> = emptyList()
    private var vmax: List<Double> = emptyList()
    private var total = 1.0
    private var s = 0.0
    private var v = 15.0
    private var t = 0.0
    private var lapNoise = listOf(1.0)

    fun start(track: Track) {
        stop()
        build(track)
        t = System.currentTimeMillis() / 1000.0
        newLapNoise()
        ticker.start()
        isRunning = true
    }

    fun stop() {
        ticker.stop()
        isRunning = false
    }

    private fun tick() {
        val now = System.currentTimeMillis() / 1000.0
        val dt = min(0.3, max(0.01, now - t))
        t = now
        onSample?.invoke(advance(dt, now))
    }

    private fun advance(dt: Double, time: Double): Sample {
        val i = index(s)
        val section = min(lapNoise.size - 1, (s / total * lapNoise.size).toInt())
        val target = vmax[i] * pace * lapNoise[section]
        v = if (target > v) min(target, v + 6.5 * dt) else max(target, v - 14 * dt)
        s += v * dt
        if (s >= total) {
            s -= total
            newLapNoise()
        }
        val (pos, dir) = point(s)
        val jitter = Vec(Random.nextDouble(-0.3, 0.3), Random.nextDouble(-0.3, 0.3))
        val heading = (atan2(dir.x, dir.y) * 180 / Math.PI + 360) % 360
        return Sample(time, frame.coord(pos + jitter), v, heading, wall = time)
    }

    private fun newLapNoise() {
        val form = Random.nextDouble(0.985, 1.01)
        lapNoise = List(6) { form * Random.nextDouble(0.98, 1.02) }
    }

    private fun build(track: Track) {
        frame = LocalFrame(track.start?.mid ?: track.center)
        val gate = track.start?.let { frame.xy(it.a) to frame.xy(it.b) }
        val raw = osmLoop(track, frame, gate) ?: syntheticLoop(gate)
        path = resample(raw, 2.0)
        val n = path.size
        val c = ArrayList<Double>(n)
        c.add(0.0)
        for (i in 1 until n) c.add(c[i - 1] + (path[i] - path[i - 1]).length)
        cum = c
        total = c[n - 1] + (path[0] - path[n - 1]).length
        vmax = speedProfile(path, 2.0)

        // Start 150 m before the line, so the first lap begins almost at once.
        var crossing = 0
        if (gate != null) {
            for (i in 0 until n) {
                if (Geo.intersect(path[i], path[(i + 1) % n], gate.first, gate.second) != null) {
                    crossing = i
                    break
                }
            }
        }
        s = ((cum[crossing] - 150 + total) % total)
        v = vmax[index(s)] * 0.9
    }

    private fun index(s: Double): Int {
        var lo = 0
        var hi = cum.size - 1
        while (hi - lo > 1) {
            val mid = (lo + hi) / 2
            if (cum[mid] <= s) lo = mid else hi = mid
        }
        return if (cum[hi] <= s) hi else lo
    }

    private fun point(s: Double): Pair<Vec, Vec> {
        val n = path.size
        val i = index(s)
        val j = (i + 1) % n
        val segLen = if (i == n - 1) total - cum[i] else cum[i + 1] - cum[i]
        val f = if (segLen > 0) (s - cum[i]) / segLen else 0.0
        val dir = path[j] - path[i]
        return (path[i] + dir * f) to dir.normalized
    }

    companion object {
        /** The OpenStreetMap ways chained into one closed loop that crosses the start line, if they make one. */
        fun osmLoop(track: Track, frame: LocalFrame, gate: Pair<Vec, Vec>?): List<Vec>? {
            if (gate == null) return null
            val ways = track.outline.filter { it.size >= 2 }.sortedByDescending { Geo.length(it) }
            for ((i, seed) in ways.withIndex()) {
                val others = ways.toMutableList().also { it.removeAt(i) }
                val loop = chain(seed, others) ?: continue
                val pts = loop.map { frame.xy(it) }
                for (k in 1 until pts.size) {
                    if (Geo.intersect(pts[k - 1], pts[k], gate.first, gate.second) != null) return pts
                }
            }
            return null
        }

        private fun chain(seed: List<Coord>, pool0: List<List<Coord>>): List<Coord>? {
            val line = seed.toMutableList()
            val pool = pool0.toMutableList()
            repeat(80) {
                if (line.size > 10 && Geo.distance(line.first(), line.last()) < 40 && Geo.length(line) > 500) return line
                val end = line.lastOrNull() ?: return null
                val i = pool.indexOfFirst { Geo.distance(end, it[0]) < 8 || Geo.distance(end, it[it.size - 1]) < 8 }
                if (i < 0) return null
                val w = pool.removeAt(i)
                if (Geo.distance(end, w[0]) < 8) line += w.drop(1) else line += w.reversed().drop(1)
            }
            return null
        }

        /** A twisty closed circuit of about 2.8 km, placed so it crosses the gate at its midpoint. */
        fun syntheticLoop(gate: Pair<Vec, Vec>?): List<Vec> {
            val n = 1600
            val raw = ArrayList<Vec>(n)
            for (i in 0 until n) {
                val th = 2 * Math.PI * i / n
                val r = 360 * (1 + 0.22 * sin(2 * th) + 0.12 * cos(3 * th + 0.6) + 0.07 * sin(5 * th + 1.1))
                raw.add(Vec(r * cos(th), r * sin(th)))
            }
            val p0 = raw[0]
            val t0 = (raw[1] - raw[n - 1]).normalized
            var mid = Vec(0.0, 0.0)
            var dir = Vec(0.0, 1.0)
            if (gate != null) {
                mid = (gate.first + gate.second) * 0.5
                dir = (gate.second - gate.first).normalized.perpendicular
            }
            val ang = atan2(dir.y, dir.x) - atan2(t0.y, t0.x)
            val c = cos(ang)
            val sn = sin(ang)
            return raw.map { p ->
                val q = p - p0
                Vec(q.x * c - q.y * sn, q.x * sn + q.y * c) + mid
            }
        }

        fun resample(pts: List<Vec>, spacing: Double): List<Vec> {
            if (pts.size <= 2) return pts
            val closed = pts.toMutableList()
            if ((pts.first() - pts.last()).length > 0.5) closed.add(pts.first())
            val out = arrayListOf(closed[0])
            var carry = 0.0
            for (i in 1 until closed.size) {
                val a = closed[i - 1]
                val b = closed[i]
                val seg = (b - a).length
                if (seg <= 0) continue
                var pos = spacing - carry
                while (pos <= seg) {
                    out.add(a + (b - a) * (pos / seg))
                    pos += spacing
                }
                carry = seg - (pos - spacing)
            }
            if ((out.last() - out[0]).length < spacing * 0.5) out.removeAt(out.size - 1)
            return out
        }

        /** Cornering speed from the curvature (about 1.1 g), then acceleration and braking limits around the loop. */
        fun speedProfile(p: List<Vec>, ds: Double): List<Double> {
            val n = p.size
            val v = DoubleArray(n) { 72.0 }
            val k = 6
            for (i in 0 until n) {
                val a = p[(i - k + n) % n]
                val b = p[i]
                val c = p[(i + k) % n]
                val ab = (b - a).length
                val bc = (c - b).length
                val ca = (a - c).length
                val den = ab * bc * ca
                val curvature = if (den > 0) 2 * abs((b - a).cross(c - a)) / den else 0.0
                v[i] = min(72.0, sqrt(11.0 / max(curvature, 1e-5)))
            }
            repeat(2) {
                for (i in 1 until 2 * n) {
                    val j = i % n
                    val pj = (i - 1) % n
                    v[j] = min(v[j], sqrt(v[pj] * v[pj] + 2 * 6.5 * ds))
                }
                for (i in 2 * n - 2 downTo 0) {
                    val j = i % n
                    val nj = (i + 1) % n
                    v[j] = min(v[j], sqrt(v[nj] * v[nj] + 2 * 13 * ds))
                }
            }
            return v.toList()
        }
    }
}

/**
 * A simulated drag run at 10 Hz on a straight road: a few seconds standing, full throttle with
 * gear changes for a kilometre, then a hard stop. A hot hatch: 0–100 in under 5 s.
 */
class DemoDrag {
    var isRunning by mutableStateOf(false); private set
    var onSample: ((Sample) -> Unit)? = null

    private val ticker = Ticker { tick() }
    private var car = Car(Coord(0.0, 0.0))
    private var t = 0.0

    fun start(origin: Coord, power: Double = 1.0) {
        stop()
        car = Car(origin, power)
        t = System.currentTimeMillis() / 1000.0
        ticker.start()
        isRunning = true
    }

    fun stop() {
        ticker.stop()
        isRunning = false
    }

    /** A clock of its own, a tenth of a second a fix like a GPS: a busy main thread slows the run instead of making a gap. */
    private fun tick() {
        t += 0.1
        onSample?.invoke(car.advance(0.1, t, System.currentTimeMillis() / 1000.0))
        if (car.done) stop()
    }

    private class Car(origin: Coord, val power: Double = 1.0) {
        val frame = LocalFrame(origin)
        val heading = 32.0
        var s = 0.0
        var v = 0.0
        var clock = 0.0
        var shiftUntil = 0.0
        var gear = 1
        var braking = false
        var stoppedAt: Double? = null

        val done: Boolean get() = stoppedAt?.let { clock - it > 3 } ?: false

        fun advance(dt: Double, time: Double, wall: Double): Sample {
            clock += dt
            if (clock > 3 && stoppedAt == null) {
                val a = when {
                    braking -> -10.2
                    clock < shiftUntil -> 0.4
                    // Grip first, then power, less the air.
                    else -> min(6.4, 165 * power / max(v, 1.0)) - 0.0005 * v * v - 0.12
                }
                v = max(0.0, v + a * dt)
                if (!braking && gear <= SHIFTS.size && v * 3.6 >= SHIFTS[gear - 1]) {
                    gear += 1
                    shiftUntil = clock + 0.2
                }
                if (!braking && s >= 1020) braking = true
                if (braking && v == 0.0) stoppedAt = clock
                s += v * dt
            }
            val dir = Vec(sin(heading * Math.PI / 180), cos(heading * Math.PI / 180))
            val jitter = Vec(Random.nextDouble(-0.25, 0.25), Random.nextDouble(-0.25, 0.25))
            val noise = if (v > 0) Random.nextDouble(-0.06, 0.06) else 0.0
            // A gentle climb of 0.4%.
            val alt = 120 + s * 0.004 + Random.nextDouble(-0.15, 0.15)
            return Sample(time, frame.coord(dir * s + jitter), max(0.0, v + noise), heading, wall = wall, utc = time, alt = alt)
        }

        companion object {
            /** km/h where it changes up. */
            val SHIFTS = listOf(58.0, 98.0, 140.0, 182.0, 220.0)
        }
    }
}
