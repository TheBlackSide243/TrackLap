package win.tbsgaming.tracklap

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Smartphone
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.vector.ImageVector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import win.tbsgaming.tracklap.data.AccountStore
import win.tbsgaming.tracklap.data.DragStore
import win.tbsgaming.tracklap.data.DriverProfile
import win.tbsgaming.tracklap.data.Files
import win.tbsgaming.tracklap.data.FriendLap
import win.tbsgaming.tracklap.data.FriendLapStore
import win.tbsgaming.tracklap.data.GarageLink
import win.tbsgaming.tracklap.data.GarageStore
import win.tbsgaming.tracklap.data.LayoutMatch
import win.tbsgaming.tracklap.data.Server
import win.tbsgaming.tracklap.data.SessionStore
import win.tbsgaming.tracklap.data.TrackStore
import win.tbsgaming.tracklap.gps.BleManager
import win.tbsgaming.tracklap.gps.DemoDrag
import win.tbsgaming.tracklap.gps.DemoDriver
import win.tbsgaming.tracklap.gps.PhoneGps
import win.tbsgaming.tracklap.model.Car
import win.tbsgaming.tracklap.model.CarSetup
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.DragMeasure
import win.tbsgaming.tracklap.model.Geo
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.Session
import win.tbsgaming.tracklap.model.SharedLap
import win.tbsgaming.tracklap.model.SharedSetup
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.model.Units
import win.tbsgaming.tracklap.model.nowSeconds
import win.tbsgaming.tracklap.multiplayer.GroupSession
import win.tbsgaming.tracklap.timing.DragEngine
import win.tbsgaming.tracklap.timing.DragEvent
import win.tbsgaming.tracklap.timing.LapEngine
import win.tbsgaming.tracklap.timing.Sample
import win.tbsgaming.tracklap.ui.L
import win.tbsgaming.tracklap.ui.Strings
import java.util.Locale
import kotlin.math.roundToInt

enum class SourceKind {
    device, phone, demo;

    val title: String
        get() = when (this) {
            device -> "ESP32 TrackLap"
            phone -> L("GPS dell'iPhone")
            demo -> "Demo"
        }

    val short: String
        get() = when (this) {
            device -> "ESP32"
            phone -> L("Telefono")
            demo -> "Demo"
        }

    val icon: ImageVector
        get() = when (this) {
            device -> Icons.Filled.Memory
            phone -> Icons.Filled.Smartphone
            demo -> Icons.Filled.PlayCircle
        }

    val detail: String
        get() = when (this) {
            device -> L("Qualsiasi ESP32 con Bluetooth + GPS a 10–25 Hz: tempi precisi al centesimo.")
            phone -> L("Circa 1 Hz: va bene per provare e per segnare la linea a piedi.")
            demo -> L("Un'auto simulata gira sulla pista scelta: prova tutto senza hardware.")
        }

    companion object {
        /** The kind behind the source a session was saved with: its title, in the language of the time. */
        fun ofSession(s: String): SourceKind = if (s.contains("ESP32")) device else if (s == demo.title || s == "Demo") demo else phone
    }
}

enum class AppTab { live, drag, tracks, sessions, garage, device }

/** What the live delta compares with. */
enum class DeltaReference {
    session, record;

    val title: String get() = if (this == session) L("Best sessione") else L("Record pista")
}

