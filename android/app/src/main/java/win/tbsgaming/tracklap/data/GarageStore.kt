package win.tbsgaming.tracklap.data

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.util.LruCache
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import win.tbsgaming.tracklap.model.Car
import win.tbsgaming.tracklap.model.CarSetup
import win.tbsgaming.tracklap.model.SetupRevision
import win.tbsgaming.tracklap.model.SharedSetup
import win.tbsgaming.tracklap.model.newID
import win.tbsgaming.tracklap.model.nowSeconds
import win.tbsgaming.tracklap.ui.L
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Your cars: an index (garage.json) and one JPEG per photo in the garage folder. Public, the garage
 * goes to the server a moment after every change: the cars first, then the photos the server says it
 * is missing. The setups stay on this phone: never sent anywhere, only to a file you export yourself.
 */
class GarageStore(private val context: Context) {
    sealed interface Sync {
        data object Idle : Sync
        data object Syncing : Sync
        data class Done(val at: Double) : Sync
        data class Failed(val message: String) : Sync
    }

    private val prefs = context.getSharedPreferences("tracklap", Context.MODE_PRIVATE)
    var cars by mutableStateOf<List<Car>>(emptyList()); private set
    var setups by mutableStateOf<List<CarSetup>>(emptyList()); private set
    /** Shown to everyone at the garage's link and next to your laps on the leaderboards. */
    var isPublic by mutableStateOf(prefs.getBoolean("garagePublic", false)); private set
    var sync by mutableStateOf<Sync>(Sync.Idle); private set
    var account: AccountStore? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pending: Job? = null
    private val cache = LruCache<String, Bitmap>(12)
    private val dir get() = File(Files.docs, "garage").also { it.mkdirs() }
    private val indexFile get() = File(Files.docs, "garage.json")
    private val setupsFile get() = File(Files.docs, "setups.json")
    private val carList = ListSerializer(Car.serializer())
    private val setupList = ListSerializer(CarSetup.serializer())

    init {
        cars = Files.read(carList, indexFile) ?: emptyList()
        setups = Files.read(setupList, setupsFile) ?: emptyList()
        sweep()
    }

    fun car(id: String?): Car? = id?.let { i -> cars.firstOrNull { it.id == i } }
    val isFull: Boolean get() = cars.size >= Car.MAX_CARS

    /** A new car goes first; the photo it had before, if it changed, is deleted. */
    fun save(car: Car) {
        val old = car(car.id)
        val i = cars.indexOfFirst { it.id == car.id }
        cars = if (i >= 0) cars.toMutableList().also { it[i] = car } else {
            if (isFull) return
            listOf(car) + cars
        }
        old?.photo?.let { if (it != car.photo) discardPhoto(it) }
        changed()
    }

    fun delete(id: String) {
        val car = car(id) ?: return
        cars = cars.filter { it.id != id }
        setups = setups.filter { it.carID != id }
        Files.write(setups, setupList, setupsFile)
        car.photo?.let { discardPhoto(it) }
        changed()
    }

    fun move(id: String, by: Int) {
        val i = cars.indexOfFirst { it.id == id }
        if (i < 0) return
        val j = max(0, min(cars.size - 1, i + by))
        if (i == j) return
        val list = cars.toMutableList()
        val c = list.removeAt(i)
        list.add(j, c)
        cars = list
        changed()
    }

    // Setups

    /** A car's setups, the last changed first. */
    fun setups(car: String?): List<CarSetup> = setups.filter { it.carID == car }.sortedByDescending { it.updated }
    fun setup(id: String?): CarSetup? = id?.let { i -> setups.firstOrNull { it.id == i } }

    /** A new setup, or a change to one: when its values change, the ones it had are kept as a revision first. */
    fun save(setup: CarSetup) {
        val i = setups.indexOfFirst { it.id == setup.id }
        val list = setups.toMutableList()
        if (i >= 0) {
            val old = list[i]
            var s = setup.copy(history = old.history)
            if (old.values != s.values) {
                s = s.copy(history = listOf(SetupRevision(date = nowSeconds(), version = old.version, values = old.values)) + old.history, updated = nowSeconds())
            } else if (old.name != s.name || old.weather != s.weather || old.track != s.track) {
                s = s.copy(updated = nowSeconds())
            }
            list[i] = s
        } else {
            list.add(0, setup.copy(created = nowSeconds(), updated = nowSeconds()))
        }
        setups = list
        Files.write(setups, setupList, setupsFile)
    }

    /** A copy to start another setup from, with no history of its own. */
    fun duplicate(id: String): CarSetup? {
        val s = setup(id) ?: return null
        val copy = s.copy(id = newID(), name = L("%@ (copia)", s.displayName), history = emptyList())
        save(copy)
        return setup(copy.id)
    }

    fun deleteSetup(id: String) {
        setups = setups.filter { it.id != id }
        Files.write(setups, setupList, setupsFile)
    }

