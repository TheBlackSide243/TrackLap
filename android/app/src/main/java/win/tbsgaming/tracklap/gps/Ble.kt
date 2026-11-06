package win.tbsgaming.tracklap.gps

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.timing.GPoint
import win.tbsgaming.tracklap.timing.Sample
import win.tbsgaming.tracklap.ui.L
import java.io.ByteArrayOutputStream
import java.util.UUID
import kotlin.math.floor
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/** The TrackLap BLE service of the ESP32 (protocol v1, see README). */
object TrackLapBle {
    val service: UUID = UUID.fromString("7A1C0000-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    val fix: UUID = UUID.fromString("7A1C0001-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    val lap: UUID = UUID.fromString("7A1C0002-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    val track: UUID = UUID.fromString("7A1C0003-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    val control: UUID = UUID.fromString("7A1C0004-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    val info: UUID = UUID.fromString("7A1C0005-3F4B-4C8E-9D2A-6B1E5F0A9C10")
    val cccd: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
}

@Serializable
data class DeviceInfo(
    val fw: String? = null,
    val chip: String? = null,
    /** Empty while no GPS module answers. */
    val gps: String? = null,
    val hz: Int? = null,
    /** The GPIOs the GPS is wired to. */
    val rx: Int? = null,
    val tx: Int? = null,
    val name: String? = null,
    /** The board's accelerometer ("QMI8658"), empty or null without one. */
    val imu: String? = null,
)

data class FoundDevice(val address: String, val name: String, val rssi: Int)

/** Little-endian packets of protocol v1. */
object BlePacket {
    data class Fix(
        val valid: Boolean, val sats: Int, val rate: Int, val itow: Double,
        val lat: Double, val lon: Double, val speed: Double, val heading: Double, val alt: Double?,
        /** From the board's accelerometer, in g: lateral (+ right) and longitudinal (+ accelerating). */
        val g: GPoint? = null,
    )

    private fun u16(b: ByteArray, i: Int) = (b[i].toInt() and 0xFF) or ((b[i + 1].toInt() and 0xFF) shl 8)
    private fun u32(b: ByteArray, i: Int): Long = (u16(b, i).toLong()) or (u16(b, i + 2).toLong() shl 16)
    private fun i32(b: ByteArray, i: Int): Int = u32(b, i).toInt()

    /**
     * 20 bytes: version, flags, sats, rate Hz, iTOW ms (u32), lat/lon 1e-7° (i32), speed cm/s (u16),
     * heading 0.01° (u16); from firmware 0.7.0 then the altitude in mm (i32, INT32_MIN for none); from
     * 0.9.2 the accelerometer's lateral and longitudinal g in milli-g (i16 each, INT16_MIN for none).
     */
    fun fix(b: ByteArray): Fix? {
        if (b.size < 20) return null
        val alt = if (b.size >= 24 && i32(b, 20) != Int.MIN_VALUE) i32(b, 20) / 1000.0 else null
        return Fix(
            valid = (b[1].toInt() and 1) == 1, sats = b[2].toInt() and 0xFF, rate = b[3].toInt() and 0xFF,
            itow = u32(b, 4) / 1000.0, lat = i32(b, 8) * 1e-7, lon = i32(b, 12) * 1e-7,
            speed = u16(b, 16) / 100.0, heading = u16(b, 18) / 100.0, alt = alt, g = g(b),
        )
    }

    private fun g(b: ByteArray): GPoint? {
        if (b.size < 28) return null
        val lateral = u16(b, 24).toShort().toInt()
        val longitudinal = u16(b, 26).toShort().toInt()
        if (lateral == Short.MIN_VALUE.toInt() || longitudinal == Short.MIN_VALUE.toInt()) return null
        return GPoint(lateral / 1000.0, longitudinal / 1000.0)
    }

    /** The fix's UTC time: iTOW counts from the start of the GPS week, GPS time runs 18 s ahead of UTC. */
    fun utc(itow: Double, now: Double = System.currentTimeMillis() / 1000.0): Double {
        val epoch = 315_964_800.0
        val leap = 18.0
        val week = 604_800.0
        val gpsNow = now - epoch + leap
        var start = floor(gpsNow / week) * week
        val into = gpsNow - start
        if (itow - into > week / 2) start -= week else if (into - itow > week / 2) start += week
        return epoch + start + itow - leap
    }

    /** version 1, gate count, then each gate as latA, lonA, latB, lonB (i32, 1e-7°); the start line first. */
    fun track(t: Track): ByteArray? {
        val start = t.start ?: return null
        val gates = listOf(start) + t.sectors
        val out = ByteArrayOutputStream()
        out.write(1)
        out.write(gates.size)
        fun put(deg: Double) = out.le32((deg * 1e7).roundToLong().toInt())
        for (g in gates) {
            put(g.a.lat); put(g.a.lon); put(g.b.lat); put(g.b.lon)
        }
        return out.toByteArray()
    }
}

fun ByteArrayOutputStream.le32(v: Int) {
    write(v and 0xFF); write((v shr 8) and 0xFF); write((v shr 16) and 0xFF); write((v shr 24) and 0xFF)
}

private fun clampU32(v: Double): Int = v.coerceIn(0.0, 4_294_967_295.0).toLong().toInt()

/** The ESP32 over Bluetooth LE: scanning, the connection that comes back by itself, fixes and commands. */
@SuppressLint("MissingPermission")
class BleManager(private val context: Context) {
    enum class State { off, unauthorized, unsupported, idle, scanning, connecting, connected }

    var state by mutableStateOf(State.idle); private set
    var devices by mutableStateOf<List<FoundDevice>>(emptyList()); private set
    var connectedName by mutableStateOf<String?>(null); private set
    var info by mutableStateOf<DeviceInfo?>(null); private set
    var sats by mutableStateOf(0); private set
    var rateHz by mutableStateOf(0); private set
    var hasFix by mutableStateOf(false); private set
    var deviceLapTime by mutableStateOf<Double?>(null); private set
    var onSample: ((Sample) -> Unit)? = null
    var onConnected: (() -> Unit)? = null

    private val main = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter? = (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    private val prefs = context.getSharedPreferences("tracklap", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }
    private var gatt: BluetoothGatt? = null
    private val chars = HashMap<UUID, BluetoothGattCharacteristic>()
    private var pendingTrack: ByteArray? = null
    private var keepConnected = false
    private var active = false
    private var weekOffset = 0.0
    private var lastITOW: Double? = null
    private val ops = ArrayDeque<() -> Boolean>()
    private var busy = false

    val stateTitle: String
        get() = when (state) {
            State.off -> L("Bluetooth spento")
            State.unauthorized -> L("Bluetooth non autorizzato")
            State.unsupported -> L("Bluetooth non disponibile")
            State.idle -> L("Nessun dispositivo collegato")
            State.scanning -> L("Ricerca in corso…")
            State.connecting -> L("Collegamento a %@…", connectedName ?: "TrackLap")
            State.connected -> connectedName ?: "TrackLap"
        }

    val stateDetail: String
        get() = when (state) {
            State.off -> L("Accendilo dal Centro di Controllo.")
            State.unauthorized -> L("Consentilo in Impostazioni → TrackLap → Bluetooth.")
            State.unsupported -> L("Questo dispositivo non supporta il Bluetooth LE.")
            State.idle -> L("Accendi l'ESP32 e tocca Cerca.")
            State.scanning -> L("Tieni l'ESP32 acceso e vicino.")
            State.connecting -> L("Si ricollega da solo quando torna a portata.")
            State.connected -> if (hasFix) L("GPS agganciato") else L("In attesa del fix GPS")
        }

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (!active) return
            when (i.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_ON -> { state = State.idle; reconnectLast() }
                BluetoothAdapter.STATE_OFF -> { dropConnection(); state = State.off }
            }
        }
    }

    init {
        ContextCompat.registerReceiver(context, stateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED), ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    /** The permissions a scan and a connection need on this Android version. */
    fun permissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= 31) arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    fun hasPermission(): Boolean = permissions().all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }

    // Commands

    fun activate() {
        active = true
        when {
            adapter == null -> state = State.unsupported
            !hasPermission() -> state = State.unauthorized
            !adapter.isEnabled -> state = State.off
            else -> {
                if (state == State.unauthorized || state == State.off || state == State.unsupported) state = State.idle
                if (gatt == null) reconnectLast()
            }
        }
    }

    fun deactivate() {
        active = false
        keepConnected = false
        stopScan()
        dropConnection()
        if (state != State.off && state != State.unsupported && state != State.unauthorized) state = State.idle
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.scanRecord?.deviceName ?: result.device.name ?: "TrackLap"
            val d = FoundDevice(result.device.address, name, result.rssi)
            main.post {
                val list = devices.toMutableList()
                val i = list.indexOfFirst { it.address == d.address }
                if (i >= 0) list[i] = d else list.add(d)
                devices = list
            }
        }
    }

