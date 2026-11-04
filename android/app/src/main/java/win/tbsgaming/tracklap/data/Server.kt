package win.tbsgaming.tracklap.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import win.tbsgaming.tracklap.model.Car
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.PublicGarage
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.ui.L
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale
import kotlin.math.roundToLong

/** Why the server said no, as the screens tell it. */
class ServerFailure(val kind: Kind) : Exception() {
    enum class Kind { offline, refused, signedOut, taken, wrongLogin, wrongPassword, badName, shortPassword, tooMany, notFound }

    override val message: String
        get() = when (kind) {
            Kind.offline -> L("Il server di TrackLap non risponde: controlla la connessione e riprova.")
            Kind.refused -> L("Il server ha rifiutato la richiesta.")
            Kind.signedOut -> L("Sei uscito dall'account: accedi di nuovo.")
            Kind.taken -> L("Questo nome utente è già preso: scegline un altro.")
            Kind.wrongLogin -> L("Nome utente o password sbagliati.")
            Kind.wrongPassword -> L("La password non è giusta.")
            Kind.badName -> L("Il nome utente va da 3 a 20 caratteri: lettere, numeri, punto, trattino e trattino basso, senza spazi.")
            Kind.shortPassword -> L("La password deve avere almeno 8 caratteri.")
            Kind.tooMany -> L("Troppi tentativi: riprova tra qualche minuto.")
            Kind.notFound -> L("Questo garage non esiste più, oppure è stato nascosto.")
        }
}

@Serializable
data class Leaderboard(val track: BoardTrack? = null, val laps: List<Entry> = emptyList()) {
    @Serializable
    data class BoardTrack(val id: String, val name: String)

    @Serializable
    data class Entry(
        val rank: Int,
        val name: String,
        val vehicle: String = "",
        val garage: String? = null,
        val car: String? = null,
        val source: String,
        val time: Double,
        /** Milliseconds since 1970. */
        val date: Double,
        val mine: Boolean = false,
    ) {
        val id: String get() = source + rank
        val carLink: GarageLink? get() = garage?.takeIf { it.isNotEmpty() }?.let { GarageLink(it, car?.takeIf { c -> c.isNotEmpty() }) }
    }
}

@Serializable
data class Submitted(val rank: Int, val of: Int)

/** A public garage to open, on one of its cars or on the whole garage. */
data class GarageLink(val code: String, val car: String? = null) {
    companion object {
        /** tracklap://garage/<code>[/<car>], from the garage page's button. */
        fun parse(uri: android.net.Uri): GarageLink? {
            if (uri.scheme != "tracklap" || uri.host != "garage") return null
            val parts = uri.pathSegments
            val code = parts.firstOrNull()?.uppercase() ?: return null
            if (code.length != 8) return null
            return GarageLink(code, parts.getOrNull(1))
        }
    }
}

/**
 * The TrackLap server (server/ in the repository, a Cloudflare Worker): new live groups, the online
 * leaderboards, the accounts and the public garages. The same server and accounts as the iPhone app.
 */
object Server {
    const val BASE = "https://tracklap.tbsgaming.win"

    @Serializable
    data class Account(val id: String, val name: String, val garage: String? = null)

    @Serializable
    data class SignedIn(val token: String, val account: Account)

    @Serializable
    private data class Code(val code: String)

    @Serializable
    private data class Missing(val missing: List<String> = emptyList())

    // Groups

    suspend fun createGroup(): String = send("v1/rooms", "POST", Code.serializer()).code

    fun groupURL(code: String) = BASE.replaceFirst("https://", "wss://").replaceFirst("http://", "ws://") + "/v1/rooms/$code/ws"

    // Leaderboards

    /** The leaderboard of a track, found by its start line and the length of a lap. Signed in, your laps come back marked. */
    suspend fun board(track: Track, length: Double?, token: String?): Leaderboard {
        val start = track.start ?: return Leaderboard()
        val q = String.format(Locale.US, "lat=%.6f&lon=%.6f&len=%d", start.mid.lat, start.mid.lon, (length ?: 0.0).toInt())
        return send("v1/boards?$q", "GET", Leaderboard.serializer(), token = token)
    }

    /** A lap for the leaderboard: kept if it is your best there with that GPS, under your account, linked to the car. */
    suspend fun submit(lap: Lap, source: String, track: Track, car: String?, token: String): Submitted {
        val start = track.start ?: throw ServerFailure(ServerFailure.Kind.refused)
        if (source == "demo") throw ServerFailure(ServerFailure.Kind.refused)
        val body = buildJsonObject {
            put("source", source)
            put("time", lap.time)
            put("distance", lap.distance)
            put("sectors", kotlinx.serialization.json.JsonArray(lap.sectors.map { kotlinx.serialization.json.JsonPrimitive(it) }))
            put("date", (lap.startedAt * 1000).roundToLong().toDouble())
            putJsonObject("track") {
                put("name", track.name)
                put("lat", start.mid.lat)
                put("lon", start.mid.lon)
            }
            if (car != null) put("car", car)
        }
        return send("v1/laps", "POST", Submitted.serializer(), body, token)
    }

    // Accounts

