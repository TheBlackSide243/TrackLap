package win.tbsgaming.tracklap.timing

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.GateLine
import win.tbsgaming.tracklap.model.Geo
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.LocalFrame
import win.tbsgaming.tracklap.model.TracePoint
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.model.Vec
import win.tbsgaming.tracklap.model.newID
import win.tbsgaming.tracklap.model.timeAtDistance

/** One GPS fix, whatever its source (ESP32 over BLE, the phone, the demo). */
data class Sample(
    /** Monotonic GPS time in seconds. */
    val t: Double,
    val coord: Coord,
    /** m/s */
    val speed: Double,
    /** Degrees clockwise from north. */
    val heading: Double,
    /** When the fix reached the app, in seconds since 1970: lets the timer tick smoothly between fixes. */
    val wall: Double = System.currentTimeMillis() / 1000.0,
    /** UTC of the fix in seconds since 1970, when the source gives it. */
    val utc: Double? = null,
    /** Metres above sea level, when the source gives it: the slope of a drag run. */
    val alt: Double? = null,
    /** Measured by the board's accelerometer, when it has one. */
    val g: GPoint? = null,
)

enum class SectorState { best, faster, slower }

data class LiveSector(
    val id: Int,
    val time: Double? = null,
    val state: SectorState? = null,
    /** The same sector on the previous lap, shown dimmed until this lap gets there. */
    val previous: Double? = null,
    val previousState: SectorState? = null,
)

data class LapEvent(
    val id: String = newID(),
    val number: Int,
    val time: Double,
    val isBest: Boolean,
    /** Faster than every lap driven on this track in earlier sessions. */
    val isRecord: Boolean = false,
    /** Against the best before this lap: negative is faster. */
    val gap: Double?,
    /** The friend whose lap you are chasing, and this lap against theirs. */
    val rival: String? = null,
    val rivalGap: Double? = null,
)

/**
 * Lap timing from a stream of fixes: the crossing of each line is interpolated between two fixes,
 * so at 10 Hz the times come out to a few hundredths. The delta compares where you are now with
 * where you were on the best lap at the same distance.
 */
class LapEngine {
    var track by mutableStateOf<Track?>(null); private set
    var laps by mutableStateOf<List<Lap>>(emptyList()); private set
    /** 0 while on the out lap, before the first crossing of the start line. */
    var lapNumber by mutableStateOf(0); private set
    var lapStartWall by mutableStateOf<Double?>(null); private set
    var delta by mutableStateOf<Double?>(null); private set
    var predicted by mutableStateOf<Double?>(null); private set
    var sectors by mutableStateOf<List<LiveSector>>(emptyList()); private set
    var lastEvent by mutableStateOf<LapEvent?>(null); private set
    var speed by mutableStateOf(0.0); private set
    var position by mutableStateOf<Coord?>(null); private set
    var heading by mutableStateOf(0.0); private set
    var lapDistance by mutableStateOf(0.0); private set

    /** The fastest lap on this track from earlier sessions, if any. */
    @set:JvmName("assignRecord") var record by mutableStateOf<Lap?>(null); private set
    /** Compare with the track record instead of the best lap of this session. */
    var compareWithRecord by mutableStateOf(false)
    /** A friend's lap to chase: while set, the delta is against it, whatever else is faster. */
    var ghost by mutableStateOf<Lap?>(null); private set
    var ghostName by mutableStateOf<String?>(null); private set

    var minLapTime = 20.0
    var onLap: ((Lap) -> Unit)? = null

    val bestLap: Lap? get() = laps.minByOrNull { it.time }
    /** The lap the delta is measured against. */
    val referenceLap: Lap?
        get() {
            ghost?.let { return it }
            val rec = record
            if (!compareWithRecord || rec == null) return bestLap
            val best = bestLap
            return if (best != null && best.time < rec.time) best else rec
        }
    val comparesWithRecord: Boolean get() = ghost == null && compareWithRecord && record != null
    val lastLap: Lap? get() = laps.lastOrNull()
    val isTiming: Boolean get() = lapStartWall != null

    private class Pt(val s: Sample, val xy: Vec)

