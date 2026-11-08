package win.tbsgaming.tracklap.ui

import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import win.tbsgaming.tracklap.data.TrackWeather
import win.tbsgaming.tracklap.model.SetupWeather
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.FiberManualRecord
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.SportsScore
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.Edition
import win.tbsgaming.tracklap.timing.leanAngle
import kotlin.math.roundToInt
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.SourceKind
import win.tbsgaming.tracklap.gps.BleManager
import win.tbsgaming.tracklap.model.nowSeconds
import win.tbsgaming.tracklap.timing.LapEvent
import win.tbsgaming.tracklap.timing.LiveSector
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

@Composable
fun LiveScreen() {
    val m = LocalModel.current
    val view = LocalView.current
    var banner by remember { mutableStateOf<LapEvent?>(null) }
    val event = m.engine.lastEvent
    LaunchedEffect(event?.id) {
        if (event == null) return@LaunchedEffect
        haptic(view, event.isBest)
        banner = event
        delay(4000)
        if (banner?.id == event.id) banner = null
    }
    val ready = m.selectedTrack?.isReady == true
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth > maxHeight
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            LiveHeader()
            WeatherHint()
            if (!ready) {
                NoTrackCard()
            } else if (wide) {
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        LapTimerCard()
                        DeltaCard()
                        SectorRow()
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        LiveStatsRow()
                        MiniMapCard(150)
                        SessionButton()
                        if (Edition.online) MultiplayerCard()
                    }
                }
            } else {
                LapTimerCard()
                DeltaCard()
                SectorRow()
                LiveStatsRow()
                MiniMapCard(210)
                SessionButton()
                if (Edition.online) MultiplayerCard()
            }
        }
        AnimatedVisibility(
            banner != null, enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut(),
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        ) {
            banner?.let { LapBanner(it) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun LiveHeader() {
    val m = LocalModel.current
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ScreenHeader(Icons.Filled.SportsScore, "TrackLap", m.selectedTrack?.titleWithLayout ?: L("Nessuna pista")) {
            if (m.isRunning) RecordingBadge()
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            GpsPill()
            StatusPill(m.source.icon, m.source.short)
            m.group.place?.let { StatusPill(Icons.Filled.Groups, "P${it.position}/${it.count}", Theme.yellow) }
            if (Edition.online) {
                ActiveCarChip()
                ActiveSetupChip()
            }
        }
    }
}

@Composable
private fun RecordingBadge() {
    val pulse by produceState(1f) {
        var on = true
        while (true) {
            delay(700)
            on = !on
            value = if (on) 1f else 0.45f
        }
    }
    Row(
        Modifier.clip(CircleShape).background(Theme.bad.copy(alpha = 0.14f)).padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(Icons.Filled.FiberManualRecord, null, tint = Theme.bad.copy(alpha = pulse), modifier = Modifier.size(14.dp))
        Text("REC", fontSize = 12.sp, fontWeight = FontWeight.Black, color = Theme.bad)
    }
}

/** The GPS: its rate and, from the ESP32, the satellites; red when no fix came for a while. */
@Composable
fun GpsPill() {
    val m = LocalModel.current
    val now by produceState(nowSeconds()) {
        while (true) {
            delay(1000)
            value = nowSeconds()
        }
    }
    val age = m.lastFixWall?.let { now - it } ?: Double.POSITIVE_INFINITY
    val ok = age < 2.5
    val sats = if (m.source == SourceKind.device && m.ble.sats > 0) " · ${m.ble.sats} sat" else ""
    StatusPill(
        Icons.Filled.LocationOn,
        if (ok) "GPS ${Fmt.hz(m.gpsRate)}$sats" else L("GPS assente"),
        if (ok) (if (m.gpsRate >= 5) Theme.good else Theme.yellow) else Theme.bad,
    )
}

/** Seconds since 1970 now, ticking every frame while `running`. */
@Composable
fun frameClock(running: Boolean): Double {
    val clock by produceState(nowSeconds(), running) {
        value = nowSeconds()
        while (running) {
            withFrameMillis { }
            value = nowSeconds()
        }
    }
    return clock
}

@Composable
private fun LapTimerCard() {
    val m = LocalModel.current
    val e = m.engine
    val now = frameClock(m.isRunning && e.isTiming)
    val elapsed = if (m.isRunning) e.lapStartWall?.let { max(0.0, now - it) } ?: 0.0 else 0.0
    Panel(padding = 20.dp, glow = if (m.isRunning) Theme.accent else null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            val label = if (!m.isRunning) L("PRONTO") else if (e.lapNumber == 0) L("GIRO DI LANCIO") else L("GIRO %lld", e.lapNumber)
            Text(label, fontSize = 13.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp, color = Theme.accent)
            Spacer(Modifier.weight(1f))
            e.predicted?.let { Text(L("PREVISTO  %@", Fmt.lap(it)), style = Theme.numStyle(12.sp), color = Theme.sub) }
        }
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            // As big as fits: eight characters of a lap time.
            val size = min(80f, maxWidth.value / 4.6f)
            BigText(Fmt.lap(elapsed), size.sp, if (m.isRunning) Theme.text else Theme.sub)
        }
    }
}