    private fun credentials(name: String, password: String) = buildJsonObject {
        put("username", name)
        put("password", password)
    }

    suspend fun signUp(name: String, password: String): SignedIn =
        send("v1/accounts", "POST", SignedIn.serializer(), credentials(name, password)) {
            when (it) {
                409 -> ServerFailure.Kind.taken
                400 -> if (isValidName(name)) ServerFailure.Kind.shortPassword else ServerFailure.Kind.badName
                429 -> ServerFailure.Kind.tooMany
                else -> null
            }
        }

    suspend fun signIn(name: String, password: String): SignedIn =
        send("v1/sessions", "POST", SignedIn.serializer(), credentials(name, password)) {
            when (it) {
                403 -> ServerFailure.Kind.wrongLogin
                429 -> ServerFailure.Kind.tooMany
                else -> null
            }
        }

    suspend fun signOut(token: String) {
        runCatching { send("v1/sessions", "DELETE", null, token = token) }
    }

    suspend fun me(token: String): Account = send("v1/me", "GET", Account.serializer(), token = token)

    suspend fun changePassword(token: String, old: String, new: String): SignedIn =
        send("v1/me/password", "POST", SignedIn.serializer(), buildJsonObject { put("old", old); put("new", new) }, token) {
            when (it) {
                403 -> ServerFailure.Kind.wrongPassword
                400 -> ServerFailure.Kind.shortPassword
                else -> null
            }
        }

    suspend fun deleteAccount(token: String, password: String) {
        send("v1/me", "DELETE", null, buildJsonObject { put("password", password) }, token) { if (it == 403) ServerFailure.Kind.wrongPassword else null }
    }

    fun isValidName(name: String) = Regex("^[A-Za-z0-9_.-]{3,20}$").matches(name)

    // Garages

    suspend fun openGarage(token: String): String = send("v1/me/garage", "POST", Code.serializer(), token = token).code

    /** Your cars as they are now; the answer lists the photos the server does not have yet. */
    suspend fun putGarage(code: String, cars: List<Car>, token: String): List<String> {
        val body = buildJsonObject { put("cars", Files.json.encodeToJsonElement(ListSerializer(Car.serializer()), cars)) }
        return send("v1/garages/$code", "PUT", Missing.serializer(), body, token).missing
    }

    suspend fun putPhoto(code: String, photo: String, jpeg: ByteArray, token: String) {
        raw("v1/garages/$code/photos/$photo", "PUT", jpeg, "image/jpeg", token, 60_000)
    }

    suspend fun garage(code: String, token: String?): PublicGarage =
        send("v1/garages/$code", "GET", PublicGarage.serializer(), token = token) { if (it == 404) ServerFailure.Kind.notFound else null }

    suspend fun report(code: String, car: String?, reason: String) {
        send("v1/garages/$code/report", "POST", null, buildJsonObject { put("reason", reason); if (car != null) put("car", car) })
    }

    fun photoURL(code: String, photo: String) = "$BASE/v1/garages/$code/photos/$photo"

    /** The page anyone can open, also without the app; with a car, it opens on that car. */
    fun garageURL(code: String, car: String? = null) = "$BASE/g/$code" + (car?.let { "#" + URLEncoder.encode(it, "UTF-8") } ?: "")

    // Plumbing

    private suspend fun <T> send(
        path: String, method: String, serializer: KSerializer<T>?, json: JsonObject? = null, token: String? = null,
        failure: (Int) -> ServerFailure.Kind? = { null },
    ): T {
        val (status, text) = raw(path, method, json?.toString()?.toByteArray(Charsets.UTF_8), if (json != null) "application/json" else null, token, 15_000)
        if (status !in 200..299) {
            throw ServerFailure(failure(status) ?: when (status) {
                401 -> ServerFailure.Kind.signedOut
                429 -> ServerFailure.Kind.tooMany
                else -> ServerFailure.Kind.refused
            })
        }
        @Suppress("UNCHECKED_CAST")
        if (serializer == null) return Unit as T
        return runCatching { Files.json.decodeFromString(serializer, text) }.getOrNull() ?: throw ServerFailure(ServerFailure.Kind.refused)
    }

    private suspend fun raw(path: String, method: String, body: ByteArray?, type: String?, token: String?, timeout: Int): Pair<Int, String> =
        withContext(Dispatchers.IO) {
            try {
                val c = URL("$BASE/$path").openConnection() as HttpURLConnection
                try {
                    c.requestMethod = method
                    c.connectTimeout = timeout
                    c.readTimeout = timeout
                    c.setRequestProperty("User-Agent", Net.userAgent)
                    if (token != null) c.setRequestProperty("Authorization", "Bearer $token")
                    if (body != null) {
                        c.doOutput = true
                        c.setRequestProperty("Content-Type", type ?: "application/octet-stream")
                        c.outputStream.use { it.write(body) }
                    }
                    val status = c.responseCode
                    val stream = if (status in 200..299) c.inputStream else c.errorStream
                    status to (stream?.use { it.readBytes().toString(Charsets.UTF_8) } ?: "")
                } finally {
                    c.disconnect()
                }
            } catch (e: IOException) {
                throw ServerFailure(ServerFailure.Kind.offline)
            }
        }
}