    private val stopScanLater = Runnable { stopScan() }

    fun scan() {
        activate()
        val a = adapter ?: return
        if (!hasPermission() || !a.isEnabled) return
        val scanner = a.bluetoothLeScanner ?: return
        devices = emptyList()
        state = State.scanning
        val filters = listOf(ScanFilter.Builder().setServiceUuid(ParcelUuid(TrackLapBle.service)).build())
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        runCatching { scanner.startScan(filters, settings, scanCallback) }
        main.removeCallbacks(stopScanLater)
        main.postDelayed(stopScanLater, 15_000)
    }

    fun stopScan() {
        main.removeCallbacks(stopScanLater)
        if (hasPermission()) runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        if (state == State.scanning) state = State.idle
    }

    fun connect(d: FoundDevice) {
        stopScan()
        val device = runCatching { adapter?.getRemoteDevice(d.address) }.getOrNull() ?: return
        keepConnected = true
        connectedName = d.name
        open(device, auto = false)
    }

    fun disconnect() {
        prefs.edit().remove(LAST_DEVICE).apply()
        keepConnected = false
        dropConnection()
        state = State.idle
    }

    fun sendTrack(track: Track) {
        pendingTrack = BlePacket.track(track) ?: return
        flushTrack()
    }

    fun resetDeviceSession() = write(byteArrayOf(0x01), TrackLapBle.control)

