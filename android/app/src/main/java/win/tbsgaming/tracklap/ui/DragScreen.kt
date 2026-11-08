package win.tbsgaming.tracklap.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.SportsScore
import androidx.compose.material.icons.filled.Straighten
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.Edition
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalNav
import win.tbsgaming.tracklap.SourceKind
import win.tbsgaming.tracklap.data.DragRecord
import win.tbsgaming.tracklap.gps.BleManager
import win.tbsgaming.tracklap.model.DragMeasure
import win.tbsgaming.tracklap.model.DragResult
import win.tbsgaming.tracklap.model.DragRun
import win.tbsgaming.tracklap.model.DragSummary
import win.tbsgaming.tracklap.timing.DragEngine
import win.tbsgaming.tracklap.timing.DragEvent
import java.util.Locale
import kotlin.math.max

@Composable
fun DragScreen() {
    val m = LocalModel.current
    val view = LocalView.current
    var banner by remember { mutableStateOf<DragEvent?>(null) }
    val event = m.drag.lastEvent
    LaunchedEffect(event?.id) {
        if (event == null) return@LaunchedEffect
        haptic(view, event.isRecord)
        banner = event
        delay(3000)
        if (banner?.id == event.id) banner = null
    }
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            DragHeader()
            if (m.isRunning) {
                BusyCard()
            } else {
                SpeedCard()
                SourceNote()
                m.drag.run?.let { RunCard(it, m.drag.inProgress) }
                RecordsCard()
                HistoryList()
            }
        }
        AnimatedVisibility(
            banner != null, enter = slideInVertically { -it } + fadeIn(), exit = slideOutVertically { -it } + fadeOut(),
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        ) {
            banner?.let { DragBanner(it) }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DragHeader() {
    val m = LocalModel.current
    var menu by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ScreenHeader(Icons.Filled.Speed, "Drag", m.profile.displayVehicle.ifEmpty { L("Accelerazione e frenata") }) {
            Box {
                RoundIconButton(Icons.Filled.Tune) { menu = true }
                DropdownMenu(menu, onDismissRequest = { menu = false }, containerColor = Theme.panel) {
                    MenuToggle(L("Rollout di 1 ft"), Icons.Filled.Straighten, m.dragRollout) { m.setDragRollout(it) }
                    MenuToggle(L("Partenza automatica da fermo"), Icons.Filled.AutoAwesome, !m.dragManualStart) { m.setDragManualStart(!it) }
                }
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            GpsPill()
            StatusPill(m.source.icon, m.source.short)
            if (m.dragRollout) StatusPill(Icons.Filled.Straighten, "Rollout", Theme.yellow)
            if (Edition.online) ActiveCarChip()
        }
    }
}

@Composable
fun MenuToggle(title: String, icon: ImageVector, on: Boolean, set: (Boolean) -> Unit) {
    DropdownMenuItem(
        text = { Text(title, color = Theme.text, fontSize = 15.sp) },
        leadingIcon = { Icon(icon, null, tint = Theme.accent) },
        trailingIcon = {
            Switch(on, set, colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Color.Black))
        },
        onClick = { set(!on) },
    )
}

@Composable
private fun BusyCard() {
    val m = LocalModel.current
    Panel(padding = 24.dp, glow = Theme.yellow) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.Timer, null, tint = Theme.yellow, modifier = Modifier.size(30.dp))
            Text(L("Sessione in corso"), fontSize = 20.sp, fontWeight = FontWeight.Black, color = Theme.text)
            Text(L("Mentre cronometri i giri le corse drag sono in pausa: ferma la sessione in Live per misurare."), fontSize = 14.sp, color = Theme.sub)
            SecondaryButton(L("Vai a Live"), Icons.Filled.Timer) { m.tab = AppTab.live }
        }
    }
}

