package win.tbsgaming.tracklap.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.Geo
import win.tbsgaming.tracklap.model.newID
import win.tbsgaming.tracklap.ui.L
import java.util.Locale

/**
 * Your TrackLap account: the name everyone sees on the leaderboards and on your garage. The token the
 * server gives at sign-in stays in the app's private storage; the password is never kept on the phone.
 */
class AccountStore(context: Context) {
    private val prefs = context.getSharedPreferences("account", Context.MODE_PRIVATE)

    @set:JvmName("assignName") var name by mutableStateOf<String?>(null); private set
    /** Your public garage's code, once you have shown a car. */
    @set:JvmName("assignGarage") var garage by mutableStateOf<String?>(null); private set
    var token by mutableStateOf<String?>(null); private set
    val isSignedIn: Boolean get() = token != null && name != null

    /** Called after signing in or out, for whoever keeps something tied to the account. */
    var onChange: (() -> Unit)? = null

    init {
        token = prefs.getString("token", null)
        name = if (token == null) null else prefs.getString("name", null)
        garage = prefs.getString("garage", null)
    }

    suspend fun signUp(name: String, password: String) = apply(Server.signUp(name.trim(), password))
    suspend fun signIn(name: String, password: String) = apply(Server.signIn(name.trim(), password))

    suspend fun signOut() {
        token?.let { Server.signOut(it) }
        clear()
    }

    suspend fun changePassword(old: String, new: String) {
        val t = token ?: throw ServerFailure(ServerFailure.Kind.signedOut)
        apply(Server.changePassword(t, old, new))
    }

    /** The account, its garage and its laps on the leaderboards, for good. */
    suspend fun delete(password: String) {
        val t = token ?: throw ServerFailure(ServerFailure.Kind.signedOut)
        Server.deleteAccount(t, password)
        clear()
    }

    /** Checks the token is still good (another phone may have changed the password) and picks up the garage made elsewhere. */
    suspend fun refresh() {
        val t = token ?: return
        try {
            val me = Server.me(t)
            name = me.name
            setGarage(me.garage)
        } catch (e: ServerFailure) {
            if (e.kind == ServerFailure.Kind.signedOut) clear()
        }
    }

    /** Your garage's code, made on the server the first time. */
    suspend fun garageCode(): String {
        garage?.let { return it }
        val t = token ?: throw ServerFailure(ServerFailure.Kind.signedOut)
        val code = Server.openGarage(t)
        setGarage(code)
        return code
    }

    /** A request came back refused for the token: signed out here too. */
    fun signedOutElsewhere() = clear()

    private fun apply(s: Server.SignedIn) {
        token = s.token
        name = s.account.name
        prefs.edit().putString("token", s.token).putString("name", s.account.name).apply()
        setGarage(s.account.garage)
        onChange?.invoke()
    }

    private fun setGarage(code: String?) {
        garage = code
        prefs.edit().putString("garage", code).apply()
    }

    private fun clear() {
        token = null
        name = null
        prefs.edit().remove("token").remove("name").apply()
        setGarage(null)
        onChange?.invoke()
    }
}

/**
 * Who you are to your friends: the name and the vehicle on the laps you share, in a live group and in
 * the online leaderboards.
 */
class DriverProfile(context: Context) {
    private val prefs = context.getSharedPreferences("tracklap", Context.MODE_PRIVATE)
    @set:JvmName("assignName") var name by mutableStateOf(prefs.getString("driverName", "") ?: ""); private set
    @set:JvmName("assignVehicle") var vehicle by mutableStateOf(prefs.getString("driverVehicle", "") ?: ""); private set
    /** Send the best lap of every session to the online leaderboard of its track. */
    var publishLaps by mutableStateOf(prefs.getBoolean("publishLaps", false)); private set
    val id: String = prefs.getString("driverID", null) ?: newID().also { prefs.edit().putString("driverID", it).apply() }

    val hasName: Boolean get() = name.trim().isNotEmpty()
    /** What the others see: the name without stray spaces, or "Driver". */
    val displayName: String get() = name.trim().ifEmpty { L("Pilota") }
    val displayVehicle: String get() = vehicle.trim()

    fun setName(n: String) {
        name = n.take(MAX)
        prefs.edit().putString("driverName", name).apply()
    }

    fun setVehicle(v: String) {
        vehicle = v.take(MAX)
        prefs.edit().putString("driverVehicle", vehicle).apply()
    }

    fun setPublish(on: Boolean) {
        publishLaps = on
        prefs.edit().putBoolean("publishLaps", on).apply()
    }

    companion object {
        const val MAX = 24
    }
}

/** The weather at the track now, from Open-Meteo (no key; only the track's position is sent), kept 15 minutes. */
object TrackWeather {
    data class Now(val wet: Boolean, val temperature: Double?)

    private var cache: Triple<Coord, Long, Now>? = null

    suspend fun now(c: Coord): Now? {
        cache?.let { (at, time, now) -> if (Geo.distance(at, c) < 2000 && System.currentTimeMillis() - time < 15 * 60_000) return now }
        val url = String.format(Locale.US, "https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f&current=temperature_2m,precipitation,weather_code", c.lat, c.lon)
        val text = runCatching { Net.get(url, 10_000) }.getOrNull() ?: return null
        val cur = runCatching { Files.json.parseToJsonElement(text) }.getOrNull()
            ?.let { (it as? kotlinx.serialization.json.JsonObject)?.get("current") as? kotlinx.serialization.json.JsonObject } ?: return null
        fun num(k: String) = (cur[k] as? kotlinx.serialization.json.JsonPrimitive)?.content?.toDoubleOrNull()
        // Drizzle, rain, freezing rain, showers and thunderstorms.
        val code = num("weather_code")?.toInt() ?: 0
        val wet = (num("precipitation") ?: 0.0) > 0.1 || code in 51..67 || code in 80..82 || code in 95..99
        val now = Now(wet, num("temperature_2m"))
        cache = Triple(c, System.currentTimeMillis(), now)
        return now
    }
}