/** The state of the whole app: the sources, the timers, the stores, the account and the settings. */
class AppModel(context: Context) {
    private val app = context.applicationContext
    private val prefs = app.getSharedPreferences("tracklap", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    var tab by mutableStateOf(AppTab.live)
    val tracks: TrackStore
    val sessions: SessionStore
    val drags: DragStore
    val friends: FriendLapStore
    val account: AccountStore
    val garage: GarageStore
    val profile: DriverProfile
    val group: GroupSession
    val engine = LapEngine()
    val drag = DragEngine()
    val ble = BleManager(app)
    val phone = PhoneGps(app)
    val demo = DemoDriver()
    val demoDrag = DemoDrag()
    private val voice: LapVoice

    @set:JvmName("assignSource") var source by mutableStateOf(SourceKind.demo); private set
    var selectedTrackID by mutableStateOf<String?>(null); private set
    var isRunning by mutableStateOf(false); private set
    var gpsRate by mutableStateOf(0.0); private set
    var lastFixWall by mutableStateOf<Double?>(null); private set
    @set:JvmName("assignMinLapTime") var minLapTime by mutableStateOf(20.0); private set
    @set:JvmName("assignDeltaScale") var deltaScale by mutableStateOf(2.0); private set
    @set:JvmName("assignUnits") var units by mutableStateOf(Units.metric); private set
    @set:JvmName("assignDeltaReference") var deltaReference by mutableStateOf(DeltaReference.session); private set
    var voiceOn by mutableStateOf(true); private set
    /** The Drag tab is open: the fixes go to the drag timer too. */
    var dragOn by mutableStateOf(false); private set
    @set:JvmName("assignDragRollout") var dragRollout by mutableStateOf(false); private set
    /** Runs from a standstill start with the button (the default); off, by themselves. */
    @set:JvmName("assignDragManualStart") var dragManualStart by mutableStateOf(true); private set
    @set:JvmName("assignIntroSeen") var introSeen by mutableStateOf(true); private set
    /** The friend's lap chased on the selected track. */
    @set:JvmName("assignChallenge") var challenge by mutableStateOf<FriendLap?>(null); private set
    /** The car of your garage you are driving: sessions remember it, your laps on the leaderboards link to it. */
    @set:JvmName("assignActiveCarID") var activeCarID by mutableStateOf<String?>(null); private set
    /** The setup of the active car you drive with: sessions keep it as it was that day. */
    @set:JvmName("assignActiveSetupID") var activeSetupID by mutableStateOf<String?>(null); private set
    /** Someone's public garage opened from a link or a leaderboard. */
    var shownGarage by mutableStateOf<GarageLink?>(null)
    /** A setup file opened from another app, waiting for you to pick its car. */
    var importedSetup by mutableStateOf<SharedSetup?>(null)
    /** What opening a file did, or why it could not. */
    var notice by mutableStateOf<String?>(null)

    private var session: Session? = null
    private val recentT = ArrayList<Double>()
    private var sentPlace: List<Int> = emptyList()

    val selectedTrack: Track? get() = tracks.track(selectedTrackID)
    val canStart: Boolean get() = selectedTrack?.isReady == true
    val activeCar: Car? get() = garage.car(activeCarID)
    val activeSetup: CarSetup? get() = garage.setup(activeSetupID)?.takeIf { it.carID == activeCarID }

    init {
        Files.init(app)
        Strings.init(app)
        units = prefs.getString("units", null)?.let { runCatching { Units.valueOf(it) }.getOrNull() }
            ?: if (Locale.getDefault().country in listOf("US", "GB", "LR", "MM")) Units.imperial else Units.metric
        Units.current = units
        tracks = TrackStore()
        sessions = SessionStore()
        drags = DragStore()
        friends = FriendLapStore()
        account = AccountStore(app)
        garage = GarageStore(app)
        profile = DriverProfile(app)
        group = GroupSession(app, profile)
        voice = LapVoice(app)
        source = prefs.getString("source", null)?.let { runCatching { SourceKind.valueOf(it) }.getOrNull() } ?: SourceKind.demo
        deltaScale = prefs.getFloat("deltaScale", 2f).toDouble()
        minLapTime = prefs.getFloat("minLapTime", 20f).toDouble()
        voiceOn = prefs.getBoolean("voice", true)
        dragRollout = prefs.getBoolean("dragRollout", false)
        dragManualStart = prefs.getBoolean("dragManualStart", true)
        introSeen = prefs.getBoolean("introSeen", false)
        deltaReference = prefs.getString("deltaReference", null)?.let { runCatching { DeltaReference.valueOf(it) }.getOrNull() } ?: DeltaReference.session
        val saved = prefs.getString("track", null)
        selectedTrackID = if (saved != null && tracks.track(saved) != null) saved else tracks.tracks.firstOrNull()?.id
        prefs.getString("activeCar", null)?.let { if (garage.car(it) != null) activeCarID = it }
        prefs.getString("activeSetup", null)?.let { if (garage.setup(it)?.carID == activeCarID) activeSetupID = it }
        garage.account = account
        account.onChange = { accountChanged() }
        engine.minLapTime = minLapTime
        prepareEngine(selectedTrack)

        ble.onSample = { receive(it, SourceKind.device) }
        phone.onSample = { receive(it, SourceKind.phone) }
        demo.onSample = { receive(it, SourceKind.demo) }
        demoDrag.onSample = { receive(it, SourceKind.demo) }
        ble.onConnected = {
            sendDragToDevice()
            selectedTrack?.let {
                ble.sendTrack(it)
                sendChallengeToDevice()
                sendGroupToDevice(force = true)
            }
        }
        drag.onPhase = { sendDragToDevice() }
        drag.onEvent = { dragResult(it) }
        drag.onFinish = { drags.save(it) }
        drag.source = source.name
        engine.onLap = { record(it) }
        group.onStandingsChange = { sendGroupToDevice() }
        group.resume(selectedTrack)
        scope.launch { account.refresh() }
    }

    /** The activity is in front: the source it was left on starts again. */
    fun resume() = activate(source)

    /** The activity went away: the phone's GPS and the scan stop, unless a session is running. */
    fun pause() {
        if (isRunning) return
        if (source == SourceKind.phone) phone.stop()
        ble.stopScan()
    }

    // Source

    fun setSource(k: SourceKind) {
        if (k == source) return
        if (isRunning) stop()
        deactivate(source)
        source = k
        prefs.edit().putString("source", k.name).apply()
        recentT.clear()
        gpsRate = 0.0
        lastFixWall = null
        drag.reset()
        drag.source = k.name
        activate(k)
    }

    private fun activate(k: SourceKind) {
        when (k) {
            SourceKind.device -> ble.activate()
            SourceKind.phone -> phone.start()
            SourceKind.demo -> {}
        }
    }

    private fun deactivate(k: SourceKind) {
        when (k) {
            SourceKind.device -> ble.deactivate()
            SourceKind.phone -> phone.stop()
            SourceKind.demo -> {
                demo.stop()
                demoDrag.stop()
            }
        }
    }

    /** A permission was answered in the system dialog. */
    fun permissionsChanged() {
        phone.permissionChanged()
        if (source == SourceKind.device) ble.activate()
    }

    private fun receive(s: Sample, kind: SourceKind) {
        if (kind != source) return
        lastFixWall = s.wall
        recentT.add(s.t)
        if (recentT.size > 20) recentT.subList(0, recentT.size - 20).clear()
        val f = recentT.first()
        val l = recentT.last()
        if (l > f) gpsRate = (recentT.size - 1) / (l - f)
        if (isRunning) engine.ingest(s) else engine.observe(s)
        if (dragOn && !isRunning) drag.ingest(s)
        if (group.isOn) group.report(s, if (isRunning) engine.lapNumber else 0, engine.lapDistance)
    }

    // Tracks

    fun select(id: String) {
        if (isRunning) stop()
        selectedTrackID = id
        prefs.edit().putString("track", id).apply()
        prepareEngine(selectedTrack)
        selectedTrack?.let { ble.sendTrack(it) }
        sendChallengeToDevice()
        group.setTrack(selectedTrack)
    }

    fun save(t: Track) {
        tracks.upsert(t)
        if (t.id == selectedTrackID && !isRunning) {
            prepareEngine(t)
            ble.sendTrack(t)
            sendChallengeToDevice()
            group.setTrack(t)
        }
    }

    fun deleteTrack(id: String) {
        if (id == selectedTrackID && isRunning) stop()
        tracks.delete(id)
        if (id != selectedTrackID) return
        val first = tracks.tracks.firstOrNull()
        if (first != null) select(first.id) else {
            selectedTrackID = null
            engine.load(null)
        }
    }

    // Session

    fun start() {
        val track = selectedTrack ?: return
        if (!track.isReady) return
        engine.minLapTime = minLapTime
        prepareEngine(track)
        session = Session(
            trackID = track.id, trackName = track.name, date = nowSeconds(), source = source.title, sectorCount = track.sectorCount,
            carID = activeCar?.id, carName = activeCar?.displayName, layout = track.layout?.key, setup = activeSetup?.snapshot,
        )
        isRunning = true
        when (source) {
            SourceKind.demo -> demo.start(track)
            SourceKind.device -> ble.resetDeviceSession()
            SourceKind.phone -> phone.start()
        }
    }

    fun stop() {
        isRunning = false
        if (source == SourceKind.demo) demo.stop()
        session?.let { if (it.laps.isNotEmpty()) sessions.save(it) }
        session = null
    }

    private fun record(lap0: Lap) {
        val lap = layoutSwitch(lap0) ?: lap0
        session = session?.let { it.copy(laps = it.laps + lap) }
        // Saved after every lap, so nothing is lost if the app is closed mid-session.
        session?.let { sessions.save(it) }
        group.finished(lap)
        if (voiceOn) engine.lastEvent?.let { voice.announce(it, if (group.isOn) group.place else null) }
        // The best lap of each session goes to the leaderboard, which keeps it if it is your best there.
        val track = selectedTrack
        val token = account.token
        if (profile.publishLaps && source != SourceKind.demo && engine.lastEvent?.isBest == true && track != null && token != null) {
            val kind = source.name
            val car = session?.carID
            scope.launch { runCatching { Server.submit(lap, kind, track, car, token) } }
        }
    }

    /** Loads the track into the timer with its record from earlier sessions and the friend's lap chased there. */
    private fun prepareEngine(track: Track?) {
        engine.load(track)
        engine.compareWithRecord = deltaReference == DeltaReference.record
        engine.setRecord(sessions.record(track)?.lap)
        applyChallenge(savedChallenge(track))
    }

    /**
     * A lap on another layout of the track: the track takes that layout's lines, the session so far is
     * closed and a new one goes on for this layout. The lap comes back with its sectors on the new lines.
     */
    private fun layoutSwitch(lap: Lap): Lap? {
        val track0 = selectedTrack ?: return null
        val layouts = track0.layouts ?: return null
        if (layouts.size <= 1) return null
        val found = LayoutMatch.best(lap.trace, layouts) ?: return null
        if (found.key == track0.activeLayout) return null
        val track = track0.use(found)
        tracks.upsert(track)
        val moved = lap.copy(sectors = LayoutMatch.sectors(lap, found.sectors))
        val s = session
        if (s != null && s.laps.isNotEmpty()) {
            sessions.save(s)
            session = Session(trackID = track.id, trackName = track.name, date = nowSeconds(), source = s.source,
                sectorCount = track.sectorCount, carID = s.carID, carName = s.carName, layout = found.key, setup = s.setup)
        } else {
            session = s?.copy(layout = found.key, sectorCount = track.sectorCount)
        }
        val record = sessions.record(track)?.lap
        // After the timer has finished with this crossing: it is still inside it now.
        main.post {
            engine.switchLayout(found.start, found.sectors, record, listOf(moved))
            ble.sendTrack(track)
        }
        return moved
    }

    // Files and links

    /** A .tracklap or .tracklapsetup file opened from another app. */
    fun openFile(text: String) {
        when (SharedSetup.kind(text)) {
            "lap" -> runCatching { importLap(SharedLap.decode(text)) }
                .onSuccess { notice = L("1 giro aggiunto."); tab = AppTab.sessions }
                .onFailure { notice = it.message }
            "setup" -> runCatching { SharedSetup.decode(text) }
                .onSuccess { importedSetup = it; tab = AppTab.garage }
                .onFailure { notice = it.message }
            else -> notice = L("Questo file non è un giro di TrackLap.")
        }
    }

    /** tracklap://join/<code> from a group's QR code, tracklap://garage/<code> from a garage page. */
    fun openLink(uri: Uri): Boolean {
        GarageLink.parse(uri)?.let {
            shownGarage = it
            return true
        }
        if (uri.scheme == "tracklap" && uri.host == "join") {
            uri.lastPathSegment?.let { group.join(it, selectedTrack) }
            tab = AppTab.live
            return true
        }
        return false
    }

    /** The lap goes with the friends' laps, on your track with the same start line, or else on the friend's track, added to yours. */
    fun importLap(shared: SharedLap): FriendLap = friends.add(shared, matchingTrack(shared.track) ?: adding(shared.track))

    /** The same circuit among your tracks: the same one, or a start line within 40 m. */
    private fun matchingTrack(t: Track): Track? {
        tracks.track(t.id)?.let { return it }
        val start = t.start ?: return null
        return tracks.tracks.firstOrNull { mine -> mine.start?.let { Geo.distance(it.mid, start.mid) < 40 } ?: false }
    }

    private fun adding(t: Track): Track {
        val copy = t.copy(created = nowSeconds())
        tracks.upsert(copy)
        return copy
    }

    // Friends' laps

    /** Chase a friend's lap: its track is selected (added back if it was deleted), Live opens, and the delta is against their lap. */
    fun chase(f: FriendLap) {
        var lap = f
        if (tracks.track(f.trackID) == null) {
            friends.shared(f.id)?.let { s ->
                val t = matchingTrack(s.track) ?: adding(s.track)
                friends.move(f.id, t)
                lap = f.copy(trackID = t.id, trackName = t.name)
            }
        }
        if (lap.trackID != selectedTrackID) select(lap.trackID)
        setChallenge(lap)
        tab = AppTab.live
    }

    /** The friend's lap to chase on the selected track, null for none. */
    fun setChallenge(f: FriendLap?) {
        val track = selectedTrack ?: return
        val lap = if (f?.trackID == track.id) f else null
        prefs.edit().putString("challenge." + track.id, lap?.id).apply()
        applyChallenge(lap)
    }

    fun deleteFriendLap(id: String) {
        friends.delete(id)
        if (challenge?.id == id) setChallenge(null)
    }

    private fun applyChallenge(f: FriendLap?) {
        val lap = f?.let { friends.lap(it.id) }
        challenge = if (lap == null) null else f
        engine.setGhost(lap, f?.driver)
        sendChallengeToDevice()
    }

    private fun savedChallenge(track: Track?): FriendLap? {
        track ?: return null
        val s = prefs.getString("challenge." + track.id, null) ?: return null
        return friends.laps.firstOrNull { it.id == s && it.trackID == track.id }
    }

    /** The ESP32 compares at every line with the friend's lap too: its time at each of your sector lines. */
    private fun sendChallengeToDevice() {
        val ghost = engine.ghost
        val track = selectedTrack
        if (ghost == null || track == null) {
            ble.setRival(null, emptyList())
            return
        }
        ble.setRival(ghost.time, track.sectors.map { ghost.timeCrossing(it) ?: 0.0 })
    }

    /** Your place in the live group on the ESP32's screen, sent when it changes. */
    private fun sendGroupToDevice(force: Boolean = false) {
        val p = group.place
        val packet = listOf(p?.position ?: 0, p?.count ?: 0, ((p?.gap ?: 0.0) * 1000).roundToInt())
        if (!force && packet == sentPlace) return
        sentPlace = packet
        ble.setGroup(p?.position ?: 0, p?.count ?: 0, p?.gap)
    }

    // Drag

    /** The Drag tab opened or closed: the drag timer starts afresh, with the records to beat, and the ESP32 switches dashboard. */
    fun setDragMode(on: Boolean) {
        if (on == dragOn) return
        dragOn = on
        drag.reset()
        if (on) {
            drag.bests = drags.bests(activeCarID)
            drag.rollout = dragRollout
            drag.needsArming = dragManualStart
            drag.source = source.name
            drag.vehicle = profile.displayVehicle
            drag.carID = activeCarID
            if (drag.run == null) drags.summaries.firstOrNull()?.let { drags.load(it.id) }?.let { drag.show(it) }
        } else {
            demoDrag.stop()
        }
        sendDragToDevice()
    }

    /** A simulated run on a straight road by the selected track, for the Demo. */
    fun startDemoDrag() {
        if (source != SourceKind.demo || !dragOn) return
        // The demo car presses the button for you.
        drag.arm()
        demoDrag.start(selectedTrack?.let { it.start?.mid ?: it.center } ?: Coord(43.9975, 11.3719))
    }

    fun setDragManualStart(on: Boolean) {
        dragManualStart = on
        drag.needsArming = on
        if (!on) drag.disarm()
        prefs.edit().putBoolean("dragManualStart", on).apply()
    }

    fun setDragRollout(on: Boolean) {
        dragRollout = on
        drag.rollout = on
        prefs.edit().putBoolean("dragRollout", on).apply()
    }

    fun deleteDragRun(id: String) {
        drags.delete(id)
        drag.bests = drags.bests(activeCarID)
        if (drag.run?.id == id && !drag.inProgress) {
            drag.show(null)
            drags.summaries.firstOrNull()?.let { drags.load(it.id) }?.let { drag.show(it) }
        }
    }

    /** The voice reads the main measures; the ESP32 shows them for a few seconds. */
    private fun dragResult(e: DragEvent) {
        if (!e.measure.headline) return
        if (voiceOn) voice.announce(e)
        val braking = e.result.kind == DragMeasure.Kind.braking
        ble.showDrag(e.measure.short, if (braking) null else e.result.time, if (braking) e.result.distance else null, e.isBest)
    }

    /** The ESP32's drag dashboard while the Drag tab is open (not during a lap session), the lap one otherwise. */
    private fun sendDragToDevice() {
        if (!dragOn || isRunning) {
            ble.setDrag(null)
            return
        }
        val state = when (drag.phase) {
            DragEngine.Phase.ready -> 1
            DragEngine.Phase.running -> 2
            DragEngine.Phase.moving -> 0
        }
        ble.setDrag(state, drag.startWall?.let { nowSeconds() - it } ?: 0.0)
    }

    // Garage

    /** The car you drive from now on; its name becomes the vehicle the others see. */
    fun setActiveCar(id: String?) {
        val car = garage.car(id)
        if (car?.id != activeCarID) {
            // Another car: the setup it was last driven with, if any.
            val last = sessions.summaries.firstOrNull { it.carID == car?.id && it.setupID != null }?.setupID
            setActiveSetup(if (garage.setup(last)?.carID == car?.id) last else null)
        }
        activeCarID = car?.id
        prefs.edit().putString("activeCar", car?.id).apply()
        if (car != null) {
            profile.setVehicle(car.displayName.take(DriverProfile.MAX))
            group.profileChanged()
        }
        // The Drag tab open: the next run is with this car, and its records are the ones to beat.
        if (dragOn && !drag.inProgress) {
            drag.vehicle = profile.displayVehicle
            drag.carID = car?.id
            drag.bests = drags.bests(car?.id)
        }
    }

    /** The setup you drive with from now on: the next sessions keep it as it is when they start. */
    fun setActiveSetup(id: String?) {
        activeSetupID = garage.setup(id)?.id
        prefs.edit().putString("activeSetup", activeSetupID).apply()
    }

    /** The setup you drive with, and the car it is for. */
    fun drive(setup: CarSetup) {
        setActiveCar(setup.carID)
        setActiveSetup(setup.id)
    }

    fun deleteSetup(id: String) {
        if (id == activeSetupID) setActiveSetup(null)
        garage.deleteSetup(id)
    }

    fun deleteCar(id: String) {
        if (id == activeCarID) setActiveCar(null)
        garage.delete(id)
    }

    /** Signed in or out: the garage follows the account, and your name for the live groups is the account's when you had none. */
    private fun accountChanged() {
        val name = account.name
        if (name != null && !profile.hasName) {
            profile.setName(name.take(DriverProfile.MAX))
            group.profileChanged()
        }
        garage.accountChanged()
    }

    // Settings

    fun setUnits(u: Units) {
        units = u
        Units.current = u
        prefs.edit().putString("units", u.name).apply()
    }

    fun setDeltaReference(r: DeltaReference) {
        deltaReference = r
        engine.compareWithRecord = r == DeltaReference.record
        prefs.edit().putString("deltaReference", r.name).apply()
    }

    fun setVoice(on: Boolean) {
        voiceOn = on
        prefs.edit().putBoolean("voice", on).apply()
    }

    fun setMinLapTime(v: Double) {
        minLapTime = v
        engine.minLapTime = v
        prefs.edit().putFloat("minLapTime", v.toFloat()).apply()
    }

    fun setDeltaScale(v: Double) {
        deltaScale = v
        prefs.edit().putFloat("deltaScale", v.toFloat()).apply()
    }

    fun setIntroSeen(seen: Boolean) {
        introSeen = seen
        prefs.edit().putBoolean("introSeen", seen).apply()
    }
}
