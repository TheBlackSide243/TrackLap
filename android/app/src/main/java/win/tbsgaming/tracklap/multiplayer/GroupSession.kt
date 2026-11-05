package win.tbsgaming.tracklap.multiplayer

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import win.tbsgaming.tracklap.data.DriverProfile
import win.tbsgaming.tracklap.data.Files
import win.tbsgaming.tracklap.data.Server
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.Geo
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.model.newID
import win.tbsgaming.tracklap.timing.Sample
import win.tbsgaming.tracklap.ui.L
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.pow

data class GroupPosition(val coord: Coord, val lap: Int, val distance: Double, val speed: Double, val utc: Double, val received: Long)

@Serializable
data class GroupTrack(val name: String, val lat: Double, val lon: Double) {
    fun isSame(o: GroupTrack?): Boolean = o != null && Geo.distance(Coord(lat, lon), Coord(o.lat, o.lon)) < 300

    companion object {
        fun of(t: Track?): GroupTrack? {
            val s = t?.start ?: return null
            return GroupTrack(t.name, s.mid.lat, s.mid.lon)
        }
    }
}

data class GroupMember(
    val id: String, val name: String, val vehicle: String, val track: GroupTrack?, val best: Double?, val last: Double?,
    val laps: Int, val online: Boolean, val color: Int, val position: GroupPosition? = null, val lapAt: Long? = null,
) {
    val isMoving: Boolean get() = position?.let { System.currentTimeMillis() - it.received < 5000 && it.speed > 3 } ?: false
}

data class Standing(
    val id: String, val name: String, val vehicle: String, val best: Double?, val last: Double?, val laps: Int,
    val online: Boolean, val moving: Boolean, val color: Int?, val isMe: Boolean, val lapAt: Long?,
)

data class TrackGap(val name: String, val seconds: Double, val color: Int)
data class Place(val position: Int, val count: Int, val gap: Double, val rival: String)

/**
 * A live group on the TrackLap server: everyone's best and last lap, where each car is on the track
 * and the gaps on track, over a WebSocket. The phone times the laps; the network only passes them on.
 */
class GroupSession(context: Context, private val profile: DriverProfile) {
    enum class Status { off, connecting, live, waiting }

    @Serializable
    data class Mine(val track: GroupTrack? = null, val best: Double? = null, val last: Double? = null, val laps: Int = 0)

    var status by mutableStateOf(Status.off); private set
    var code by mutableStateOf<String?>(null); private set
    var members by mutableStateOf<List<GroupMember>>(emptyList()); private set
    var problem by mutableStateOf<String?>(null)
    var mine by mutableStateOf(Mine()); private set
    var onStandingsChange: (() -> Unit)? = null

