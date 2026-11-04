package win.tbsgaming.tracklap.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import win.tbsgaming.tracklap.data.Files
import win.tbsgaming.tracklap.ui.Fmt
import win.tbsgaming.tracklap.ui.L
import java.io.File

/**
 * The files TrackLap sends between phones, the same on the iPhone and on Android. The iPhone writes
 * its dates as seconds since 1 January 2001, the app keeps them since 1970: the dates are moved
 * between the two when a file is read or written.
 */
object AppleDates {
    const val OFFSET = 978_307_200.0

    /** The object with the dates at these paths moved by `delta`; "a.b" goes into objects, "a[]" into each element of an array. */
    fun shift(o: JsonObject, paths: List<String>, delta: Double): JsonObject {
        var out = o
        for (p in paths) out = shiftOne(out, p.split("."), delta)
        return out
    }

    private fun shiftOne(o: JsonObject, path: List<String>, delta: Double): JsonObject {
        val head = path.first()
        val rest = path.drop(1)
        val map = o.toMutableMap()
        if (head.endsWith("[]")) {
            val key = head.removeSuffix("[]")
            val arr = o[key] as? JsonArray ?: return o
            map[key] = JsonArray(arr.map { e -> (e as? JsonObject)?.let { if (rest.isEmpty()) it else shiftOne(it, rest, delta) } ?: e })
        } else if (rest.isEmpty()) {
            val v = (o[head] as? JsonPrimitive)?.doubleOrNull ?: return o
            map[head] = JsonPrimitive(v + delta)
        } else {
            val inner = o[head] as? JsonObject ?: return o
            map[head] = shiftOne(inner, rest, delta)
        }
        return JsonObject(map)
    }
}

class ReadError(message: String) : Exception(message)

/** A lap sent to a friend as a .tracklap file: the lap with its trace, the track it was driven on, and who drove it. */
@Serializable
data class SharedLap(
    val format: Int = VERSION,
    val driver: String,
    val vehicle: String = "",
    /** The SourceKind it was timed with. */
    val source: String,
    val date: Double,
    val track: Track,
    val lap: Lap,
) {
    val id: String get() = lap.id

    /** Written to a file named after the driver, the track and the time, for the share sheet. */
    fun write(dir: File): File {
        val time = Fmt.lap(lap.time).replace(":", ".")
        val name = listOf(driver, track.name, time).joinToString(" - ") { s -> s.filter { it.isLetterOrDigit() || it == ' ' || it == '.' } }
        dir.mkdirs()
        val f = File(dir, "$name.tracklap")
        f.writeText(encode(this))
        return f
    }

    companion object {
        const val VERSION = 1
        private val DATES = listOf("date", "track.created", "lap.startedAt")

        fun encode(s: SharedLap): String {
            val o = Files.json.encodeToJsonElement(serializer(), s).jsonObject
            return AppleDates.shift(o, DATES, -AppleDates.OFFSET).toString()
        }

        fun decode(text: String): SharedLap {
            val o = runCatching { Files.json.parseToJsonElement(text).jsonObject }.getOrNull() ?: throw ReadError(L("Questo file non è un giro di TrackLap."))
            if ((o["format"]?.jsonPrimitive?.intOrNull ?: 1) > VERSION) throw ReadError(L("Questo giro viene da una versione più nuova di TrackLap: aggiorna l'app."))
            return runCatching { Files.json.decodeFromJsonElement(serializer(), AppleDates.shift(o, DATES, AppleDates.OFFSET)) }.getOrNull()
                ?: throw ReadError(L("Questo file non è un giro di TrackLap."))
        }

        /** Kept on the phone as it came, dates since 1970. */
        fun encodeLocal(s: SharedLap): String = Files.json.encodeToString(serializer(), s)
        fun decodeLocal(text: String): SharedLap? = runCatching { Files.json.decodeFromString(serializer(), text) }.getOrNull()
    }
}

/** A setup sent as a file: setups never go online, a file is the only way they leave the phone. */
@Serializable
data class SharedSetup(
    val format: Int = VERSION,
    val car: String,
    val setup: CarSetup,
) {
    fun write(dir: File): File {
        val name = listOf(car, setup.displayName).joinToString(" - ") { s -> s.filter { it.isLetterOrDigit() || it == ' ' } }
        dir.mkdirs()
        val f = File(dir, "$name.tracklapsetup")
        f.writeText(encode(this))
        return f
    }

    companion object {
        const val VERSION = 1
        private val DATES = listOf("setup.created", "setup.updated", "setup.history[].date")

        fun encode(s: SharedSetup): String {
            val o = Files.json.encodeToJsonElement(serializer(), s).jsonObject
            return AppleDates.shift(o, DATES, -AppleDates.OFFSET).toString()
        }

        fun decode(text: String): SharedSetup {
            val o = runCatching { Files.json.parseToJsonElement(text).jsonObject }.getOrNull() ?: throw ReadError(L("Questo file non è un assetto di TrackLap."))
            if ((o["format"]?.jsonPrimitive?.intOrNull ?: 1) > VERSION) throw ReadError(L("Questo assetto viene da una versione più nuova di TrackLap: aggiorna l'app."))
            return runCatching { Files.json.decodeFromJsonElement(serializer(), AppleDates.shift(o, DATES, AppleDates.OFFSET)) }.getOrNull()
                ?: throw ReadError(L("Questo file non è un assetto di TrackLap."))
        }

        /** What kind of TrackLap file a text is: a lap, a setup, or neither. */
        fun kind(text: String): String? {
            val o: JsonElement = runCatching { Files.json.parseToJsonElement(text) }.getOrNull() ?: return null
            val obj = o as? JsonObject ?: return null
            return when {
                obj["setup"] != null && obj["car"] != null -> "setup"
                obj["lap"] != null && obj["track"] != null -> "lap"
                else -> null
            }
        }
    }
}
