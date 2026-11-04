package win.tbsgaming.tracklap.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import win.tbsgaming.tracklap.SourceKind
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.SharedLap
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.model.nowSeconds
import win.tbsgaming.tracklap.ui.Fmt
import java.io.File

/** A friend's lap in the list: enough to show and pick it, the trace stays in its file. */
@Serializable
data class FriendLap(
    val id: String,
    /** Your track it was matched to, or the friend's track added to yours. */
    val trackID: String,
    val trackName: String,
    val driver: String,
    val vehicle: String,
    val source: String,
    val date: Double,
    val time: Double,
    val added: Double = nowSeconds(),
) {
    val title: String get() = driver + " · " + Fmt.lap(time)
    val sourceTitle: String get() = SourceKind.entries.firstOrNull { it.name == source }?.short ?: source
}

/** The laps friends sent, as .tracklap files: one file each, plus an index for the lists. */
class FriendLapStore {
    var laps by mutableStateOf<List<FriendLap>>(emptyList()); private set
    private val dir get() = File(Files.docs, "friends").also { it.mkdirs() }
    private val indexFile get() = File(Files.docs, "friends.json")
    private val list = ListSerializer(FriendLap.serializer())

    init {
        laps = Files.read(list, indexFile) ?: emptyList()
    }

    /** The same lap sent twice replaces the first. */
    fun add(s: SharedLap, track: Track): FriendLap {
        file(s.id).writeText(SharedLap.encodeLocal(s))
        val f = FriendLap(s.id, track.id, track.name, s.driver, s.vehicle, s.source, s.date, s.lap.time)
        laps = listOf(f) + laps.filter { it.id != f.id }
        save()
        return f
    }

    fun shared(id: String): SharedLap? = file(id).takeIf { it.exists() }?.let { SharedLap.decodeLocal(it.readText()) }
    fun lap(id: String): Lap? = shared(id)?.lap

    /** The lap's track was deleted and added back. */
    fun move(id: String, track: Track) {
        laps = laps.map { if (it.id == id) it.copy(trackID = track.id, trackName = track.name) else it }
        save()
    }

    fun delete(id: String) {
        file(id).delete()
        laps = laps.filter { it.id != id }
        save()
    }

    /** The friends' laps on a track, fastest first. */
    fun laps(track: String?): List<FriendLap> = laps.filter { it.trackID == track }.sortedBy { it.time }

    private fun save() = Files.write(laps, list, indexFile)
    private fun file(id: String) = File(dir, "$id.tracklap")
}
