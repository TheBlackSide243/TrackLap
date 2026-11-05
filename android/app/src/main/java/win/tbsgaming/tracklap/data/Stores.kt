package win.tbsgaming.tracklap.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import win.tbsgaming.tracklap.model.DemoCircuit
import win.tbsgaming.tracklap.model.DragMeasure
import win.tbsgaming.tracklap.model.DragResult
import win.tbsgaming.tracklap.model.DragRun
import win.tbsgaming.tracklap.model.DragSummary
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.Session
import win.tbsgaming.tracklap.model.SessionSummary
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.timing.GForce
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

object Files {
    lateinit var docs: File
    val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun init(context: Context) {
        docs = context.filesDir
    }

    fun <T> write(value: T, serializer: KSerializer<T>, file: File) {
        try {
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(json.encodeToString(serializer, value))
            if (!tmp.renameTo(file)) {
                file.delete()
                tmp.renameTo(file)
            }
        } catch (e: Exception) {
            android.util.Log.e("TrackLap", "saving ${file.name} failed", e)
        }
    }

    fun <T> read(serializer: KSerializer<T>, file: File): T? =
        runCatching { if (file.exists()) json.decodeFromString(serializer, file.readText()) else null }.getOrNull()
}

class TrackStore {
    var tracks by mutableStateOf<List<Track>>(emptyList()); private set
    private val file get() = File(Files.docs, "tracks.json")
    private val serializer = ListSerializer(Track.serializer())

    init {
        tracks = Files.read(serializer, file) ?: emptyList()
        if (tracks.isEmpty()) {
            tracks = listOf(DemoCircuit.track())
            save()
        }
    }

    fun track(id: String?): Track? = id?.let { i -> tracks.firstOrNull { it.id == i } }

    fun upsert(t: Track) {
        val i = tracks.indexOfFirst { it.id == t.id }
        tracks = if (i >= 0) tracks.toMutableList().also { it[i] = t } else listOf(t) + tracks
        save()
    }

    fun delete(id: String) {
        tracks = tracks.filter { it.id != id }
        save()
    }

    private fun save() = Files.write(tracks, serializer, file)
}

/** A lap together with the session it was driven in. */
data class SessionLap(val lap: Lap, val session: SessionSummary)

/** One JSON file per session, plus a small index for the list. */
class SessionStore {
    var summaries by mutableStateOf<List<SessionSummary>>(emptyList()); private set
    private val dir get() = File(Files.docs, "sessions").also { it.mkdirs() }
    private val indexFile get() = File(Files.docs, "sessions.json")
    private val indexSerializer = ListSerializer(SessionSummary.serializer())

    init {
        summaries = Files.read(indexSerializer, indexFile) ?: emptyList()
    }

    fun save(s: Session) {
        Files.write(s, Session.serializer(), file(s.id))
        val list = summaries.toMutableList()
        val i = list.indexOfFirst { it.id == s.id }
        if (i >= 0) list[i] = s.summary else list.add(s.summary)
        summaries = list.sortedByDescending { it.date }
        Files.write(summaries, indexSerializer, indexFile)
    }

    fun load(id: String): Session? = Files.read(Session.serializer(), file(id))

    fun delete(id: String) {
        file(id).delete()
        summaries = summaries.filter { it.id != id }
        Files.write(summaries, indexSerializer, indexFile)
    }

    /**
     * The best lap of the fastest sessions on a track, fastest first. With a layout, only its
     * sessions; those from before layouts existed count for the main one.
     */
    fun bestLaps(track: String?, layout: String? = null, main: Boolean = true, excluding: String? = null, limit: Int = 12): List<SessionLap> =
        sessions(track, excluding)
            .filter { s -> layout == null || s.layout == layout || (main && s.layout == null) }
            .take(limit)
            .mapNotNull { s -> load(s.id)?.best?.let { SessionLap(it, s) } }

    fun record(track: String?, layout: String? = null, main: Boolean = true, excluding: String? = null): SessionLap? =
        bestLaps(track, layout, main, excluding, 1).firstOrNull()

    /** The record of the layout in use on a track. */
    fun record(track: Track?): SessionLap? {
        track ?: return null
        return record(track.id, track.layout?.key, track.layout?.key == track.layouts?.firstOrNull()?.key)
    }