@Composable
private fun SpeedCard() {
    val m = LocalModel.current
    val drag = m.drag
    val view = LocalView.current
    val color = when (drag.phase) {
        DragEngine.Phase.moving -> Theme.yellow
        DragEngine.Phase.ready -> Theme.good
        DragEngine.Phase.running -> Theme.accent
    }
    val waitingButton = m.dragManualStart && !drag.armed
    val title = when (drag.phase) {
        DragEngine.Phase.moving -> if (waitingButton) L("PREMI PER PARTIRE") else L("FERMATI PER PARTIRE")
        DragEngine.Phase.ready -> L("PRONTO")
        DragEngine.Phase.running -> if (drag.run?.standing == false) L("RIPRESA") else L("IN CORSA")
    }
    val hint = when (drag.phase) {
        DragEngine.Phase.moving -> if (waitingButton)
            L("Da fermo premi Pronto al via, poi parti: il tempo parte appena ti muovi. Riprese e frenate si misurano anche in movimento.")
        else L("Da fermo il tempo parte da solo appena ti muovi. Riprese e frenate si misurano anche in movimento.")
        DragEngine.Phase.ready -> L("Via quando vuoi: il tempo parte appena l'auto si muove.")
        DragEngine.Phase.running -> L("Fermati o togli gas per chiudere la corsa.")
    }
    val now = frameClock(drag.inProgress)
    Panel(padding = 20.dp, glow = color) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontSize = 13.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp, color = color)
                Spacer(Modifier.weight(1f))
                if (drag.inProgress) Text(Fmt.dragTime(drag.startWall?.let { now - it }) + " s", style = Theme.numStyle(15.sp, FontWeight.Black))
            }
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BigText(Fmt.speed(drag.speed), 96.sp)
                Text(Fmt.speedUnit, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Theme.sub, modifier = Modifier.padding(bottom = 18.dp))
            }
            Text(hint, fontSize = 14.sp, color = Theme.sub)
            if (m.dragManualStart && !drag.inProgress) {
                if (drag.armed) {
                    SecondaryButton(
                        if (drag.phase == DragEngine.Phase.ready) L("Pronto: parti quando vuoi") else L("Fermati: poi parti"),
                        Icons.Filled.SportsScore, Theme.good,
                    ) {
                        drag.disarm()
                        haptic(view)
                    }
                } else {
                    PrimaryButton(L("Pronto al via"), Icons.Filled.SportsScore, Theme.good) {
                        drag.arm()
                        haptic(view, true)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile(
                    L("Accelerazione"), String.format(Locale.US, "%.2f", drag.accel / 9.80665), Modifier.weight(1f), unit = "g",
                    color = if (drag.accel > 0.5) Theme.good else if (drag.accel < -0.5) Theme.bad else Theme.text,
                )
                StatTile(L("Distanza"), if (drag.inProgress) Fmt.distance(drag.distance) else "—", Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun SourceNote() {
    val m = LocalModel.current
    when (m.source) {
        SourceKind.demo -> Column(verticalArrangement = Arrangement.spacedBy(8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            PrimaryButton(if (m.demoDrag.isRunning) L("Corsa demo in corso…") else L("Corsa demo"), Icons.Filled.PlayArrow, enabled = !m.demoDrag.isRunning) {
                m.startDemoDrag()
            }
            Text(L("Un'auto simulata parte da ferma, fa un chilometro e frena."), fontSize = 12.sp, color = Theme.sub, textAlign = TextAlign.Center)
        }
        SourceKind.phone -> Note(
            Icons.Filled.Warning, Theme.yellow,
            L("Il GPS dell'iPhone dà circa un fix al secondo: i tempi sono indicativi, mezzo secondo in più o in meno. Per misure vere serve l'ESP32 a 10 Hz o più."),
        )
        SourceKind.device -> if (m.ble.state != BleManager.State.connected) Note(Icons.Filled.Sensors, Theme.sub, L("Collega l'ESP32 nella scheda Dispositivo."))
    }
}

@Composable
private fun RunCard(run: DragRun, live: Boolean) {
    val m = LocalModel.current
    val nav = LocalNav.current
    Panel(glow = if (live) Theme.accent else null) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(if (run.standing) L("DA FERMO") else L("IN MOVIMENTO"), fontSize = 13.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp, color = Theme.accent)
                if (live) Badge(L("In corso"), Theme.bad)
                if (run.rollout) Badge("Rollout", Theme.yellow)
                Spacer(Modifier.weight(1f))
                if (!live) {
                    Row(Modifier.clickable { nav.push(AppTab.drag, "run:${run.id}") }, verticalAlignment = Alignment.CenterVertically) {
                        Text(Fmt.day(run.date), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.sub)
                        Icon(Icons.Filled.ChevronRight, null, tint = Theme.sub, modifier = Modifier.size(16.dp))
                    }
                }
            }
            ResultGrid(run.results, run.standing, m.drags.records(run.carID), pending = live)
            if (!live && run.trace.size > 2) DragChart(run, Modifier.fillMaxWidth().height(170.dp))
        }
    }
}

@Composable
fun ResultGrid(results: List<DragResult>, standing: Boolean, records: Map<String, DragRecord>, pending: Boolean = false) {
    val measures = DragMeasure.all().filter { standing || !it.standing }
    val done = results.map { it.name }.toSet()
    // Measures of other units (a run from before a change of units) come after.
    val others = results.filter { r -> measures.none { it.name == r.name } }
    val cells = measures.map { mm -> Triple(mm.name, results.firstOrNull { it.name == mm.name }, pending && mm.name !in done) } +
        others.map { Triple(it.name, it, false) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in cells.chunked(2)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (c in row) ResultTile(c.first, c.second, records[c.first], c.third, Modifier.weight(1f))
                if (row.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun ResultTile(name: String, result: DragResult?, record: DragRecord?, waiting: Boolean, modifier: Modifier) {
    val shape = RoundedCornerShape(16.dp)
    val best = result?.let { r -> (if (r.kind == DragMeasure.Kind.braking) r.distance else r.time) <= (record?.value ?: Double.POSITIVE_INFINITY) + 1e-9 } ?: false
    val color = if (result == null) Theme.sub else if (best) Theme.purple else Theme.text
    Column(
        modifier.alpha(if (waiting) 0.55f else 1f).clip(shape)
            .background(if (best) Theme.purple.copy(alpha = 0.14f) else Theme.input.copy(alpha = 0.6f))
            .border(1.dp, if (best) Theme.purple.copy(alpha = 0.6f) else Theme.line.copy(alpha = 0.6f), shape).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(name, fontSize = 11.sp, fontWeight = FontWeight.Black, color = Theme.sub)
            if (best) Icon(Icons.Filled.WorkspacePremium, null, tint = Theme.purple, modifier = Modifier.size(12.dp))
        }
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            val value = result?.let { if (it.kind == DragMeasure.Kind.braking) Fmt.shortDistance(it.distance) else Fmt.dragTime(it.time) } ?: "—"
            Text(value, style = Theme.numStyle(24.sp, color = color), maxLines = 1)
            if (result != null) {
                Text(if (result.kind == DragMeasure.Kind.braking) Fmt.shortDistanceUnit else "s", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.sub, modifier = Modifier.padding(bottom = 3.dp))
            }
        }
        val detail = when (result?.kind) {
            null -> " "
            DragMeasure.Kind.distance -> L("a %@ %@", Fmt.speed(result.speed), Fmt.speedUnit)
            DragMeasure.Kind.speed -> L("in %@", Fmt.distance(result.distance))
            DragMeasure.Kind.braking -> L("in %@ s", Fmt.dragTime(result.time))
        }
        Text(detail, style = Theme.numStyle(11.sp, FontWeight.SemiBold, Theme.sub), maxLines = 1)
    }
}

/** Speed over the run, with the main measures marked. */
@Composable
fun DragChart(run: DragRun, modifier: Modifier) {
    val pts = thin(run.trace)
    val headline = DragMeasure.all().filter { it.headline }.map { it.name }.toSet()
    LineChart(
        listOf(ChartSeries(pts.map { it.t }, pts.map { it.v * Fmt.speedFactor }, Theme.accent, fill = true)),
        modifier,
        marks = run.results.map { r ->
            val main = r.name in headline
            ChartMark(r.at, r.speed * Fmt.speedFactor, if (main) Theme.purple else Theme.text, if (main) 5f else 3f, if (main) r.name else null)
        },
        xLabel = { "${it.toInt()} s" },
        yMin = 0.0,
    )
}

@Composable
private fun RecordsCard() {
    val m = LocalModel.current
    val car = m.activeCar
    var allCars by remember { mutableStateOf(false) }
    val records = m.drags.records(if (car != null && !allCars) car.id else null)
    if (records.isEmpty() && m.drags.summaries.isEmpty()) return
    val measures = DragMeasure.all().filter { records[it.name] != null }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel(if (car != null && !allCars) L("I tuoi record con %@", car.displayName) else L("I tuoi record"))
        if (car != null) Segmented(listOf(L("Questo veicolo") to false, L("Tutte") to true), allCars) { allCars = it }
        Panel(padding = 4.dp) {
            for ((i, mm) in measures.withIndex()) {
                val rec = records.getValue(mm.name)
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(mm.name, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Theme.text, modifier = Modifier.weight(1f))
                    Text(Fmt.dayShort(rec.run.date), fontSize = 12.sp, color = Theme.sub, modifier = Modifier.padding(end = 12.dp))
                    val r = rec.result
                    Text(
                        if (r.kind == DragMeasure.Kind.braking) "${Fmt.shortDistance(r.distance)} ${Fmt.shortDistanceUnit}" else "${Fmt.dragTime(r.time)} s",
                        style = Theme.numStyle(16.sp, FontWeight.Black, Theme.purple),
                    )
                }
                if (i < measures.size - 1) Hairline()
            }
        }
    }
}

@Composable
private fun HistoryList() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val runs = m.drags.summaries
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionLabel(if (runs.size == 1) L("1 corsa") else L("%lld corse", runs.size))
        if (runs.isEmpty()) {
            Panel(padding = 20.dp) {
                Text(L("Ancora nessuna corsa"), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                Spacer(Modifier.height(6.dp))
                Text(L("Fermati in un posto sicuro e chiuso al traffico, poi parti: ogni corsa finisce qui con tutti i tempi e il grafico."), fontSize = 14.sp, color = Theme.sub)
            }
        }
        for (s in runs) DragRunRow(s) { nav.push(AppTab.drag, "run:${s.id}") }
    }
}

