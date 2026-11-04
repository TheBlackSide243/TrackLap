package win.tbsgaming.tracklap.ui

import android.content.Context
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import win.tbsgaming.tracklap.model.Units
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * Translated text. The Italian text is the key, as on the iPhone: the table is the iPhone's
 * (tools/l10n.mjs), written to assets/l10n.json with "iPhone" turned into the phone for Android.
 * %@ stands for a text and %lld for a number, filled in order.
 */
object Strings {
    private var table: Map<String, String> = emptyMap()
    var language: String = "en"; private set

    fun init(context: Context) {
        val lang = Locale.getDefault().language
        language = if (lang in listOf("it", "en", "es", "fr", "de", "pt")) lang else "en"
        table = runCatching {
            val text = context.assets.open("l10n.json").use { it.readBytes().toString(Charsets.UTF_8) }
            val all = Json.parseToJsonElement(text).jsonObject
            (all[language] as? JsonObject)?.mapValues { it.value.jsonPrimitive.content } ?: emptyMap()
        }.getOrDefault(emptyMap())
    }

    fun get(key: String): String = table[key] ?: key
}

fun L(key: String, vararg args: Any): String {
    val text = Strings.get(key)
    if (args.isEmpty()) return text
    val out = StringBuilder()
    var i = 0
    var k = 0
    while (i < text.length) {
        when {
            text.startsWith("%@", i) -> {
                out.append(args.getOrNull(k++)?.toString() ?: "")
                i += 2
            }
            text.startsWith("%lld", i) -> {
                out.append(args.getOrNull(k++)?.toString() ?: "")
                i += 4
            }
            else -> {
                out.append(text[i])
                i += 1
            }
        }
    }
    return out.toString()
}

object Fmt {
    fun lap(t: Double?): String {
        if (t == null || !t.isFinite() || t < 0) return "–:––.––"
        val cs = (t * 100).roundToLong()
        return String.format(Locale.US, "%d:%02d.%02d", cs / 6000, (cs / 100) % 60, cs % 100)
    }

    /** Axis labels: tenths are enough. */
    fun lapShort(t: Double): String {
        val ds = (t * 10).roundToLong()
        return String.format(Locale.US, "%d:%02d.%d", ds / 600, (ds / 10) % 60, ds % 10)
    }

    fun sector(t: Double): String = if (t < 60) String.format(Locale.US, "%.2f", t) else lap(t)

    fun delta(d: Double?): String {
        if (d == null || !d.isFinite()) return "—"
        return (if (d < 0) "−" else "+") + String.format(Locale.US, "%.2f", abs(d))
    }

    /** Metres per second to the unit of the settings. */
    val speedFactor: Double get() = if (Units.current == Units.metric) 3.6 else 2.236936
    val speedUnit: String get() = if (Units.current == Units.metric) "km/h" else "mph"

    fun speed(v: Double): String = "${(v * speedFactor).roundToInt()}"

    /** A drag time: hundredths of a second, no minutes. */
    fun dragTime(t: Double?): String {
        if (t == null || !t.isFinite() || t < 0) return "—"
        return String.format(Locale.US, "%.2f", t)
    }

    /** A stopping distance: to the tenth of a metre, or in feet. */
    fun shortDistance(m: Double): String =
        if (Units.current == Units.imperial) "${(m * 3.28084).roundToInt()}" else String.format(Locale.US, "%.1f", m)

    val shortDistanceUnit: String get() = if (Units.current == Units.imperial) "ft" else "m"

    fun slope(s: Double): String = String.format(Locale.US, "%+.1f%%", s)

    fun hz(r: Double): String = if (r >= 2) "${r.roundToInt()} Hz" else String.format(Locale.US, "%.1f Hz", r)

    fun distance(m: Double?): String {
        if (m == null) return "—"
        if (Units.current == Units.imperial) {
            return if (m >= 161) String.format(Locale.US, "%.2f mi", m / 1609.344) else "${(m * 3.28084).toInt()} ft"
        }
        return if (m >= 1000) String.format(Locale.US, "%.2f km", m / 1000) else "${m.toInt()} m"
    }

    private fun pattern(skeleton: String): String =
        android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), skeleton)

    fun dayShort(seconds: Double): String = SimpleDateFormat(pattern("dMMM"), Locale.getDefault()).format(Date((seconds * 1000).toLong()))
    fun day(seconds: Double): String = SimpleDateFormat(pattern("dMMMyyyyHHmm"), Locale.getDefault()).format(Date((seconds * 1000).toLong()))
}
