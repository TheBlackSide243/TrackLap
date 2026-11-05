package win.tbsgaming.tracklap.timing

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.DragMeasure
import win.tbsgaming.tracklap.model.DragPoint
import win.tbsgaming.tracklap.model.DragResult
import win.tbsgaming.tracklap.model.DragRun
import win.tbsgaming.tracklap.model.newID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** A measure just done, for the banner, the voice and the ESP32. */
data class DragEvent(
    val id: String = newID(),
    val result: DragResult,
    val measure: DragMeasure,
    /** The best ever for this measure (the first one is, too). */
    val isBest: Boolean,
    /** Better than an earlier best. */
    val isRecord: Boolean,
)

/**
 * Drag timing from a stream of fixes, the way a performance meter does it: stop, press the start
 * button, and the run starts when the car moves off; it ends when the car stops again or stops
 * accelerating. Times come from the GPS speed (Doppler, far steadier than positions) and the
 * distance from integrating it, each threshold interpolated between the two fixes around it.
 * While moving, an overtake (80–120) or a stop from 100 is a rolling run of its own.
 */
class DragEngine {
    enum class Phase { moving, ready, running }

    @set:JvmName("assignPhase") var phase by mutableStateOf(Phase.moving); private set
    var speed by mutableStateOf(0.0); private set
    /** m/s² over the last half second. */
    var accel by mutableStateOf(0.0); private set
    /** Metres since the launch of the run in progress. */
    var distance by mutableStateOf(0.0); private set
    /** The run in progress, then the last one until the next begins. */
    var run by mutableStateOf<DragRun?>(null); private set
    var inProgress by mutableStateOf(false); private set
    /** When the run in progress started (seconds since 1970), for the clock between fixes. */
    var startWall by mutableStateOf<Double?>(null); private set
    var lastEvent by mutableStateOf<DragEvent?>(null); private set
    /** The start button was pressed: ready as soon as the car is still, until a run gets going. */
    var armed by mutableStateOf(false); private set

    /** The best time of each measure in earlier runs (the shortest distance for braking). */
    var bests: MutableMap<String, Double> = HashMap()
    /** Standing times count from when the car has moved a foot, like on a drag strip. */
    var rollout = false
    var source = "demo"
    var vehicle = ""
    var carID: String? = null
    /** A run from a standstill needs the start button first (the default). Off, a second still is enough. */
    var needsArming = false

    var onEvent: ((DragEvent) -> Unit)? = null
    var onFinish: ((DragRun) -> Unit)? = null
    var onPhase: ((Phase) -> Unit)? = null

    companion object {
        const val STILL_SPEED = 0.5
        const val LAUNCH_SPEED = 0.8
        const val CONFIRM_SPEED = 3.0
        const val ROLLOUT_DISTANCE = 0.3048
    }

    private class Fix(val t: Double, val v: Double, val alt: Double?, val coord: Coord, val wall: Double)
    private class Mark(val t: Double, val d: Double, val alt: Double?)
    private class At(val t: Double, val v: Double, val d: Double, val alt: Double?)

    /** The run being timed. */
    private class Live(val standing: Boolean, val t0: Double, val wall: Double, val start: Coord, val rollout: Boolean) {
        val id = newID()
        val measures = DragMeasure.all()
        var confirmed = !standing
        var zero: Mark? = null
        var d = 0.0
        val done = HashSet<String>()
        val rolling = HashMap<String, Mark>()
        val braking = HashMap<String, Mark>()
        val results = ArrayList<DragResult>()
        val trace = ArrayList<DragPoint>()
        var maxSpeed = 0.0
        var peakG = 0.0
        var lastActivity = t0
        var lastT = t0
        var fixes = 1
        val counts: Boolean get() = confirmed && (standing || results.isNotEmpty())
    }

    private var prev: Fix? = null
    private val recent = ArrayList<Fix>()
    private var stillSince: Double? = null
    private var live: Live? = null
    private var shownBefore: DragRun? = null

    /** The start button: ready at once if the car is still, else as soon as it stops. */
    fun arm() {
        if (live != null && inProgress) return
        armed = true
        if (speed < STILL_SPEED && live == null) setPhase(Phase.ready)
    }