    /** Moves the GPS to other GPIOs (null = the chip's defaults); the ESP32 restarts and reconnects. */
    fun setGpsPins(rx: Int?, tx: Int?) {
        val d = byteArrayOf(0x02, 0xFF.toByte(), 0xFF.toByte())
        if (rx != null && tx != null) {
            d[1] = rx.coerceIn(0, 255).toByte()
            d[2] = tx.coerceIn(0, 255).toByte()
        }
        write(d, TrackLapBle.control)
    }

    /** A friend's lap for the ESP32 to compare with at every line; null puts the ESP32's own best back. */
    fun setRival(time: Double?, splits: List<Double>) {
        val out = ByteArrayOutputStream()
        out.write(0x03)
        if (time != null) {
            out.write(splits.size + 1)
            for (v in listOf(time) + splits) out.le32(clampU32(v * 1000))
        }
        write(out.toByteArray(), TrackLapBle.control)
    }

    /** Your place in the live group for the ESP32's screen: position 0 for none, the gap in seconds to the one ahead. */
    fun setGroup(position: Int, count: Int, gap: Double?) {
        val out = ByteArrayOutputStream()
        out.write(0x04); out.write(position.coerceIn(0, 255)); out.write(count.coerceIn(0, 255))
        out.le32(gap?.let { (it * 1000).roundToInt().coerceIn(Int.MIN_VALUE + 1, Int.MAX_VALUE - 1) } ?: Int.MAX_VALUE)
        write(out.toByteArray(), TrackLapBle.control)
    }

