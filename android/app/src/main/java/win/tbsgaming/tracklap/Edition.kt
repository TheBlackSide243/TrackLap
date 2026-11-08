package win.tbsgaming.tracklap

/**
 * TrackLap Lite (the "lite" flavor, its own app next to the full one): the timer, drag, tracks and
 * sessions, all on the phone. No account, no garage, no friends, no leaderboards, no live groups.
 */
object Edition {
    val isLite: Boolean get() = BuildConfig.LITE
    val online: Boolean get() = !isLite
}