    private val prefs = context.getSharedPreferences("group", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private val client = OkHttpClient.Builder().pingInterval(25, TimeUnit.SECONDS).readTimeout(0, TimeUnit.MILLISECONDS).build()
    private var memberID = ""
    private var socket: WebSocket? = null
    private var generation = 0
    private var retries = 0
    private var lastReport = 0.0
    private val history = HashMap<String, ArrayList<GroupPosition>>()
    private val myHistory = ArrayList<GroupPosition>()
    private val colors = HashMap<String, Int>()

    val isOn: Boolean get() = code != null

    fun resume(track: Track?) {
        val c = prefs.getString("code", null) ?: return
        val m = prefs.getString("member", null) ?: return
        code = c
        memberID = m
        prefs.getString("mine", null)?.let { runCatching { mine = Files.json.decodeFromString(Mine.serializer(), it) } }
        setTrack(track)
        connect()
    }

    suspend fun create(track: Track?) {
        val c = Server.createGroup()
        join(c, track)
    }

    fun join(raw: String, track: Track?) {
        val c = clean(raw)
        if (c.length != 5) {
            problem = L("Il codice del gruppo ha cinque caratteri.")
            return
        }
        close()
        code = c
        memberID = newID()
        mine = Mine(GroupTrack.of(track))
        problem = null
        prefs.edit().putString("code", c).putString("member", memberID).apply()
        saveMine()
        connect()
    }

    fun leave() {
        close()
        prefs.edit().clear().apply()
        onStandingsChange?.invoke()
    }

    // Your side

    fun setTrack(t: Track?) {
        val g = GroupTrack.of(t)
        if (g != null && g.isSame(mine.track)) {
            mine = mine.copy(track = g)
            return
        }
        mine = Mine(g)
        myHistory.clear()
        saveMine()
        if (status == Status.live) sendHello()
        onStandingsChange?.invoke()
    }

    fun profileChanged() {
        if (status == Status.live) sendHello()
    }

    fun report(s: Sample, lap: Int, distance: Double) {
        if (code == null) return
        val utc = s.utc ?: s.wall
        val p = GroupPosition(s.coord, lap, distance, s.speed, utc, System.currentTimeMillis())
        val last = myHistory.lastOrNull()
        if (last == null || abs(utc - last.utc) >= 0.5) remember(p, myHistory)
        if (status != Status.live || abs(utc - lastReport) < 1) return
        lastReport = utc
        send("""{"t":"pos","lat":${s.coord.lat},"lon":${s.coord.lon},"lap":$lap,"d":$distance,"v":${s.speed},"g":$utc}""")
    }

    fun finished(lap: Lap) {
        if (code == null) return
        mine = mine.copy(last = lap.time, best = min(mine.best ?: Double.POSITIVE_INFINITY, lap.time), laps = mine.laps + 1)
        saveMine()
        if (status == Status.live) send("""{"t":"lap","n":${lap.number},"time":${lap.time}}""")
        onStandingsChange?.invoke()
    }

    // Standings

    private fun sameTrack(m: GroupMember): Boolean = mine.track?.isSame(m.track) ?: (m.track == null)

    val standings: List<Standing>
        get() {
            val rows = members.filter { sameTrack(it) }.map {
                Standing(it.id, it.name, it.vehicle, it.best, it.last, it.laps, it.online, it.isMoving, it.color, false, it.lapAt)
            } + Standing(memberID, profile.displayName, profile.displayVehicle, mine.best, mine.last, mine.laps, true, false, null, true, null)
            return rows.sortedWith { a, b ->
                val x = a.best
                val y = b.best
                when {
                    x != null && y != null -> x.compareTo(y)
                    x != null -> -1
                    y != null -> 1
                    else -> a.name.compareTo(b.name, ignoreCase = true)
                }
            }
        }

    val elsewhere: List<GroupMember> get() = members.filter { !sameTrack(it) }

    /** Your place among those with a lap, and the gap to the one ahead (or the margin over the second). */
    val place: Place?
        get() {
            val ranked = standings.filter { it.best != null }
            if (ranked.size <= 1) return null
            val i = ranked.indexOfFirst { it.isMe }
            if (i < 0) return null
            val best = ranked[i].best ?: return null
            val other = ranked[if (i == 0) 1 else i - 1]
            return Place(i + 1, ranked.size, best - (other.best ?: best), other.name)
        }

    /** The car right ahead and right behind on track, and by how many seconds, from where each passed the same point. */
    fun trackGaps(length: Double): Pair<TrackGap?, TrackGap?> {
        val now = System.currentTimeMillis()
        val me = myHistory.lastOrNull()
        if (length <= 200 || me == null || me.lap <= 0 || now - me.received >= 5000) return null to null
        var ahead: Pair<Double, TrackGap>? = null
        var behind: Pair<Double, TrackGap>? = null
        for (m in members) {
            if (!m.online || !sameTrack(m)) continue
            val p = m.position ?: continue
            if (p.lap <= 0 || now - p.received >= 5000) continue
            var a = (p.distance - me.distance) % length
            if (a < 0) a += length
            if (a < length / 2) {
                val t = time(me.distance, history[m.id] ?: emptyList(), length) ?: continue
                val gap = me.utc - t
                if (gap > 0 && gap < 600 && (ahead == null || a < ahead.first)) ahead = a to TrackGap(m.name, gap, m.color)
            } else {
                val t = time(p.distance, myHistory, length) ?: continue
                val gap = p.utc - t
                if (gap > 0 && gap < 600 && (behind == null || length - a < behind.first)) behind = (length - a) to TrackGap(m.name, gap, m.color)
            }
        }
        return ahead?.second to behind?.second
    }

    // Connection

    private fun connect() {
        val c = code ?: return
        generation += 1
        val gen = generation
        socket?.cancel()
        status = if (retries == 0) Status.connecting else Status.waiting
        val req = Request.Builder().url(Server.groupURL(c)).build()
        socket = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                main.post { if (gen == generation) sendHello() }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                main.post { if (gen == generation) handle(text) }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                main.post { if (gen == generation) dropped(gen, code, null) }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                main.post { if (gen == generation) dropped(gen, null, response?.code) }
            }
        })
    }

    private fun close() {
        generation += 1
        socket?.close(1000, null)
        socket = null
        code = null
        status = Status.off
        members = emptyList()
        history.clear()
        myHistory.clear()
        colors.clear()
        retries = 0
    }

    private fun dropped(gen: Int, closeCode: Int?, http: Int?) {
        if (code == null) return
        if (http == 404) {
            leave()
            problem = L("Questo gruppo non esiste più: creane uno nuovo.")
            return
        }
        if (closeCode == 4029) {
            leave()
            problem = L("Il gruppo è pieno.")
            return
        }
        status = Status.waiting
        retries += 1
        val delay = min(15.0, 2.0.pow(min(retries, 4))).toLong() * 1000
        main.postDelayed({ if (gen == generation && code != null) connect() }, delay)
    }

    private fun handle(s: String) {
        val o = runCatching { Files.json.parseToJsonElement(s).jsonObject }.getOrNull() ?: return
        when (o["t"]?.jsonPrimitive?.contentOrNull) {
            "state" -> {
                status = Status.live
                retries = 0
                problem = null
                val list = (o["members"] as? kotlinx.serialization.json.JsonArray)?.mapNotNull { (it as? JsonObject)?.let(::wire) } ?: emptyList()
                members = list.filter { it.id != memberID }.map { member(it) }
                (o["positions"] as? kotlinx.serialization.json.JsonArray)?.forEach { (it as? JsonObject)?.let(::applyPos) }
                onStandingsChange?.invoke()
            }
            "member" -> {
                val m = (o["member"] as? JsonObject)?.let(::wire) ?: return
                if (m.id == memberID) return
                val updated = member(m)
                val i = members.indexOfFirst { it.id == m.id }
                members = if (i >= 0) members.toMutableList().also { it[i] = updated } else members + updated
                onStandingsChange?.invoke()
            }
            "pos" -> applyPos(o)
            "lap" -> {
                val id = o.str("id") ?: return
                val i = members.indexOfFirst { it.id == id }
                if (i < 0) return
                val m = members[i]
                members = members.toMutableList().also {
                    it[i] = m.copy(best = o.num("best") ?: m.best, last = o.num("last") ?: o.num("time"),
                        laps = o.num("laps")?.toInt() ?: (m.laps + 1), lapAt = System.currentTimeMillis())
                }
                onStandingsChange?.invoke()
            }
        }
    }

    private class Wire(val id: String, val name: String, val vehicle: String, val track: GroupTrack?, val best: Double?, val last: Double?, val laps: Int, val online: Boolean)

    private fun JsonObject.str(k: String) = (this[k] as? kotlinx.serialization.json.JsonPrimitive)?.contentOrNull
    private fun JsonObject.num(k: String) = (this[k] as? kotlinx.serialization.json.JsonPrimitive)?.contentOrNull?.toDoubleOrNull()

    private fun wire(o: JsonObject): Wire? {
        val id = o.str("id") ?: return null
        val track = (o["track"] as? JsonObject)?.let { t ->
            val lat = t.num("lat")
            val lon = t.num("lon")
            if (lat != null && lon != null) GroupTrack(t.str("name") ?: "", lat, lon) else null
        }
        return Wire(id, o.str("name") ?: "", o.str("vehicle") ?: "", track, o.num("best"), o.num("last"), o.num("laps")?.toInt() ?: 0,
            o.str("online")?.toBooleanStrictOrNull() ?: true)
    }

    private fun member(w: Wire): GroupMember {
        val old = members.firstOrNull { it.id == w.id }
        val color = colors[w.id] ?: colors.size
        colors[w.id] = color
        return GroupMember(w.id, w.name, w.vehicle, w.track, w.best, w.last, w.laps, w.online, color, old?.position, old?.lapAt)
    }

    private fun applyPos(o: JsonObject) {
        val id = o.str("id") ?: return
        val i = members.indexOfFirst { it.id == id }
        if (i < 0) return
        val p = GroupPosition(Coord(o.num("lat") ?: return, o.num("lon") ?: return), o.num("lap")?.toInt() ?: 0, o.num("d") ?: 0.0,
            o.num("v") ?: 0.0, o.num("g") ?: 0.0, System.currentTimeMillis())
        members = members.toMutableList().also { it[i] = it[i].copy(position = p) }
        remember(p, history.getOrPut(id) { ArrayList() })
    }

    private fun sendHello() {
        val track = mine.track?.let { """{"name":${quote(it.name)},"lat":${it.lat},"lon":${it.lon}}""" } ?: "null"
        send(
            """{"t":"hello","id":${quote(memberID)},"name":${quote(profile.displayName)},"vehicle":${quote(profile.displayVehicle)},""" +
                """"track":$track,"best":${mine.best ?: "null"},"last":${mine.last ?: "null"},"laps":${mine.laps}}""",
        )
    }

    private fun quote(s: String) = kotlinx.serialization.json.JsonPrimitive(s).toString()

    private fun send(text: String) {
        socket?.send(text)
    }

    private fun saveMine() = prefs.edit().putString("mine", Files.json.encodeToString(Mine.serializer(), mine)).apply()

    companion object {
        private const val KEEP = 300_000L

        fun clean(raw: String) = raw.uppercase().filter { it.code < 128 && it.isLetterOrDigit() }.take(5)
        fun inviteURL(code: String) = "tracklap://join/$code"

        /** When a car with this history passed a point of the lap, interpolated between two positions. */
        fun time(x: Double, h: List<GroupPosition>, length: Double): Double? {
            if (h.size <= 1) return null
            for (i in h.size - 1 downTo 1) {
                val a = h[i - 1]
                val b = h[i]
                if (a.lap <= 0 || b.lap <= 0) continue
                var db = b.distance
                if (b.lap == a.lap + 1) db += length else if (b.lap != a.lap) continue
                var target = x
                if (target < a.distance) target += length
                if (db <= a.distance || target > db) continue
                return a.utc + (b.utc - a.utc) * (target - a.distance) / (db - a.distance)
            }
            return null
        }

        private fun remember(p: GroupPosition, h: ArrayList<GroupPosition>) {
            h.add(p)
            val i = h.indexOfFirst { p.received - it.received < KEEP }
            if (i > 0) h.subList(0, i).clear()
        }
    }
}
