package win.tbsgaming.tracklap.gps

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.timing.Sample
import kotlin.coroutines.resume
import kotlin.math.max

/** The phone's own GPS: about 1 Hz on most phones, fine for trying the app and for marking the line on foot. */
class PhoneGps(private val context: Context) {
    var accuracy by mutableStateOf<Double?>(null); private set
    var permitted by mutableStateOf(false); private set
    var onSample: ((Sample) -> Unit)? = null

    private val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private var streaming = false
    private var wanted = false

    private val listener = object : LocationListener {
        override fun onLocationChanged(l: Location) = deliver(l)
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    fun hasPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** The permission was answered: start if it was wanted. */
    fun permissionChanged() {
        permitted = hasPermission()
        if (wanted && permitted && !streaming) start()
    }

    @SuppressLint("MissingPermission")
    fun start() {
        wanted = true
        permitted = hasPermission()
        if (!permitted || streaming) return
        streaming = true
        manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, 0L, 0f, listener, Looper.getMainLooper())
    }

    fun stop() {
        wanted = false
        if (!streaming) return
        streaming = false
        manager.removeUpdates(listener)
    }

    private fun deliver(l: Location) {
        accuracy = l.accuracy.toDouble()
        val t = l.time / 1000.0
        onSample?.invoke(
            Sample(
                t = t, coord = Coord(l.latitude, l.longitude),
                speed = if (l.hasSpeed()) max(0.0, l.speed.toDouble()) else 0.0,
                heading = if (l.hasBearing()) l.bearing.toDouble() else 0.0,
                utc = t, alt = if (l.hasAltitude()) l.altitude else null,
            ),
        )
    }

    /** Where the phone is now: the last fix if recent, else a fresh one (network or GPS), within 15 s. */
    @SuppressLint("MissingPermission")
    suspend fun currentLocation(): Coord? {
        if (!hasPermission()) return null
        val recent = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .filter { System.currentTimeMillis() - it.time < 60_000 }
            .maxByOrNull { it.time }
        if (recent != null) return Coord(recent.latitude, recent.longitude)
        return withTimeoutOrNull(15_000) {
            suspendCancellableCoroutine { c ->
                val once = object : LocationListener {
                    override fun onLocationChanged(l: Location) {
                        manager.removeUpdates(this)
                        if (c.isActive) c.resume(Coord(l.latitude, l.longitude))
                    }
                    @Deprecated("Deprecated in Java")
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                }
                val providers = manager.getProviders(true).filter { it == LocationManager.GPS_PROVIDER || it == LocationManager.NETWORK_PROVIDER }
                if (providers.isEmpty()) {
                    c.resume(null)
                } else {
                    for (p in providers) manager.requestLocationUpdates(p, 0L, 0f, once, Looper.getMainLooper())
                }
                c.invokeOnCancellation { manager.removeUpdates(once) }
            }
        } ?: manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER)?.let { Coord(it.latitude, it.longitude) }
    }
}