@Composable
private fun DragRunRow(s: DragSummary, open: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.panel).border(1.dp, Theme.line.copy(alpha = 0.8f), shape).clickable(onClick = open).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(s.vehicle.ifEmpty { if (s.standing) L("Da fermo") else L("In movimento") }, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1)
            Text(Fmt.day(s.date), fontSize = 12.sp, color = Theme.sub)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Badge(if (s.results.size == 1) L("1 misura") else L("%lld misure", s.results.size))
                if (!s.standing) Badge(L("Ripresa"), Theme.yellow)
            }
        }
        s.headline?.let { h ->
            Column(horizontalAlignment = Alignment.End) {
                Text(h.name, fontSize = 10.sp, fontWeight = FontWeight.Black, color = Theme.sub)
                Text(if (h.kind == DragMeasure.Kind.braking) Fmt.shortDistance(h.distance) else Fmt.dragTime(h.time), style = Theme.numStyle(22.sp, FontWeight.Black))
            }
        }
        Icon(Icons.Filled.ChevronRight, null, tint = Theme.sub, modifier = Modifier.padding(start = 6.dp).size(18.dp))
    }
}

@Composable
private fun DragBanner(event: DragEvent) {
    val r = event.result
    val color = if (event.isRecord || event.isBest) Theme.purple else Theme.accent
    val shape = RoundedCornerShape(24.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.panel.copy(alpha = 0.96f)).border(1.5.dp, color.copy(alpha = 0.8f), shape).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(44.dp).clip(CircleShape).background(color.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
            Icon(if (event.isRecord) Icons.Filled.EmojiEvents else Icons.Filled.Speed, null, tint = color, modifier = Modifier.size(24.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(if (event.isRecord) L("%@ · NUOVO RECORD", r.name) else r.name, fontSize = 12.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, color = color)
            BigText(if (r.kind == DragMeasure.Kind.braking) "${Fmt.shortDistance(r.distance)} ${Fmt.shortDistanceUnit}" else "${Fmt.dragTime(r.time)} s", 32.sp)
        }
        Text(
            if (r.kind == DragMeasure.Kind.distance) "${Fmt.speed(r.speed)} ${Fmt.speedUnit}" else if (r.kind == DragMeasure.Kind.speed) Fmt.distance(r.distance) else "${Fmt.dragTime(r.time)} s",
            style = Theme.numStyle(16.sp, FontWeight.Bold, Theme.sub),
        )
    }
}

/** One run: every measure, the numbers of the run and its charts. */
@Composable
fun DragRunScreen(id: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val run = remember(id) { m.drags.load(id) }
    var confirmDelete by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        TopBar(if (run?.standing == false) L("Ripresa") else L("Corsa drag"), onBack = { nav.pop(AppTab.drag) }) {
            RoundIconButton(Icons.Filled.Delete, Theme.bad) { confirmDelete = true }
        }
        if (run == null) return@Column
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Panel {
                Text(run.vehicle.ifEmpty { if (run.standing) L("Da fermo") else L("In movimento") }, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Theme.text)
                Text(Fmt.day(run.date), fontSize = 14.sp, color = Theme.sub)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Badge(if (run.standing) L("Da fermo") else L("Ripresa"))
                    if (run.rollout) Badge("Rollout", Theme.yellow)
                    Badge(SourceKind.entries.firstOrNull { it.name == run.source }?.short ?: run.source, Theme.sub)
                }
            }
            ResultGrid(run.results, run.standing, m.drags.records(run.carID))
            val slope = run.summary.slope
            val tiles = listOf(
                Triple(L("V max"), Fmt.speed(run.maxSpeed), Fmt.speedUnit),
                Triple(L("Picco"), String.format(Locale.US, "%.2f", run.peakG), "g"),
                Triple(L("Distanza"), Fmt.distance(run.trace.lastOrNull()?.d), null),
                Triple(L("Pendenza"), slope?.let { Fmt.slope(it) } ?: "—", null),
                Triple(L("Frequenza"), Fmt.hz(run.rate), null),
                Triple(L("Misure"), "${run.results.size}", null),
            )
            for (row in tiles.chunked(3)) {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    for (t in row) StatTile(t.first, t.second, Modifier.weight(1f), unit = t.third)
                }
            }
            if (slope != null && slope < -0.5) Note(Icons.Filled.Warning, Theme.yellow, L("In discesa: i tempi non sono confrontabili con quelli in piano."))
            Panel {
                Text(L("Velocità"), fontSize = 12.sp, fontWeight = FontWeight.Black, color = Theme.text)
                Spacer(Modifier.height(8.dp))
                DragChart(run, Modifier.fillMaxWidth().height(200.dp))
            }
            Panel {
                Text(L("Accelerazione"), fontSize = 12.sp, fontWeight = FontWeight.Black, color = Theme.text)
                Spacer(Modifier.height(8.dp))
                val pts = run.trace
                val g = pts.indices.map { i ->
                    val a = pts[max(0, i - 2)]
                    val b = pts[minOf(pts.size - 1, i + 2)]
                    if (b.t > a.t) (b.v - a.v) / (b.t - a.t) / 9.80665 else 0.0
                }
                LineChart(
                    listOf(ChartSeries(thin(pts.map { it.t }), thin(g), Theme.good, fill = true)), Modifier.fillMaxWidth().height(160.dp),
                    xLabel = { "${it.toInt()} s" }, yLabel = { String.format(Locale.US, "%.1f g", it) }, zeroLine = true,
                )
            }
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            containerColor = Theme.panel,
            title = { Text(L("Eliminare questa corsa?"), color = Theme.text) },
            confirmButton = {
                TextButton({
                    confirmDelete = false
                    m.deleteDragRun(id)
                    nav.pop(AppTab.drag)
                }) { Text(L("Elimina"), color = Theme.bad) }
            },
            dismissButton = { TextButton({ confirmDelete = false }) { Text(L("Annulla"), color = Theme.accent) } },
        )
    }
}

/** The bar on top of a page below a tab's first one: back, title, actions. */
@Composable
fun TopBar(title: String, onBack: () -> Unit, actions: @Composable () -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        RoundIconButton(Icons.AutoMirrored.Filled.ArrowBack, onClick = onBack)
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
        Box(Modifier.width(40.dp), contentAlignment = Alignment.Center) { actions() }
    }
}