    /** The start button again, before going: not ready any more. */
    fun disarm() {
        armed = false
        if (phase == Phase.ready) setPhase(Phase.moving)
    }

    fun reset() {
        armed = false
        live = null
        prev = null
        recent.clear()
        stillSince = null
        inProgress = false
        startWall = null
        distance = 0.0
        accel = 0.0
        speed = 0.0
        setPhase(Phase.moving)
    }

    /** Puts a finished run on screen, as if just driven. */
    fun show(r: DragRun?) {
        run = r
    }

    fun ingest(s: Sample) {
        val f = Fix(s.t, max(0.0, s.speed), s.alt, s.coord, s.wall)
        speed = f.v
        val p = prev
        if (p == null || f.t <= p.t) {
            if (p == null) prev = f
            return
        }
        prev = f
        val dt = f.t - p.t
        if (dt > 2) {
            // The signal was lost: nothing is interpolated across the gap.
            finish()
            stillSince = null
            recent.clear()
            recent.add(f)
            setPhase(Phase.moving)
            return
        }
        recent.add(f)
        recent.removeAll { f.t - it.t > 3 }
        accel = acceleration()

        live?.let { advance(it, p, f, dt) }
        if (live == null) {
            if (phase == Phase.ready && f.v >= LAUNCH_SPEED) launch(p, f, dt)
            else if (phase == Phase.moving) rollingStart(p, f, dt)
        }

        if (f.v < STILL_SPEED) {
            if (stillSince == null) stillSince = f.t
            // A second still, give or take a fix of the phone's; at once after the start button.
            val still = stillSince
            if (live == null && (armed || (!needsArming && still != null && f.t - still >= 0.9))) setPhase(Phase.ready)
        } else {
            stillSince = null
            if (live == null && (phase != Phase.ready || f.v >= LAUNCH_SPEED)) setPhase(Phase.moving)
        }
    }

    // Runs

    private fun launch(p: Fix, f: Fix, dt: Double) {
        // Back to the moment the car moved off: the line through the speeds since it was last still,
        // down to zero; not before it was last still.
        val still = recent.lastOrNull { it.v <= 0.1 && it.t <= p.t }?.t
        val moving = recent.filter { it.t > (still ?: Double.NEGATIVE_INFINITY) && it.v > 0.1 }
        var guess = f.t - dt * f.v / max(f.v - p.v, 0.01)
        if (moving.size >= 2) {
            val n = moving.size.toDouble()
            val tm = moving.sumOf { it.t } / n
            val vm = moving.sumOf { it.v } / n
            val num = moving.sumOf { (it.t - tm) * (it.v - vm) }
            val den = moving.sumOf { (it.t - tm) * (it.t - tm) }
            if (den > 0 && num / den > 0.5) guess = tm - vm / (num / den)
        }
        val t0 = min(f.t, max(max(still ?: (p.t - dt), f.t - max(2 * dt, 0.5)), guess))
        val r = Live(true, t0, f.wall + (t0 - f.t), p.coord, rollout)
        r.d = f.v / 2 * (f.t - t0)
        r.lastT = f.t
        r.maxSpeed = f.v
        r.trace.add(DragPoint(0.0, 0.0, 0.0))
        r.trace.add(DragPoint(f.t - t0, r.d, f.v))
        if (!rollout) {
            r.zero = Mark(t0, 0.0, p.alt ?: f.alt)
        } else if (r.d >= ROLLOUT_DISTANCE) {
            // At a steady acceleration the distance grows with the square of the time.
            r.zero = Mark(t0 + (f.t - t0) * sqrt(ROLLOUT_DISTANCE / r.d), ROLLOUT_DISTANCE, f.alt)
        }
        live = r
        distance = r.d
        if (f.v >= CONFIRM_SPEED) confirm(r)
    }

    private fun confirm(r: Live) {
        r.confirmed = true
        // One press, one run: the next one from a standstill needs the button again.
        armed = false
        shownBefore = run
        inProgress = true
        startWall = r.wall
        publish(r)
        setPhase(Phase.running)
    }