    /** A setup from a file, for one of your cars: a new setup, its history included. */
    fun importSetup(shared: SharedSetup, car: String): CarSetup {
        val s = shared.setup.copy(id = newID(), carID = car)
        setups = listOf(s) + setups
        Files.write(setups, setupList, setupsFile)
        return s
    }

    // Photos

    /** A picked photo, made smaller and stored as a JPEG: its new id. */
    suspend fun storePhoto(uri: Uri): String? = withContext(Dispatchers.IO) {
        val bitmap = runCatching { decode(uri) }.getOrNull() ?: return@withContext null
        val data = jpeg(bitmap)
        val id = newID()
        runCatching { file(id).writeBytes(data) }.getOrNull() ?: return@withContext null
        id
    }

    fun image(photo: String?): Bitmap? {
        photo ?: return null
        cache.get(photo)?.let { return it }
        val f = file(photo)
        if (!f.exists()) return null
        val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
        val b = BitmapFactory.decodeFile(f.path, opts) ?: return null
        cache.put(photo, b)
        return b
    }

    /** A photo nobody uses any more (the editor was cancelled, the car changed photo). */
    fun discardPhoto(photo: String) {
        if (cars.any { it.photo == photo }) return
        file(photo).delete()
        cache.remove(photo)
    }

    private fun file(photo: String) = File(dir, "$photo.jpg")

    /** Photos left behind by an editor closed in the middle: deleted at launch. */
    private fun sweep() {
        val used = cars.mapNotNull { it.photo }.toSet()
        dir.listFiles()?.forEach { f -> if (f.extension == "jpg" && f.nameWithoutExtension !in used) f.delete() }
    }

    private fun decode(uri: Uri): Bitmap? {
        if (Build.VERSION.SDK_INT >= 28) {
            val src = ImageDecoder.createSource(context.contentResolver, uri)
            return ImageDecoder.decodeBitmap(src) { d, info, _ ->
                val side = max(info.size.width, info.size.height)
                if (side > PHOTO_SIDE) {
                    val k = PHOTO_SIDE.toDouble() / side
                    d.setTargetSize((info.size.width * k).roundToInt(), (info.size.height * k).roundToInt())
                }
                d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        }
        return context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
    }

    /** At most 1600 pixels on the longest side, as a JPEG small enough for the server. */
    private fun jpeg(source: Bitmap): ByteArray {
        val side = max(source.width, source.height)
        val b = if (side > PHOTO_SIDE) {
            val k = PHOTO_SIDE.toDouble() / side
            Bitmap.createScaledBitmap(source, (source.width * k).roundToInt(), (source.height * k).roundToInt(), true)
        } else source
        var quality = 80
        while (quality > 30) {
            val out = ByteArrayOutputStream()
            b.compress(Bitmap.CompressFormat.JPEG, quality, out)
            if (out.size() <= MAX_PHOTO_BYTES) return out.toByteArray()
            quality -= 15
        }
        return ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, 30, it) }.toByteArray()
    }

    // Publishing

    fun updatePublic(on: Boolean) {
        isPublic = on
        prefs.edit().putBoolean("garagePublic", on).apply()
        publishSoon(now = true)
    }

    /** After signing in or out: a garage shown from this phone goes up under the new account. */
    fun accountChanged() {
        sync = Sync.Idle
        publishSoon(now = true)
    }

    private fun changed() {
        Files.write(cars, carList, indexFile)
        publishSoon()
    }

    /** Changes come in bursts: one upload a moment after the last. */
    fun publishSoon(now: Boolean = false) {
        pending?.cancel()
        pending = scope.launch {
            if (!now) delay(1500)
            publish()
        }
    }

    /** Public: the cars and then the missing photos. Private again: the garage is emptied on the server. */
    suspend fun publish() {
        val account = account
        val token = account?.token
        if (account == null || !account.isSignedIn || token == null) {
            sync = Sync.Idle
            return
        }
        if (!isPublic && account.garage == null) {
            sync = Sync.Idle
            return
        }
        sync = Sync.Syncing
        try {
            val code = account.garageCode()
            val shown = if (isPublic) cars.map { it.published } else emptyList()
            val missing = Server.putGarage(code, shown, token)
            for (photo in missing) {
                val data = withContext(Dispatchers.IO) { file(photo).takeIf { it.exists() }?.readBytes() } ?: continue
                Server.putPhoto(code, photo, data, token)
            }
            sync = Sync.Done(nowSeconds())
        } catch (e: ServerFailure) {
            if (e.kind == ServerFailure.Kind.signedOut) account.signedOutElsewhere()
            sync = Sync.Failed(e.message)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            sync = Sync.Failed(e.message ?: L("Il server ha rifiutato la richiesta."))
        }
    }

    companion object {
        const val PHOTO_SIDE = 1600
        const val MAX_PHOTO_BYTES = 1_400_000
    }
}