    /** The drag dashboard: null puts the lap one back; otherwise 0 waiting for a stop, 1 ready, 2 a run in progress. */
    fun setDrag(state: Int?, elapsed: Double = 0.0) {
        if (state == null) {
            write(byteArrayOf(0x05, 0x00), TrackLapBle.control)
            return
        }
        val out = ByteArrayOutputStream()
        out.write(0x05); out.write(0x01); out.write(state)
        out.le32(clampU32(elapsed * 1000))
        write(out.toByteArray(), TrackLapBle.control)
    }

    /** A drag result for the dashboard, shown for 5 s: a time, or a distance (braking), purple for a best. */
    fun showDrag(label: String, time: Double?, distance: Double?, best: Boolean) {
        val out = ByteArrayOutputStream()
        out.write(0x05); out.write(0x02)
        out.write((if (best) 1 else 0) or (if (distance != null) 2 else 0))
        val value = distance?.let { it * 100 } ?: ((time ?: 0.0) * 1000)
        out.le32(clampU32(value.roundToInt().toDouble()))
        out.write(label.toByteArray(Charsets.UTF_8).take(12).toByteArray())
        write(out.toByteArray(), TrackLapBle.control)
    }

    private fun flushTrack() {
        val data = pendingTrack ?: return
        if (state != State.connected || chars[TrackLapBle.track] == null) return
        write(data, TrackLapBle.track)
        pendingTrack = null
    }

    @Suppress("DEPRECATION")
    private fun write(data: ByteArray, uuid: UUID) {
        enqueue {
            val g = gatt
            val c = chars[uuid]
            if (g == null || c == null) false
            else if (Build.VERSION.SDK_INT >= 33) {
                g.writeCharacteristic(c, data, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == 0
            } else {
                c.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                c.value = data
                g.writeCharacteristic(c)
            }
        }
    }

    // The GATT queue: Android runs one operation at a time.

    private fun enqueue(op: () -> Boolean) {
        main.post {
            ops.addLast(op)
            if (!busy) next()
        }
    }

    private fun next() {
        while (ops.isNotEmpty()) {
            val op = ops.removeFirst()
            if (runCatching { op() }.getOrDefault(false)) {
                busy = true
                return
            }
        }
        busy = false
    }

    private fun done() = main.post { busy = false; next() }

    private fun open(device: BluetoothDevice, auto: Boolean) {
        dropConnection()
        state = State.connecting
        gatt = device.connectGatt(context, auto, callback, BluetoothDevice.TRANSPORT_LE)
    }

    private fun dropConnection() {
        runCatching { gatt?.disconnect(); gatt?.close() }
        gatt = null
        chars.clear()
        ops.clear()
        busy = false
        resetStatus()
    }

    private fun reconnectLast() {
        val a = adapter ?: return
        if (!hasPermission() || !a.isEnabled) return
        val address = prefs.getString(LAST_DEVICE, null) ?: return
        val device = runCatching { a.getRemoteDevice(address) }.getOrNull() ?: return
        keepConnected = true
        connectedName = prefs.getString(LAST_NAME, null) ?: "TrackLap"
        // A pending connection with autoConnect never times out: it comes back on its own when in range.
        open(device, auto = true)
    }

    private fun resetStatus() {
        sats = 0
        rateHz = 0
        hasFix = false
        lastITOW = null
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.post {
                if (g != gatt) return@post
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    prefs.edit().putString(LAST_DEVICE, g.device.address).putString(LAST_NAME, connectedName).apply()
                    if (!g.requestMtu(185)) g.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    chars.clear()
                    ops.clear()
                    busy = false
                    resetStatus()
                    if (keepConnected && active) {
                        val device = g.device
                        runCatching { g.close() }
                        gatt = null
                        open(device, auto = true)
                    } else {
                        state = State.idle
                    }
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            main.post { if (g == gatt) g.discoverServices() }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                if (g != gatt) return@post
                val service = g.getService(TrackLapBle.service) ?: return@post
                for (c in service.characteristics) chars[c.uuid] = c
                for (uuid in listOf(TrackLapBle.fix, TrackLapBle.lap, TrackLapBle.info)) {
                    val c = chars[uuid] ?: continue
                    if (uuid == TrackLapBle.info) enqueue { g.readCharacteristic(c) }
                    if (c.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0) subscribe(g, c)
                }
                state = State.connected
                connectedName = g.device.name ?: connectedName
                onConnected?.invoke()
                flushTrack()
            }
        }

        @Suppress("DEPRECATION")
        private fun subscribe(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            g.setCharacteristicNotification(c, true)
            val d = c.getDescriptor(TrackLapBle.cccd) ?: return
            enqueue {
                if (Build.VERSION.SDK_INT >= 33) {
                    g.writeDescriptor(d, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == 0
                } else {
                    d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    g.writeDescriptor(d)
                }
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) { done() }
        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) { done() }

        @Deprecated("Deprecated in Java")
        @Suppress("DEPRECATION")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT < 33) {
                val v = c.value
                if (v != null) handle(c.uuid, v)
                done()
            }
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            handle(c.uuid, value)
            done()
        }