    private var frame: LocalFrame? = null
    private var startGate: Pair<Vec, Vec>? = null
    private var splitGates: List<Pair<Vec, Vec>> = emptyList()
    private var prev: Pt? = null
    private var lapStartT: Double? = null
    private var trace = ArrayList<TracePoint>()
    private val splits = HashMap<Int, Double>()
    private var maxSpeed = 0.0

    fun load(track: Track?) {
        this.track = track
        frame = null
        startGate = null
        splitGates = emptyList()
        val start = track?.start
        if (track != null && start != null) {
            val f = LocalFrame(start.mid)
            frame = f
            startGate = f.xy(start.a) to f.xy(start.b)
            splitGates = track.sectors.map { f.xy(it.a) to f.xy(it.b) }
        }
        record = null
        ghost = null
        ghostName = null
        reset()
    }

    /**
     * Another layout of the same track, found from the lap just driven: its lines from now on, its
     * record to beat, and the laps of this session on it. When the start line moves too, the timer
     * waits for the new line before the next lap.
     */
    fun switchLayout(start: GateLine, sectors: List<GateLine>, record: Lap?, keep: List<Lap>) {
        val t = track ?: return
        val moved = t.start?.let { Geo.distance(it.mid, start.mid) > 15 } ?: true
        track = t.copy(start = start, sectors = sectors)
        val f = LocalFrame(start.mid)
        frame = f
        startGate = f.xy(start.a) to f.xy(start.b)
        splitGates = sectors.map { f.xy(it.a) to f.xy(it.b) }
        prev?.let { prev = Pt(it.s, f.xy(it.s.coord)) }
        this.record = record
        laps = keep
        splits.clear()
        if (moved) {
            lapStartT = null
            lapStartWall = null
            trace = ArrayList()
            lapDistance = 0.0
            delta = null
            predicted = null
        }
        this.sectors = makeSectors(emptyList())
    }

    fun setRecord(lap: Lap?) {
        record = lap
    }

    /** The friend's lap to chase on this track, null for none; like the record, until another track. */
    fun setGhost(lap: Lap?, name: String?) {
        ghost = lap
        ghostName = if (lap == null) null else name
    }

    fun reset() {
        laps = emptyList()
        lapNumber = 0
        lapStartWall = null
        delta = null
        predicted = null
        lastEvent = null
        prev = null
        lapStartT = null
        trace = ArrayList()
        splits.clear()
        maxSpeed = 0.0
        lapDistance = 0.0
        sectors = makeSectors(emptyList())
    }

    /** Position only, while no session is running. */
    fun observe(s: Sample) {
        speed = s.speed
        position = s.coord
        heading = s.heading
    }

    fun ingest(s: Sample) {
        observe(s)
        val frame = frame ?: return
        val gate = startGate ?: return
        val xy = frame.xy(s.coord)
        val p = prev
        prev = Pt(s, xy)
        if (p == null) return
        val dt = s.t - p.s.t
        // A long gap (signal lost) is not interpolated across.
        if (dt <= 0 || dt >= 5) return
        val step = (xy - p.xy).length

        val u = Geo.intersect(p.xy, xy, gate.first, gate.second)
        if (u != null && canCross(lapDistance + step * u, lapStartT?.let { p.s.t + u * dt - it }, s.speed)) {
            val tc = p.s.t + u * dt
            val crossing = frame.coord(p.xy + (xy - p.xy) * u)
            if (lapStartT != null) {
                checkSplits(p, Pt(s, xy), u, dt, step)
                lapDistance += step * u
                appendPoint(tc, crossing, s.speed, s.g)
                finishLap(tc)
            }
            beginLap(tc, s.wall + (tc - s.t), crossing, s.speed, s.g)
            lapDistance = step * (1 - u)
            appendPoint(s.t, s.coord, s.speed, s.g)
        } else if (lapStartT != null) {
            checkSplits(p, Pt(s, xy), 1.0, dt, step)
            lapDistance += step
            appendPoint(s.t, s.coord, s.speed, s.g)
        }
        updateDelta(s.t)
    }

    // Laps

