package win.tbsgaming.tracklap.data

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import win.tbsgaming.tracklap.Edition
import win.tbsgaming.tracklap.SourceKind
import win.tbsgaming.tracklap.model.VehicleKind
import win.tbsgaming.tracklap.model.nowSeconds
import win.tbsgaming.tracklap.ui.L
import kotlin.math.roundToLong

/** Who sees your sessions in your garage, apart from who sees the vehicles. */
enum class SessionAudience {
    nobody, friends, everyone;

    val title: String
        get() = when (this) {
            nobody -> L("Nessuno")
            friends -> L("Solo amici")
            everyone -> L("Tutti")
        }

    val summary: String
        get() = when (this) {
            nobody -> L("Le sessioni restano su questo telefono.")
            friends -> L("I tuoi amici vedono pista, data e tempi di ogni sessione.")
            everyone -> L("Chiunque apra il tuo garage vede pista, data e tempi di ogni sessione.")
        }
}

/** A session as it goes to the server: where, when, the lap times and what it was driven with. No traces and no positions. */
@Serializable
data class SharedSession(
    val id: String,
    val track: String,
    /** Milliseconds since 1970. */
    val date: Double,
    val laps: List<Double>,
    val best: Double? = null,
    val car: String? = null,
    val kind: String? = null,
    /** "device" or "phone". */
    val source: String = "phone",
) {
    val vehicle: VehicleKind get() = VehicleKind.of(kind) ?: VehicleKind.car
}

/** Someone's shared sessions as the server sends them. */
@Serializable
data class SharedSessions(
    val code: String,
    val name: String = "",
    val audience: String = "all",
    val sessions: List<SharedSession> = emptyList(),
    val mine: Boolean? = null,
)

/**
 * Your sessions in your garage on the server, for everyone or for your friends, like on the iPhone:
 * the list goes up a while after a session is saved or deleted. Set to nobody, it is removed from the server.
 */
class SharedSessionStore(context: Context) {
    private val prefs = context.getSharedPreferences("tracklap", Context.MODE_PRIVATE)
    @set:JvmName("assignAudience") var audience by mutableStateOf(
        prefs.getString("sessionAudience", null)?.let { runCatching { SessionAudience.valueOf(it) }.getOrNull() } ?: SessionAudience.nobody,
    ); private set
    var sync by mutableStateOf<GarageStore.Sync>(GarageStore.Sync.Idle); private set
    var account: AccountStore? = null
    var sessions: SessionStore? = null
    var garage: GarageStore? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pending: Job? = null

    fun updateAudience(a: SessionAudience) {
        if (a == audience) return
        audience = a
        prefs.edit().putString("sessionAudience", a.name).apply()
        publishSoon(now = true)
    }

    fun accountChanged() {
        sync = GarageStore.Sync.Idle
        publishSoon(now = true)
    }

    /** Sessions are saved after every lap: one upload a while after the last. */
    fun publishSoon(now: Boolean = false) {
        if (!Edition.online) return
        pending?.cancel()
        pending = scope.launch {
            if (!now) delay(10_000)
            publish()
        }
    }

    suspend fun publish() {
        val account = account
        val token = account?.token
        if (account == null || !account.isSignedIn || token == null) {
            sync = GarageStore.Sync.Idle
            return
        }
        // Never shared and nothing to take down.
        if (audience == SessionAudience.nobody && !prefs.getBoolean("sessionsShared", false)) {
            sync = GarageStore.Sync.Idle
            return
        }
        sync = GarageStore.Sync.Syncing
        try {
            val code = account.garageCode()
            if (audience == SessionAudience.nobody) {
                Server.deleteSessions(code, token)
                prefs.edit().putBoolean("sessionsShared", false).apply()
            } else {
                Server.putSessions(code, shared(), if (audience == SessionAudience.friends) "friends" else "all", token)
                prefs.edit().putBoolean("sessionsShared", true).apply()
            }
            sync = GarageStore.Sync.Done(nowSeconds())
        } catch (e: ServerFailure) {
            if (e.kind == ServerFailure.Kind.signedOut) account.signedOutElsewhere()
            sync = GarageStore.Sync.Failed(e.message)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            sync = GarageStore.Sync.Failed(e.message ?: L("Il server ha rifiutato la richiesta."))
        }
    }

    /** The newest sessions driven for real, as many as fit in one request. */
    private fun shared(): List<SharedSession> {
        val store = sessions ?: return emptyList()
        val showCar = garage?.isShown == true
        var list = store.withLapTimes().mapNotNull { s ->
            val source = SourceKind.ofSession(s.source)
            val times = s.lapTimes
            if (source == SourceKind.demo || times.isNullOrEmpty()) return@mapNotNull null
            val laps = times.take(MAX_LAPS).map { (it * 1000).roundToLong() / 1000.0 }
            SharedSession(
                id = s.id, track = s.trackName.take(60), date = (s.date * 1000).roundToLong().toDouble(), laps = laps, best = laps.minOrNull(),
                // The vehicle's name only when the garage is shown: a hidden garage keeps it to itself.
                car = if (showCar) s.carName?.take(40) else null, kind = s.vehicle.name,
                source = if (source == SourceKind.device) "device" else "phone",
            )
        }.sortedByDescending { it.date }.take(MAX_SESSIONS)
        val serializer = ListSerializer(SharedSession.serializer())
        while (list.size > 1 && Files.json.encodeToString(serializer, list).length > MAX_BYTES) {
            list = list.dropLast(maxOf(1, list.size / 10))
        }
        return list
    }

    companion object {
        const val MAX_SESSIONS = 300
        const val MAX_LAPS = 200
        const val MAX_BYTES = 240_000
    }
}