    private fun sessions(track: String?, excluding: String?): List<SessionSummary> {
        track ?: return emptyList()
        return summaries.filter { it.trackID == track && it.id != excluding && it.best != null }.sortedBy { it.best ?: 0.0 }
    }

    private fun file(id: String) = File(dir, "$id.json")
}

/** The best result of a measure and the run it was done in. */
data class DragRecord(val result: DragResult, val run: DragSummary) {
    val value: Double get() = if (result.kind == DragMeasure.Kind.braking) result.distance else result.time
}

/** The drag runs: one JSON file per run, plus an index with the results for the list and the records. */
class DragStore {
    var summaries by mutableStateOf<List<DragSummary>>(emptyList()); private set
    private val dir get() = File(Files.docs, "drags").also { it.mkdirs() }
    private val indexFile get() = File(Files.docs, "drags.json")
    private val indexSerializer = ListSerializer(DragSummary.serializer())

    init {
        summaries = Files.read(indexSerializer, indexFile) ?: emptyList()
    }

    fun save(r: DragRun) {
        Files.write(r, DragRun.serializer(), file(r.id))
        val list = summaries.toMutableList()
        val i = list.indexOfFirst { it.id == r.id }
        if (i >= 0) list[i] = r.summary else list.add(r.summary)
        summaries = list.sortedByDescending { it.date }
        Files.write(summaries, indexSerializer, indexFile)
    }

    fun load(id: String): DragRun? = Files.read(DragRun.serializer(), file(id))

    fun delete(id: String) {
        file(id).delete()
        summaries = summaries.filter { it.id != id }
        Files.write(summaries, indexSerializer, indexFile)
    }

    /** The best of every measure: the shortest time, or the shortest stop for braking. */
    fun records(car: String? = null): Map<String, DragRecord> {
        val out = HashMap<String, DragRecord>()
        for (s in summaries) {
            if (car != null && s.carID != car) continue
            for (r in s.results) {
                val v = if (r.kind == DragMeasure.Kind.braking) r.distance else r.time
                val old = out[r.name]
                if (old != null && old.value <= v) continue
                out[r.name] = DragRecord(r, s)
            }
        }
        return out
    }

    fun bests(car: String? = null): MutableMap<String, Double> = records(car).mapValues { it.value.value }.toMutableMap()

    private fun file(id: String) = File(dir, "$id.json")
}

object Export {
    fun file(context: Context, s: Session, ext: String): File {
        val df = SimpleDateFormat("yyyy-MM-dd_HH-mm", Locale.US)
        val safe = s.trackName.filter { it.isLetterOrDigit() }
        val dir = File(context.cacheDir, "exports").also { it.mkdirs() }
        return File(dir, "TrackLap_${safe}_${df.format(Date((s.date * 1000).toLong()))}.$ext")
    }

    /** Every point of every lap with speed and g, for spreadsheets and analysis tools. */
    fun csv(context: Context, s: Session): File {
        val x = StringBuilder("lap,lap_time_s,elapsed_s,distance_m,latitude,longitude,speed_kmh,lateral_g,longitudinal_g\n")
        for (lap in s.laps) {
            val g = GForce.along(lap.trace)
            for ((i, p) in lap.trace.withIndex()) {
                x.append(lap.number).append(',')
                x.append(String.format(Locale.US, "%.3f,%.3f,%.1f,%.7f,%.7f,%.2f,%.2f,%.2f\n",
                    lap.time, p.t, p.d, p.lat, p.lon, p.v * 3.6, g[i].lateral, g[i].longitudinal))
            }
        }
        return file(context, s, "csv").also { it.writeText(x.toString()) }
    }

    fun gpx(context: Context, s: Session): File {
        val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val x = StringBuilder()
        x.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        x.append("<gpx version=\"1.1\" creator=\"TrackLap\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n")
        x.append("<trk><name>").append(escape(s.trackName)).append("</name>\n")
        for (lap in s.laps) {
            x.append("<trkseg>\n")
            for (p in lap.trace) {
                val time = iso.format(Date(((lap.startedAt + p.t) * 1000).toLong()))
                x.append("<trkpt lat=\"${p.lat}\" lon=\"${p.lon}\"><time>$time</time></trkpt>\n")
            }
            x.append("</trkseg>\n")
        }
        x.append("</trk>\n</gpx>\n")
        return file(context, s, "gpx").also { it.writeText(x.toString()) }
    }

    private fun escape(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
}
