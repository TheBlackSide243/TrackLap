package win.tbsgaming.tracklap.model

import kotlinx.serialization.Serializable
import win.tbsgaming.tracklap.ui.L
import java.text.NumberFormat
import java.util.Locale

/** The conditions a setup is for. */
@Serializable
enum class SetupWeather {
    dry, mixed, wet;

    val title: String
        get() = when (this) {
            dry -> L("Asciutto")
            mixed -> L("Misto")
            wet -> L("Bagnato")
        }
}

/**
 * The numbers of a setup, every one optional: what is set on the car, nothing more. Pressures are
 * kept in bar, lengths in millimetres, springs in N/mm.
 */
@Serializable
data class SetupValues(
    val tyres: String = "",
    val pressureFrontCold: Double? = null,
    val pressureRearCold: Double? = null,
    val pressureFrontHot: Double? = null,
    val pressureRearHot: Double? = null,
    val camberFront: Double? = null,
    val camberRear: Double? = null,
    val toeFront: Double? = null,
    val toeRear: Double? = null,
    val heightFront: Double? = null,
    val heightRear: Double? = null,
    val bumpFront: Double? = null,
    val bumpRear: Double? = null,
    val reboundFront: Double? = null,
    val reboundRear: Double? = null,
    val springFront: Double? = null,
    val springRear: Double? = null,
    val barFront: String = "",
    val barRear: String = "",
    val wing: String = "",
    val brakeBias: Double? = null,
    /** Two wheels (0.10.0): spring preload and sag in millimetres, and the gearing as written ("15/43"). */
    val preloadFront: Double? = null,
    val preloadRear: Double? = null,
    val sagFront: Double? = null,
    val sagRear: Double? = null,
    val gearing: String? = null,
    /** Anything else, as a name and a value. */
    val extra: List<SetupItem> = emptyList(),
    val notes: String = "",
) {
    val isEmpty: Boolean get() = this == SetupValues()

    /** What changed from older values, as "Front cold pressure: 2.0 bar → 1.8 bar". */
    fun changes(old: SetupValues): List<String> {
        val out = ArrayList<String>()
        for (f in SetupField.all) {
            val a = f.display(old)
            val b = f.display(this)
            if (a != b) out.add("${f.title}: ${a ?: "—"} → ${b ?: "—"}")
        }
        val oldExtra = old.extra.associate { it.label to it.value }
        val newExtra = extra.associate { it.label to it.value }
        for (label in (oldExtra.keys + newExtra.keys).sorted()) {
            if (oldExtra[label] != newExtra[label]) out.add("$label: ${oldExtra[label] ?: "—"} → ${newExtra[label] ?: "—"}")
        }
        if (notes.trim() != old.notes.trim()) out.add(L("Note cambiate"))
        return out
    }
}

@Serializable
data class SetupItem(val id: String = newID(), val label: String, val value: String)

/** The values a setup had until it was changed: kept, never overwritten. */
@Serializable
data class SetupRevision(
    val id: String = newID(),
    /** When these values were replaced by the next ones (seconds since 1970). */
    val date: Double,
    val version: Int,
    val values: SetupValues,
)

/**
 * A setup of one car for some conditions, "Mugello in the wet": each its own, side by side with the
 * others. Changing one keeps the values it had as a revision.
 */
@Serializable
data class CarSetup(
    val id: String = newID(),
    val carID: String,
    val name: String = "",
    val weather: SetupWeather = SetupWeather.dry,
    /** The track it was made for, when there is one. */
    val track: String = "",
    val created: Double = nowSeconds(),
    val updated: Double = nowSeconds(),
    val values: SetupValues = SetupValues(),
    /** The earlier versions, newest first. */
    val history: List<SetupRevision> = emptyList(),
) {
    val version: Int get() = history.size + 1
    val displayName: String get() = name.trim().ifEmpty { weather.title }
    val snapshot: SessionSetup get() = SessionSetup(id, displayName, weather, version, values)
}

