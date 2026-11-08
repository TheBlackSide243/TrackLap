package win.tbsgaming.tracklap.model

import kotlinx.serialization.Serializable

/** A driver you are friends with on TrackLap: friends both ways, from an invitation link. */
@Serializable
data class Friend(
    val id: String,
    val name: String,
    /** Their garage's code, once they have shown a car (to friends or to everyone). */
    val garage: String? = null,
    /** Milliseconds since 1970: when you became friends. */
    val since: Double? = null,
) {
    val initial: String get() = name.take(1).uppercase()
}

/**
 * A friend as the server sends them when you open them: their best lap on every track, from the
 * online leaderboards, and a few numbers worked out from those.
 */
@Serializable
data class FriendProfile(
    val id: String,
    val name: String,
    val garage: String? = null,
    val since: Double? = null,
    val laps: List<Best> = emptyList(),
    val stats: Stats? = null,
) {
    @Serializable
    data class BestTrack(val id: String, val name: String, val length: Double? = null)

    @Serializable
    data class Best(
        val track: BestTrack,
        val source: String,
        val time: Double,
        /** Milliseconds since 1970: the day of the lap, and of the last session on that track. */
        val date: Double,
        val last: Double,
        val sessions: Int = 1,
        val vehicle: String = "",
        val garage: String = "",
        val car: String = "",
        val rank: Int,
        val of: Int,
        /** "car", "motorcycle" or "scooter"; null for laps from before 0.10.0. */
        val kind: String? = null,
    ) {
        val id: String get() = track.id + "/" + source
        val vehicleKind: VehicleKind? get() = VehicleKind.of(kind)
    }

    @Serializable
    data class Stats(
        val tracks: Int,
        val sessions: Int,
        val wins: Int,
        val favourite: String? = null,
        val last: Double? = null,
    )
}

/** Your invitation link's code and when it stops working (milliseconds since 1970). */
@Serializable
data class FriendInvite(val code: String, val expires: Double)
