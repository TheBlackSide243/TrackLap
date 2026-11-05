package win.tbsgaming.tracklap.model

import kotlinx.serialization.Serializable
import win.tbsgaming.tracklap.gps.DemoDriver
import win.tbsgaming.tracklap.ui.Fmt
import win.tbsgaming.tracklap.ui.L
import java.util.UUID

fun newID(): String = UUID.randomUUID().toString().uppercase()
fun nowSeconds(): Double = System.currentTimeMillis() / 1000.0

/** A virtual line across the track: the start/finish or an intermediate. */
@Serializable
data class GateLine(val a: Coord, val b: Coord) {
    val mid: Coord get() = Coord((a.lat + b.lat) / 2, (a.lon + b.lon) / 2)
    val width: Double get() = Geo.distance(a, b)

    fun resized(w: Double): GateLine {
        val f = LocalFrame(mid)
        val dir = (f.xy(b) - f.xy(a)).normalized
        return GateLine(f.coord(dir * (-w / 2)), f.coord(dir * (w / 2)))
    }
}

/** A layout of a track with its lines placed: from an OpenStreetMap circuit, or worked out from the raceways. */
@Serializable
data class TrackLayout(
    val name: String,
    val length: Double,
    val start: GateLine,
    val sectors: List<GateLine>,
    val source: Source,
    /** The lap as a line every 15 m, to tell which layout a lap was driven on. */
    val path: List<Coord>? = null,
) {
    @Serializable
    enum class Source { mapped, pits, named, straight }

    /** What sessions and records are filed under: two layouts never share it. */
    val key: String get() = name + "|" + Math.round(length).toInt()

    fun title(index: Int): String {
        val n = name.ifEmpty { if (index == 0) L("Giro completo") else L("Variante %lld", index) }
        return n + " · " + Fmt.distance(length)
    }
}

@Serializable
data class Track(
    val id: String = newID(),
    val name: String,
    val place: String = "",
    val center: Coord,
    /** The raceway ways downloaded from OpenStreetMap, each one a polyline. */
    val outline: List<List<Coord>> = emptyList(),
    val start: GateLine? = null,
    /** Intermediate lines: n intermediates make n + 1 sectors. */
    val sectors: List<GateLine> = emptyList(),
    val isDemo: Boolean = false,
    val created: Double = nowSeconds(),
    val layouts: List<TrackLayout>? = null,
    /** How the lines were placed when they were put there automatically; null once moved by hand. */
    val autoLines: TrackLayout.Source? = null,
    /** The key of the layout the lines come from: it changes by itself when you drive another. */
    val activeLayout: String? = null,
) {
    val isReady: Boolean get() = start != null
    val sectorCount: Int get() = if (sectors.isEmpty()) 0 else sectors.size + 1
    val length: Double? get() = outline.maxOfOrNull { Geo.length(it) }

    val allPoints: List<Coord>
        get() {
            val pts = outline.flatten().toMutableList()
            start?.let { pts += listOf(it.a, it.b) }
            for (g in sectors) pts += listOf(g.a, g.b)
            return pts
        }

    /** The layout the lines come from now, when the track has several. */
    val layout: TrackLayout? get() = layouts?.firstOrNull { it.key == activeLayout }

    /** The lines of the first layout found, and the others kept for the editor to switch to. */
    fun applyAuto(found: List<TrackLayout>): Track {
        val first = found.firstOrNull() ?: return this
        return copy(layouts = found).use(first)
    }

    /** The lines of this layout from now on. */
    fun use(l: TrackLayout): Track = copy(start = l.start, sectors = l.sectors, autoLines = l.source, activeLayout = l.key)

    /** Lines moved by hand stay with their layout, for when it comes back. */
    fun keepLinesInLayout(): Track {
        val list = layouts ?: return this
        val i = list.indexOfFirst { it.key == activeLayout }
        val s = start ?: return this
        if (i < 0) return this
        val updated = list.toMutableList()
        updated[i] = updated[i].copy(start = s, sectors = sectors)
        return copy(layouts = updated)
    }

    /** The layout's name in the title, when the track has several. */
    val titleWithLayout: String
        get() {
            val list = layouts ?: return name
            if (list.size < 2) return name
            val i = list.indexOfFirst { it.key == activeLayout }
            if (i < 0) return name
            val l = list[i]
            return name + " · " + l.name.ifEmpty { if (i == 0) L("Giro completo") else L("Variante %lld", i) }
        }
}

/** The built-in demo circuit, so the whole app can be tried without hardware. */
object DemoCircuit {
    val center = Coord(45.1585, 8.8350)

    fun track(): Track {
        val f = LocalFrame(center)
        val pts = DemoDriver.syntheticLoop(null)
        val n = pts.size
        val coords = pts.map { f.coord(it) }
        fun gate(i: Int): GateLine {
            val dir = (pts[(i + 1) % n] - pts[(i - 1 + n) % n]).normalized.perpendicular * 12.0
            return GateLine(f.coord(pts[i] - dir), f.coord(pts[i] + dir))
        }
        return Track(
            name = L("Circuito Demo"), place = L("Pista simulata"), center = center,
            outline = listOf(coords + coords[0]),
            start = gate(0), sectors = listOf(gate(n / 3), gate(2 * n / 3)), isDemo = true,
        )
    }
}