/** The setup a session was driven with, as it was that day. */
@Serializable
data class SessionSetup(val id: String, val name: String, val weather: SetupWeather, val version: Int, val values: SetupValues)

/** One value of a setup: what it is called, its unit and where it is kept. The list decides the order of the editor and the page. */
class SetupField(
    val id: String,
    val group: Group,
    val title: String,
    val number: ((SetupValues) -> Double?)? = null,
    val setNumber: ((SetupValues, Double?) -> SetupValues)? = null,
    val text: ((SetupValues) -> String)? = null,
    val setText: ((SetupValues, String) -> SetupValues)? = null,
    /** A pressure, shown in bar or psi. */
    val pressure: Boolean = false,
    val unit: String = "",
    val decimals: Int = 0,
    /** Which vehicles have it: camber and wings are for cars, preload and sag for bikes. */
    val wheels: Wheels = Wheels.any,
) {
    enum class Wheels { any, four, two }

    fun fits(kind: VehicleKind): Boolean = when (wheels) {
        Wheels.any -> true
        Wheels.four -> !kind.onTwoWheels
        Wheels.two -> kind.onTwoWheels
    }

    enum class Group {
        tyres, geometry, dampers, drivetrain, aero;

        val title: String
            get() = when (this) {
                tyres -> L("Gomme")
                geometry -> L("Geometria")
                dampers -> L("Ammortizzatori e molle")
                drivetrain -> L("Trasmissione")
                aero -> L("Aero e freni")
            }
    }

    val shownUnit: String get() = if (pressure) (if (Units.current == Units.metric) "bar" else "psi") else unit
    val shownDecimals: Int get() = if (pressure) (if (Units.current == Units.metric) 2 else 1) else decimals

    /** The value as it reads, with its unit; null when it is not set. */
    fun display(v: SetupValues): String? {
        text?.let { t -> return t(v).trim().ifEmpty { null } }
        val x = number?.invoke(v) ?: return null
        return format(shown(x), shownDecimals) + (if (shownUnit.isEmpty()) "" else " $shownUnit")
    }

    /** Kept value to the unit shown, and back. */
    fun shown(x: Double) = if (pressure && Units.current != Units.metric) x * 14.5038 else x
    fun kept(x: Double) = if (pressure && Units.current != Units.metric) x / 14.5038 else x

    companion object {
        fun format(x: Double, decimals: Int): String = NumberFormat.getNumberInstance(Locale.getDefault()).apply {
            minimumFractionDigits = 0
            maximumFractionDigits = decimals
            minimumIntegerDigits = 1
        }.format(x)

        private fun num(id: String, g: Group, title: String, get: (SetupValues) -> Double?, set: (SetupValues, Double?) -> SetupValues,
                        pressure: Boolean = false, unit: String = "", decimals: Int = 0, wheels: Wheels = Wheels.any) =
            SetupField(id, g, title, number = get, setNumber = set, pressure = pressure, unit = unit, decimals = decimals, wheels = wheels)

        private fun txt(id: String, g: Group, title: String, get: (SetupValues) -> String, set: (SetupValues, String) -> SetupValues, wheels: Wheels = Wheels.any) =
            SetupField(id, g, title, text = get, setText = set, wheels = wheels)

        /** The fields of the editor for a vehicle. */
        fun fields(kind: VehicleKind): List<SetupField> = all.filter { it.fits(kind) }

        val all: List<SetupField> by lazy {
            val t = Group.tyres
            val g = Group.geometry
            val d = Group.dampers
            val a = Group.aero
            val four = Wheels.four
            val two = Wheels.two
            listOf(
                txt("tyres", t, L("Gomme"), { it.tyres }, { v, x -> v.copy(tyres = x) }),
                num("pfc", t, L("Pressione ant. a freddo"), { it.pressureFrontCold }, { v, x -> v.copy(pressureFrontCold = x) }, pressure = true),
                num("prc", t, L("Pressione post. a freddo"), { it.pressureRearCold }, { v, x -> v.copy(pressureRearCold = x) }, pressure = true),
                num("pfh", t, L("Pressione ant. a caldo"), { it.pressureFrontHot }, { v, x -> v.copy(pressureFrontHot = x) }, pressure = true),
                num("prh", t, L("Pressione post. a caldo"), { it.pressureRearHot }, { v, x -> v.copy(pressureRearHot = x) }, pressure = true),
                num("cf", g, L("Campanatura ant."), { it.camberFront }, { v, x -> v.copy(camberFront = x) }, unit = "°", decimals = 1, wheels = four),
                num("cr", g, L("Campanatura post."), { it.camberRear }, { v, x -> v.copy(camberRear = x) }, unit = "°", decimals = 1, wheels = four),
                num("tf", g, L("Convergenza ant."), { it.toeFront }, { v, x -> v.copy(toeFront = x) }, unit = "mm", decimals = 1, wheels = four),
                num("tr", g, L("Convergenza post."), { it.toeRear }, { v, x -> v.copy(toeRear = x) }, unit = "mm", decimals = 1, wheels = four),
                num("hf", g, L("Altezza ant."), { it.heightFront }, { v, x -> v.copy(heightFront = x) }, unit = "mm"),
                num("hr", g, L("Altezza post."), { it.heightRear }, { v, x -> v.copy(heightRear = x) }, unit = "mm"),
                num("bf", d, L("Compressione ant."), { it.bumpFront }, { v, x -> v.copy(bumpFront = x) }, unit = L("click")),
                num("br", d, L("Compressione post."), { it.bumpRear }, { v, x -> v.copy(bumpRear = x) }, unit = L("click")),
                num("rf", d, L("Estensione ant."), { it.reboundFront }, { v, x -> v.copy(reboundFront = x) }, unit = L("click")),
                num("rr", d, L("Estensione post."), { it.reboundRear }, { v, x -> v.copy(reboundRear = x) }, unit = L("click")),
                num("sf", d, L("Molle ant."), { it.springFront }, { v, x -> v.copy(springFront = x) }, unit = "N/mm"),
                num("sr", d, L("Molle post."), { it.springRear }, { v, x -> v.copy(springRear = x) }, unit = "N/mm"),
                num("plf", d, L("Precarico ant."), { it.preloadFront }, { v, x -> v.copy(preloadFront = x) }, unit = "mm", decimals = 1, wheels = two),
                num("plr", d, L("Precarico post."), { it.preloadRear }, { v, x -> v.copy(preloadRear = x) }, unit = "mm", decimals = 1, wheels = two),
                num("sagf", d, L("Sag ant."), { it.sagFront }, { v, x -> v.copy(sagFront = x) }, unit = "mm", wheels = two),
                num("sagr", d, L("Sag post."), { it.sagRear }, { v, x -> v.copy(sagRear = x) }, unit = "mm", wheels = two),
                txt("arbf", d, L("Barra ant."), { it.barFront }, { v, x -> v.copy(barFront = x) }, wheels = four),
                txt("arbr", d, L("Barra post."), { it.barRear }, { v, x -> v.copy(barRear = x) }, wheels = four),
                txt("gear", Group.drivetrain, L("Rapporto (pignone/corona)"), { it.gearing ?: "" }, { v, x -> v.copy(gearing = x.ifEmpty { null }) }, wheels = two),
                txt("wing", a, L("Ala"), { it.wing }, { v, x -> v.copy(wing = x) }, wheels = four),
                num("bias", a, L("Ripartizione di frenata (ant.)"), { it.brakeBias }, { v, x -> v.copy(brakeBias = x) }, unit = "%", decimals = 1, wheels = four),
            )
        }
    }
}
