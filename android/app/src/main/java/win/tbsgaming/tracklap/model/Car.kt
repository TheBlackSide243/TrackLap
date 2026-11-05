package win.tbsgaming.tracklap.model

import kotlinx.serialization.Serializable
import win.tbsgaming.tracklap.ui.L
import java.util.Locale
import kotlin.math.roundToInt

/**
 * A car in your garage: what it is, its numbers and what was done to it, with one photo. The same
 * shape the server keeps (server/src/index.js, cleanGarage), so the garage goes up as it is.
 */
@Serializable
data class Car(
    val id: String = newID(),
    val name: String = "",
    val year: Int? = null,
    /** Metric horsepower (CV) whatever the units shown, like the server. */
    val power: Int? = null,
    /** Kilograms. */
    val weight: Int? = null,
    val mods: List<String> = emptyList(),
    val notes: String = "",
    /** Its photo: a JPEG in the garage folder, under the same id on the server. A new photo always gets a new id. */
    val photo: String? = null,
    val added: Double = nowSeconds(),
) {
    val displayName: String get() = name.trim().ifEmpty { L("Auto senza nome") }

    val info: CarInfo
        get() = CarInfo(id, displayName, year, power, weight, mods, notes, photo?.let { CarPhoto.Local(it) } ?: CarPhoto.Empty)

    /** What goes to the server: the same fields, the modifications without empty lines. */
    val published: Car
        get() = copy(name = displayName.take(MAX_NAME), mods = mods.map { it.trim() }.filter { it.isNotEmpty() }, notes = notes.trim())

    companion object {
        const val MAX_NAME = 40
        const val MAX_MOD = 80
        const val MAX_MODS = 40
        const val MAX_NOTES = 600
        const val MAX_CARS = 20
    }
}

/** A car as the screens show it, yours or from someone's public garage. */
data class CarInfo(
    val id: String,
    val name: String,
    val year: Int?,
    val power: Int?,
    val weight: Int?,
    val mods: List<String>,
    val notes: String,
    val photo: CarPhoto,
) {
    /** Kilograms (or pounds) for each horsepower: the number drivers compare cars by. */
    val ratio: Double? get() = if (power != null && weight != null && power > 0) weight.toDouble() / power else null

    /** "2019 · 320 CV", for a card. */
    val subtitle: String
        get() = listOfNotNull(year?.toString(), power?.let { CarFmt.power(it) + " " + CarFmt.powerUnit }).joinToString(" · ")
}

sealed interface CarPhoto {
    data object Empty : CarPhoto
    /** A photo id in your garage folder. */
    data class Local(val id: String) : CarPhoto
    data class Remote(val url: String) : CarPhoto
}

/** Someone's garage as the server sends it. */
@Serializable
data class PublicGarage(
    val code: String,
    val name: String,
    val cars: List<Entry>,
    val mine: Boolean? = null,
    val hidden: Boolean? = null,
    val missing: List<String>? = null,
    /** "all", or "friends" for a garage shown to friends only. */
    val audience: String? = null,
) {
    @Serializable
    data class Entry(
        val id: String,
        val name: String,
        val year: Int? = null,
        val power: Int? = null,
        val weight: Int? = null,
        val mods: List<String> = emptyList(),
        val notes: String? = null,
        val photo: String? = null,
    )

    fun info(e: Entry, photoURL: (String) -> String) =
        CarInfo(e.id, e.name, e.year, e.power, e.weight, e.mods, e.notes ?: "", e.photo?.let { CarPhoto.Remote(photoURL(it)) } ?: CarPhoto.Empty)
}

/** Power, weight and their ratio in the units of the settings. */
object CarFmt {
    private val metric get() = Units.current == Units.metric

    fun power(cv: Int): String = if (metric) "$cv" else "${(cv * 0.98632).roundToInt()}"
    val powerUnit: String get() = if (metric) L("CV") else "hp"
    fun weight(kg: Int): String = if (metric) "$kg" else "${(kg * 2.20462).roundToInt()}"
    val weightUnit: String get() = if (metric) "kg" else "lb"
    /** kg/CV, or lb/hp. */
    fun ratio(kgPerCV: Double): String = String.format(Locale.US, "%.2f", if (metric) kgPerCV else kgPerCV * 2.20462 / 0.98632)
    val ratioUnit: String get() = if (metric) L("kg/CV") else "lb/hp"
    /** What was typed in the editor, in the unit shown, back to CV and kg. */
    fun cv(shown: Int): Int = if (metric) shown else (shown / 0.98632).roundToInt()
    fun kg(shown: Int): Int = if (metric) shown else (shown / 2.20462).roundToInt()
}