        @Deprecated("Deprecated in Java")
        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT < 33) c.value?.let { handle(c.uuid, it.copyOf()) }
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            handle(c.uuid, value)
        }
    }

    private fun handle(uuid: UUID, data: ByteArray) {
        main.post {
            when (uuid) {
                TrackLapBle.fix -> handleFix(data)
                TrackLapBle.lap -> handleLap(data)
                TrackLapBle.info -> handleInfo(data)
            }
        }
    }

    private var infoReread = false

    private fun handleInfo(data: ByteArray) {
        val parsed = runCatching { json.decodeFromString(DeviceInfo.serializer(), data.toString(Charsets.UTF_8)) }.getOrNull()
        if (parsed != null) {
            info = parsed
            infoReread = false
        } else if (!infoReread) {
            // A notification longer than the connection's MTU arrives cut: read it whole.
            infoReread = true
            val g = gatt
            val c = chars[TrackLapBle.info]
            if (g != null && c != null) enqueue { g.readCharacteristic(c) }
        }
    }

    private fun handleFix(data: ByteArray) {
        val fix = BlePacket.fix(data) ?: return
        sats = fix.sats
        rateHz = fix.rate
        hasFix = fix.valid
        if (!fix.valid) return
        // iTOW restarts every Sunday at midnight GPS time.
        val last = lastITOW
        if (last != null && fix.itow < last - 302_400) weekOffset += 604_800.0
        lastITOW = fix.itow
        onSample?.invoke(
            Sample(weekOffset + fix.itow, Coord(fix.lat, fix.lon), fix.speed, fix.heading, utc = BlePacket.utc(fix.itow), alt = fix.alt, g = fix.g),
        )
    }

    /** version, kind (1 = lap), lap number (u16), time ms (u32): the lap as timed by the ESP32 itself. */
    private fun handleLap(b: ByteArray) {
        if (b.size < 8 || b[1].toInt() != 1) return
        val ms = (b[4].toLong() and 0xFF) or ((b[5].toLong() and 0xFF) shl 8) or ((b[6].toLong() and 0xFF) shl 16) or ((b[7].toLong() and 0xFF) shl 24)
        deviceLapTime = ms / 1000.0
    }

    companion object {
        private const val LAST_DEVICE = "lastDevice"
        private const val LAST_NAME = "lastDeviceName"
    }
}