@Composable
private fun DeltaCard() {
    val m = LocalModel.current
    val e = m.engine
    val d = e.delta
    val color = d?.let { if (it <= 0) Theme.good else Theme.bad } ?: Theme.sub
    Panel(glow = if (d == null) null else color) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("DELTA", fontSize = 13.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp, color = Theme.sub)
                    val ghost = e.ghost
                    val caption = when {
                        ghost != null -> L("sul giro di %@ (%@)", e.ghostName ?: "", Fmt.lap(ghost.time))
                        e.comparesWithRecord -> L("sul record della pista (%@)", Fmt.lap(e.referenceLap?.time))
                        d == null -> L("Completa un giro per il confronto")
                        else -> L("sul tuo giro migliore")
                    }
                    Text(caption, fontSize = 12.sp, color = Theme.sub.copy(alpha = 0.8f))
                }
                BigText(Fmt.delta(d), 46.sp, color)
            }
            DeltaBar(d, m.deltaScale)
            ChallengeMenu()
        }
    }
}

/** The friend's lap to chase, picked from the laps friends sent for this track. */
@Composable
private fun ChallengeMenu() {
    val m = LocalModel.current
    val laps = if (Edition.online) m.friends.laps(m.selectedTrackID) else emptyList()
    if (laps.isEmpty()) return
    var open by remember { mutableStateOf(false) }
    val c = m.challenge
    Box {
        Row(
            Modifier.clip(CircleShape).background(if (c == null) Theme.input else Theme.yellow.copy(alpha = 0.14f)).clickable { open = true }
                .padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.Filled.Flag, null, tint = if (c == null) Theme.sub else Theme.yellow, modifier = Modifier.size(14.dp))
            Text(c?.let { L("Sfida: %@", it.driver) } ?: L("Sfida un amico"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = if (c == null) Theme.sub else Theme.yellow)
        }
        DropdownMenu(open, { open = false }, containerColor = Theme.panel) {
            DropdownMenuItem({ Text(L("Nessuna sfida"), color = Theme.text) }, { open = false; m.setChallenge(null) })
            for (f in laps) DropdownMenuItem({ Text(f.title, color = if (f.id == c?.id) Theme.yellow else Theme.text) }, { open = false; m.setChallenge(f) })
        }
    }
}

/** Rain at the track and a setup for the wet in your garage (or sun and one for the dry): Live offers to switch before the session starts. */
@Composable
private fun WeatherHint() {
    val m = LocalModel.current
    val t = m.selectedTrack
    val now by produceState<TrackWeather.Now?>(null, t?.id) {
        value = if (t == null || t.isDemo) null else TrackWeather.now(t.start?.mid ?: t.center)
    }
    var dismissed by remember { mutableStateOf<String?>(null) }
    val n = now ?: return
    val car = m.activeCar ?: return
    if (m.isRunning) return
    val wanted = if (n.wet) SetupWeather.wet else SetupWeather.dry
    if (m.activeSetup?.weather == wanted) return
    val list = m.garage.setups(car.id).filter { it.weather == wanted }
    val name = t?.name ?: ""
    val setup = list.firstOrNull { it.track.isNotEmpty() && name.contains(it.track, ignoreCase = true) } ?: list.firstOrNull() ?: return
    if (dismissed == setup.id + wanted.name) return
    Panel(padding = 14.dp, glow = if (wanted == SetupWeather.wet) Theme.blue else Theme.yellow) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            WeatherGlyph(wanted, 36.dp)
            Column(Modifier.weight(1f)) {
                val temp = n.temperature?.let { " · " + Math.round(it) + "°" } ?: ""
                Text((if (n.wet) L("Piove a %@", name) else L("Asciutto a %@", name)) + temp, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                Text(L("Usare l'assetto %@?", setup.displayName), fontSize = 12.sp, color = Theme.sub, maxLines = 2)
            }
            Text(L("Usa"), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.Black,
                modifier = Modifier.clip(CircleShape).background(Theme.accent).clickable { m.setActiveSetup(setup.id) }.padding(horizontal = 14.dp, vertical = 8.dp))
            Icon(Icons.Filled.Close, L("Chiudi"), tint = Theme.sub, modifier = Modifier.size(18.dp).clickable { dismissed = setup.id + wanted.name })
        }
    }
}

