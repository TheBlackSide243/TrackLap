package win.tbsgaming.tracklap.model

import kotlinx.serialization.Serializable

/** Speed and distance units: km/h and metres, or mph and miles. The default follows the region. */
enum class Units {
    metric, imperial;

    val title: String get() = if (this == metric) "km/h · km" else "mph · mi"

    companion object {
        /** Set at start from the settings (AppModel). */
        var current: Units = metric
    }
}

/**
 * What a drag run measures: the time from one speed to another (from a standstill, or rolling),
 * the time over a distance from a standstill with the speed at its end, or the time and the
 * distance to stop from a speed.
 */
data class DragMeasure(
    val kind: Kind,
    /** m/s: where a speed or a braking measure begins (0 = from a standstill). */
    val from: Double,
    /** m/s where a speed measure ends, metres for a distance, 0 for braking. */
    val to: Double,
    /** "0–100 km/h", "1/4 mi": what it is called everywhere, and the key of its records. */
    val name: String,
    /** The same in plain ASCII, for the ESP32's screen. */
    val short: String,
    /** The few that are read out and shown on the ESP32: 0–100 (0–60 mph), the quarter mile, braking. */
    val headline: Boolean,
) {
    @Serializable
    enum class Kind { speed, distance, braking }

    /** Timed from the launch, so only in a run from a standstill. */
    val standing: Boolean get() = kind == Kind.distance || (kind == Kind.speed && from == 0.0)

    companion object {
        private const val KMH = 1 / 3.6
        private const val MPH = 0.44704

        /** The measures of a run in the units of the settings. */
        fun all(units: Units = Units.current): List<DragMeasure> {
            val metric = units == Units.metric
            val f = if (metric) KMH else MPH
            val unit = if (metric) "km/h" else "mph"
            val first = if (metric) 100.0 else 60.0
            fun speed(a: Double, b: Double) = DragMeasure(
                Kind.speed, a * f, b * f, "${a.toInt()}–${b.toInt()} $unit", "${a.toInt()}-${b.toInt()}", a == 0.0 && b == first,
            )
            fun distance(m: Double, name: String, short: String, headline: Boolean = false) =
                DragMeasure(Kind.distance, 0.0, m, name, short, headline)
            val speeds = if (metric) listOf(0.0 to 50.0, 0.0 to 100.0, 0.0 to 150.0, 0.0 to 200.0, 80.0 to 120.0, 100.0 to 200.0)
            else listOf(0.0 to 30.0, 0.0 to 60.0, 0.0 to 100.0, 0.0 to 130.0, 50.0 to 70.0, 60.0 to 130.0)
            return speeds.map { speed(it.first, it.second) } + listOf(
                distance(18.288, "60 ft", "60FT"),
                distance(201.168, "1/8 mi", "1/8MI"),
                distance(402.336, "1/4 mi", "1/4MI", headline = true),
                if (metric) distance(1000.0, "1000 m", "1000M") else distance(804.672, "1/2 mi", "1/2MI"),
                DragMeasure(Kind.braking, first * f, 0.0, "${first.toInt()}–0 $unit", "${first.toInt()}-0", true),
            )
        }
    }
}

/** One measure done in a run. */
@Serializable
data class DragResult(
    val name: String,
    val kind: DragMeasure.Kind,
    /** Seconds. */
    val time: Double,
    /** m/s at the end: the trap speed of a distance. */
    val speed: Double,
    /** Metres covered: the stopping distance of a braking measure. */
    val distance: Double,
    /** Rise over the distance in %, when the GPS gives the altitude and the distance is long enough. */
    val slope: Double? = null,
    /** Seconds into the run when it ended, for the chart. */
    val at: Double,
)

@Serializable
data class DragPoint(val t: Double, val d: Double, val v: Double)

/** A run: from a standstill to a stop, or a rolling one (an overtake, a stop) while already moving. */
@Serializable
data class DragRun(
    val id: String = newID(),
    val date: Double,
    val source: String,
    val vehicle: String,
    val standing: Boolean,
    val rollout: Boolean,
    val results: List<DragResult>,
    val trace: List<DragPoint>,
    val maxSpeed: Double,
    /** The strongest acceleration, in g. */
    val peakG: Double,
    /** Fixes per second. */
    val rate: Double,
    val start: Coord? = null,
    val carID: String? = null,
) {
    val summary: DragSummary get() = DragSummary(id, date, source, vehicle, standing, rollout, results, maxSpeed, peakG, rate, carID)
    fun result(name: String) = results.firstOrNull { it.name == name }
}

/** What the list and the records need, kept apart so the traces load only when a run opens. */
@Serializable
data class DragSummary(
    val id: String,
    val date: Double,
    val source: String,
    val vehicle: String,
    val standing: Boolean,
    val rollout: Boolean,
    val results: List<DragResult>,
    val maxSpeed: Double,
    val peakG: Double,
    val rate: Double,
    val carID: String? = null,
) {
    fun result(name: String) = results.firstOrNull { it.name == name }

    /** The road's slope over the longest measure that has one. */
    val slope: Double? get() = results.filter { it.slope != null }.maxByOrNull { it.distance }?.slope

    /** The measure the list shows first: 0–100 or 0–60, else the quarter mile, else the first one done. */
    val headline: DragResult?
        get() {
            val names = DragMeasure.all().filter { it.headline }.map { it.name }
            return names.firstNotNullOfOrNull { n -> results.firstOrNull { it.name == n } } ?: results.firstOrNull()
        }
}