    /**
     * While moving: crossing the lower speed of an overtake, or slowing through the speed a stop is
     * timed from, starts a rolling run, with the fixes of the last two seconds before it.
     */
    private fun rollingStart(p: Fix, f: Fix, dt: Double) {
        val starts = DragMeasure.all().any { m ->
            (m.kind == DragMeasure.Kind.speed && m.from > 0 && p.v < m.from && f.v >= m.from) ||
                (m.kind == DragMeasure.Kind.braking && p.v > m.from && f.v <= m.from)
        }
        if (!starts) return
        val seed = recent.filter { it.t <= p.t && f.t - it.t <= 2 }
        val first = seed.firstOrNull() ?: return
        val r = Live(false, first.t, first.wall, first.coord, false)
        for ((i, x) in seed.withIndex()) {
            if (i > 0) r.d += (seed[i - 1].v + x.v) / 2 * (x.t - seed[i - 1].t)
            r.trace.add(DragPoint(x.t - first.t, r.d, x.v))
            r.maxSpeed = max(r.maxSpeed, x.v)
        }
        r.fixes = seed.size
        r.lastT = p.t
        r.lastActivity = f.t
        live = r
        advance(r, p, f, dt)
    }

    private fun advance(r: Live, p: Fix, f: Fix, dt: Double) {
        val pd = r.d
        r.d += (p.v + f.v) / 2 * dt
        r.lastT = f.t
        r.fixes += 1
        r.maxSpeed = max(r.maxSpeed, f.v)
        r.trace.add(DragPoint(f.t - r.t0, r.d, f.v))
        if (r.confirmed) r.peakG = max(r.peakG, accel / 9.80665)
        if (accel > 0.5) r.lastActivity = f.t
        distance = r.d

        fun at(u0: Double): At {
            val u = min(1.0, max(0.0, u0))
            val v = p.v + (f.v - p.v) * u
            val alt = if (p.alt != null && f.alt != null) p.alt + (f.alt - p.alt) * u else null
            return At(p.t + dt * u, v, pd + (p.v + v) / 2 * dt * u, alt)
        }
        fun speedCrossing(x: Double) = at(if (f.v == p.v) 1.0 else (x - p.v) / (f.v - p.v))

        if (r.standing && !r.confirmed) {
            if (f.v >= CONFIRM_SPEED) {
                confirm(r)
            } else if (f.v < STILL_SPEED * 0.6 || f.t - r.t0 > 4) {
                // Creeping forward, not a launch: still ready if it stopped, else wait for a stop.
                live = null
                distance = 0.0
                if (f.v >= STILL_SPEED * 0.6) setPhase(Phase.moving)
                return
            }
        }
        if (r.standing && r.zero == null && r.d >= ROLLOUT_DISTANCE) {
            val x = at((ROLLOUT_DISTANCE - pd) / max(r.d - pd, 1e-6))
            r.zero = Mark(x.t, ROLLOUT_DISTANCE, x.alt)
        }

        for (m in r.measures) {
            if (r.done.contains(m.name)) continue
            when (m.kind) {
                DragMeasure.Kind.speed -> if (m.from == 0.0) {
                    val z = r.zero
                    if (!r.standing || z == null || !(p.v < m.to && f.v >= m.to)) continue
                    val x = speedCrossing(m.to)
                    add(r, m, x.t - z.t, m.to, x.d - z.d, slope(z.alt, x.alt, x.d - z.d), x.t)
                } else {
                    if (p.v < m.from && f.v >= m.from) {
                        val x = speedCrossing(m.from)
                        r.rolling[m.name] = Mark(x.t, x.d, x.alt)
                        r.lastActivity = f.t
                    } else if (f.v < m.from) {
                        r.rolling.remove(m.name)
                    }
                    val s = r.rolling[m.name] ?: continue
                    if (p.v < m.to && f.v >= m.to) {
                        val x = speedCrossing(m.to)
                        r.rolling.remove(m.name)
                        add(r, m, x.t - s.t, m.to, x.d - s.d, slope(s.alt, x.alt, x.d - s.d), x.t)
                    } else if (f.t - s.t > 30) {
                        r.rolling.remove(m.name)
                    }
                }
                DragMeasure.Kind.distance -> {
                    val z = r.zero
                    if (!r.standing || z == null || !(pd - z.d < m.to && r.d - z.d >= m.to)) continue
                    val x = at((m.to + z.d - pd) / max(r.d - pd, 1e-6))
                    add(r, m, x.t - z.t, x.v, m.to, slope(z.alt, x.alt, m.to), x.t)
                }
                DragMeasure.Kind.braking -> {
                    if (p.v > m.from && f.v <= m.from) {
                        val x = speedCrossing(m.from)
                        r.braking[m.name] = Mark(x.t, x.d, x.alt)
                        r.lastActivity = f.t
                    } else if (f.v > m.from) {
                        r.braking.remove(m.name)
                    }
                    val s = r.braking[m.name] ?: continue
                    if (f.v < STILL_SPEED) {
                        // On to zero at the deceleration between the two fixes.
                        val tStop = f.t + min(dt, f.v * dt / max(p.v - f.v, 0.01))
                        val dStop = r.d + f.v / 2 * (tStop - f.t)
                        r.braking.remove(m.name)
                        if (tStop - s.t < 15) add(r, m, tStop - s.t, 0.0, dStop - s.d, slope(s.alt, f.alt, dStop - s.d), tStop)
                    } else if (f.t - s.t > 15) {
                        // Coasting down, not braking.
                        r.braking.remove(m.name)
                    }
                }
            }
        }

        if (r.confirmed && f.v < STILL_SPEED) finish()
        else if (f.t - r.t0 > 120) finish()
        else if (r.confirmed && r.braking.isEmpty() && f.t - r.lastActivity > 6) finish()
    }