/** Zero in the middle: green grows to the left when faster, red to the right when slower. */
@Composable
fun DeltaBar(delta: Double?, scale: Double) {
    val v by animateFloatAsState(max(-1.0, min(1.0, (delta ?: 0.0) / scale)).toFloat(), label = "delta")
    val color = if (v <= 0) Theme.good else Theme.bad
    BoxWithConstraints(Modifier.fillMaxWidth().height(14.dp).clip(CircleShape).background(Theme.input)) {
        val half = maxWidth / 2
        val w = half * abs(v)
        Box(
            Modifier.padding(start = if (v <= 0) half - w else half).size(w, 14.dp)
                .shadow(6.dp, CircleShape, ambientColor = color, spotColor = color).clip(CircleShape).background(color),
        )
        Box(Modifier.padding(start = half - 1.dp).size(2.dp, 14.dp).background(Theme.text.copy(alpha = 0.7f)))
    }
}

@Composable
private fun SectorRow() {
    val sectors = LocalModel.current.engine.sectors
    if (sectors.isEmpty()) return
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        for (s in sectors) SectorChip(s, Modifier.weight(1f))
    }
}

@Composable
private fun SectorChip(sector: LiveSector, modifier: Modifier) {
    val live = sector.time != null
    val state = if (live) sector.state else sector.previousState
    val value = sector.time ?: sector.previous
    val color = state?.let { Theme.color(it) } ?: Theme.sub
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier.clip(shape).background(color.copy(alpha = if (live) 0.2f else 0.06f))
            .border(1.5.dp, color.copy(alpha = if (live) 0.9f else 0.25f), shape).padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text("S${sector.id + 1}", fontSize = 11.sp, fontWeight = FontWeight.Black, color = if (live) color else Theme.sub)
        Text(value?.let { Fmt.sector(it) } ?: "—", style = Theme.numStyle(18.sp, color = if (live) Theme.text else Theme.sub.copy(alpha = 0.8f)))
    }
}

@Composable
private fun LiveStatsRow() {
    val m = LocalModel.current
    val e = m.engine
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        StatTile(L("Ultimo"), Fmt.lap(e.lastLap?.time), Modifier.weight(1f))
        StatTile(L("Best"), Fmt.lap(e.bestLap?.time), Modifier.weight(1f), color = if (e.bestLap == null) Theme.text else Theme.purple)
        StatTile(L("Velocità"), Fmt.speed(e.speed), Modifier.weight(1f), unit = Fmt.speedUnit)
        if (m.drivenKind.onTwoWheels) StatTile(L("Piega"), "${leanAngle(e.lateralG).roundToInt()}°", Modifier.weight(1f))
    }
}