    private fun canCross(distance: Double, elapsed: Double?, speed: Double): Boolean {
        // The first crossing starts lap 1; GPS jitter while parked on the line must not.
        if (elapsed == null) return speed > 2
        return elapsed >= minLapTime && distance >= 200
    }

    private fun beginLap(t: Double, wall: Double, coord: Coord, v: Double, g: GPoint?) {
        lapNumber += 1
        lapStartT = t
        lapStartWall = wall
        lapDistance = 0.0
        trace = ArrayList()
        splits.clear()
        maxSpeed = 0.0
        sectors = makeSectors(sectors)
        appendPoint(t, coord, v, g)
    }

    private fun finishLap(tc: Double) {
        val t0 = lapStartT ?: return
        val wall = lapStartWall ?: return
        val time = tc - t0
        val times = ArrayList<Double>()
        val ordered = splits.values.sorted()
        if (splitGates.isNotEmpty() && ordered.size == splitGates.size) {
            var last = 0.0
            for (e in ordered) {
                times.add(e - last)
                last = e
            }
            times.add(time - last)
            setSector(times.size - 1, time - last)
        }
        val previousBest = bestLap?.time
        val lap = Lap(number = lapNumber, startedAt = wall, time = time, sectors = times, distance = lapDistance,
            maxSpeed = maxSpeed, trace = trace.toList())
        val isBest = previousBest?.let { time < it } ?: true
        val isRecord = record?.let { time < minOf(it.time, previousBest ?: Double.POSITIVE_INFINITY) } ?: false
        laps = laps + lap
        lastEvent = LapEvent(number = lap.number, time = time, isBest = isBest, isRecord = isRecord, gap = previousBest?.let { time - it },
            rival = ghostName, rivalGap = ghost?.let { time - it.time })
        onLap?.invoke(lap)
    }

    private fun appendPoint(t: Double, coord: Coord, v: Double, g: GPoint?) {
        val t0 = lapStartT ?: return
        maxSpeed = maxOf(maxSpeed, v)
        trace.add(TracePoint(t - t0, lapDistance, coord.lat, coord.lon, v, g?.lateral, g?.longitudinal))
    }

    // Sectors

    private fun checkSplits(p: Pt, q: Pt, limit: Double, dt: Double, step: Double) {
        val t0 = lapStartT ?: return
        for ((i, g) in splitGates.withIndex()) {
            if (splits.containsKey(i)) continue
            val u = Geo.intersect(p.xy, q.xy, g.first, g.second) ?: continue
            if (u > limit) continue
            val elapsed = p.s.t + u * dt - t0
            if (elapsed <= 3 || lapDistance + step * u <= 30) continue
            val before = splits.values.filter { it < elapsed }.maxOrNull() ?: 0.0
            splits[i] = elapsed
            // Sectors are numbered in the order they are crossed, whatever order the lines were drawn in.
            setSector(splits.size - 1, elapsed - before)
        }
    }

    private fun setSector(k: Int, time: Double) {
        if (k >= sectors.size) return
        val list = sectors.toMutableList()
        list[k] = list[k].copy(time = time, state = state(k, time))
        sectors = list
    }

    private fun state(k: Int, time: Double): SectorState {
        val previous = laps.mapNotNull { if (it.sectors.size > k) it.sectors[k] else null }
        val best = previous.minOrNull() ?: return SectorState.best
        if (time <= best) return SectorState.best
        val last = laps.lastOrNull()
        if (last != null && last.sectors.size > k && time < last.sectors[k]) return SectorState.faster
        return SectorState.slower
    }

    private fun makeSectors(carry: List<LiveSector>): List<LiveSector> {
        val n = if (splitGates.isEmpty()) 0 else splitGates.size + 1
        return (0 until n).map { i ->
            val old = carry.getOrNull(i)
            LiveSector(i, null, null, old?.time, old?.state)
        }
    }

    // Delta

    private fun updateDelta(now: Double) {
        val t0 = lapStartT
        val ref = referenceLap
        if (t0 == null || ref == null || ref.trace.size <= 1) {
            delta = null
            predicted = null
            return
        }
        val d = (now - t0) - ref.trace.timeAtDistance(lapDistance)
        delta = d
        predicted = ref.time + d
    }
}