    private fun add(r: Live, m: DragMeasure, time: Double, speed: Double, distance: Double, slope: Double?, end: Double) {
        if (time <= 0) return
        val result = DragResult(m.name, m.kind, time, speed, distance, slope, end - r.t0)
        r.done.add(m.name)
        r.results.add(result)
        r.lastActivity = max(r.lastActivity, end)
        val value = if (m.kind == DragMeasure.Kind.braking) distance else time
        val earlier = bests[m.name]
        val isBest = earlier?.let { value < it } ?: true
        if (isBest) bests[m.name] = value
        if (!r.standing && r.results.size == 1) {
            // A rolling run shows up with its first result.
            shownBefore = run
            inProgress = true
            startWall = r.wall
            setPhase(Phase.running)
        }
        publish(r)
        val e = DragEvent(result = result, measure = m, isBest = isBest, isRecord = isBest && earlier != null)
        lastEvent = e
        onEvent?.invoke(e)
    }

    private fun finish() {
        val r = live ?: return
        live = null
        inProgress = false
        startWall = null
        if (r.counts && r.results.isNotEmpty()) {
            val done = makeRun(r)
            run = done
            onFinish?.invoke(done)
        } else if (r.counts) {
            // Off and stopped again before any measure: the last run goes back on screen.
            run = shownBefore
        }
        setPhase(Phase.moving)
    }

    private fun publish(r: Live) {
        run = makeRun(r)
    }

    private fun makeRun(r: Live): DragRun {
        val span = r.lastT - r.t0
        return DragRun(
            id = r.id, date = r.wall, source = source, vehicle = vehicle, standing = r.standing,
            rollout = r.standing && r.rollout, results = r.results.toList(), trace = r.trace.toList(), maxSpeed = r.maxSpeed,
            peakG = r.peakG, rate = if (span > 0) (r.fixes - 1) / span else 0.0, start = r.start, carID = carID,
        )
    }

    private fun setPhase(p: Phase) {
        if (p == phase) return
        phase = p
        onPhase?.invoke(p)
    }

    /** Over the last half second, or between the last two fixes when they are further apart. */
    private fun acceleration(): Double {
        val last = recent.lastOrNull() ?: return 0.0
        if (recent.size <= 1) return 0.0
        val first = recent.lastOrNull { last.t - it.t >= 0.45 } ?: recent[0]
        return if (last.t > first.t) (last.v - first.v) / (last.t - first.t) else 0.0
    }

    /** Rise over run in %: the altitude of a GPS is good for that only over 50 m or more. */
    private fun slope(a: Double?, b: Double?, d: Double): Double? {
        if (a == null || b == null || d < 50) return null
        return (b - a) / d * 100
    }
}