@Composable
private fun MiniMapCard(height: Int) {
    val m = LocalModel.current
    val track = m.selectedTrack ?: return
    val e = m.engine
    val lines = remember(track) { trackLines(track.outline, track.start, track.sectors) }
    Panel(padding = 8.dp) {
        Box(Modifier.fillMaxWidth().height(height.dp).clip(RoundedCornerShape(16.dp))) {
            SatelliteMap(
                Modifier.fillMaxSize(), frame = track.allPoints, frameKey = track.id, lines = lines,
                dots = friendDots() + listOfNotNull(e.position?.let { MapDot(it, Theme.accent) }),
            )
            Row(Modifier.padding(8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Badge(L("Giri: %lld", e.laps.size))
                track.length?.let { Badge(Fmt.distance(it), Theme.sub) }
            }
        }
    }
}

/** The cars of the live group on this track, as their latest position put them. */
@Composable
private fun friendDots(): List<MapDot> {
    val g = LocalModel.current.group
    val now = System.currentTimeMillis()
    return g.members.mapNotNull { mm ->
        val p = mm.position ?: return@mapNotNull null
        if (!mm.online || now - p.received > 10_000 || g.mine.track?.isSame(mm.track) != true) return@mapNotNull null
        MapDot(p.coord, GroupColors.color(mm.color), 6f, label = mm.name.take(1).uppercase())
    }
}

@Composable
private fun SessionButton() {
    val m = LocalModel.current
    val view = LocalView.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        PrimaryButton(
            if (m.isRunning) L("Ferma sessione") else L("Avvia sessione"),
            if (m.isRunning) Icons.Filled.Stop else Icons.Filled.PlayArrow,
            if (m.isRunning) Theme.bad else Theme.accent,
        ) {
            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
            if (m.isRunning) m.stop() else m.start()
        }
        val hint = when (m.source) {
            SourceKind.demo -> L("Demo: un'auto simulata gira sulla pista selezionata.")
            SourceKind.phone -> L("GPS dell'iPhone, circa 1 Hz: per tempi precisi usa l'ESP32.")
            SourceKind.device -> if (m.ble.state == BleManager.State.connected) L("Il giro parte al primo passaggio sulla linea del via.")
            else L("Collega l'ESP32 nella scheda Dispositivo.")
        }
        Text(hint, fontSize = 12.sp, color = Theme.sub, textAlign = TextAlign.Center)
    }
}

@Composable
private fun NoTrackCard() {
    val m = LocalModel.current
    Panel(padding = 24.dp, glow = Theme.accent) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Icon(Icons.Filled.Route, null, tint = Theme.accent, modifier = Modifier.size(34.dp))
            Text(if (m.selectedTrack == null) L("Scegli una pista") else L("Segna la linea del via"), fontSize = 22.sp, fontWeight = FontWeight.Black, color = Theme.text)
            Text(
                L("Cerca il circuito su OpenStreetMap, poi tocca la pista sulla mappa satellitare per mettere il via e gli intermedi."),
                fontSize = 14.sp, color = Theme.sub,
            )
            PrimaryButton(L("Vai alle piste"), Icons.Filled.Map) { m.tab = AppTab.tracks }
        }
    }
}

@Composable
private fun LapBanner(event: LapEvent) {
    val color = when {
        event.isRecord -> Theme.yellow
        event.isBest -> Theme.purple
        (event.gap ?: 0.0) <= 0 -> Theme.good
        else -> Theme.yellow
    }
    val shape = RoundedCornerShape(24.dp)
    Row(
        Modifier.fillMaxWidth().shadow(24.dp, shape, ambientColor = color, spotColor = color).clip(shape)
            .background(Theme.panel.copy(alpha = 0.96f)).border(1.5.dp, color.copy(alpha = 0.8f), shape).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(color.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
            Icon(
                when {
                    event.isRecord -> Icons.Filled.EmojiEvents
                    event.isBest -> Icons.Filled.WorkspacePremium
                    else -> Icons.Filled.SportsScore
                },
                null, tint = color, modifier = Modifier.size(24.dp),
            )
        }
        Column(Modifier.weight(1f)) {
            Text(
                when {
                    event.isRecord -> L("GIRO %lld · RECORD PISTA", event.number)
                    event.isBest -> L("GIRO %lld · NUOVO BEST", event.number)
                    else -> L("GIRO %lld", event.number)
                },
                fontSize = 12.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, color = color,
            )
            BigText(Fmt.lap(event.time), 32.sp)
        }
        Column(horizontalAlignment = Alignment.End) {
            event.gap?.let {
                Text(Fmt.delta(it), style = Theme.numStyle(20.sp, FontWeight.Black, if (it <= 0) Theme.good else Theme.bad))
            }
            val rival = event.rival
            val rg = event.rivalGap
            if (rival != null && rg != null) {
                Text(L("vs %@ %@", rival, Fmt.delta(rg)), style = Theme.numStyle(12.sp, FontWeight.Black, if (rg <= 0) Theme.good else Theme.bad), maxLines = 1)
            }
        }
    }
}

/** Grey line under a list. */
@Composable
fun Hairline() = Box(Modifier.fillMaxWidth().height(0.5.dp).background(Theme.line.copy(alpha = 0.6f)))

/** A tap you feel: stronger for a best or a confirmation. */
fun haptic(view: android.view.View, strong: Boolean = false) {
    view.performHapticFeedback(
        if (strong && android.os.Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.LONG_PRESS,
    )
}
