package win.tbsgaming.tracklap.ui

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.TableChart
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalNav
import win.tbsgaming.tracklap.data.Export
import win.tbsgaming.tracklap.data.SessionLap
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.LapComparison
import win.tbsgaming.tracklap.model.Session
import win.tbsgaming.tracklap.model.SessionSummary
import win.tbsgaming.tracklap.model.pointAtDistance
import win.tbsgaming.tracklap.timing.Corners
import win.tbsgaming.tracklap.timing.GForce
import java.io.File
import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

@Composable
fun SessionsScreen() {
    val m = LocalModel.current
    val nav = LocalNav.current
    var confirmDelete by remember { mutableStateOf<SessionSummary?>(null) }
    val list = m.sessions.summaries
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ScreenHeader(Icons.Filled.BarChart, L("Sessioni"), if (list.size == 1) L("1 sessione") else L("%lld sessioni", list.size))
        FriendsRow()
        if (list.isEmpty()) {
            Panel(padding = 24.dp) {
                Text(L("Ancora nessuna sessione"), fontSize = 20.sp, fontWeight = FontWeight.Black, color = Theme.text)
                Spacer(Modifier.height(8.dp))
                Text(L("Avvia una sessione dalla scheda Live: ogni giro viene salvato qui, con tempi, settori, velocità e tracciato."), fontSize = 14.sp, color = Theme.sub)
            }
        }
        for (s in list) SessionCard(s, live = m.isRunning && m.engine.laps.isNotEmpty() && s.id == list.firstOrNull()?.id && s.trackID == m.selectedTrackID,
            onOpen = { nav.push(AppTab.sessions, "session:${s.id}") }, onDelete = { confirmDelete = s })
    }
    confirmDelete?.let { s ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null }, containerColor = Theme.panel,
            title = { Text(L("Elimina sessione"), color = Theme.text) },
            text = { Text("${s.trackName} · ${Fmt.day(s.date)}", color = Theme.sub) },
            confirmButton = { TextButton({ m.sessions.delete(s.id); confirmDelete = null }) { Text(L("Elimina"), color = Theme.bad) } },
            dismissButton = { TextButton({ confirmDelete = null }) { Text(L("Annulla"), color = Theme.accent) } },
        )
    }
}

/** The laps friends sent, above the sessions. */
@Composable
private fun FriendsRow() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val n = m.friends.laps.size
    ListRow(
        Icons.Filled.Groups, L("Giri degli amici"),
        if (n == 0) L("Apri con TrackLap i file .tracklap che ti mandano") else if (n == 1) L("1 giro da sfidare") else L("%lld giri da sfidare", n),
        Theme.yellow,
    ) { nav.push(AppTab.sessions, "friends") }
}

@Composable
private fun SessionCard(s: SessionSummary, live: Boolean, onOpen: () -> Unit, onDelete: () -> Unit) {
    val shape = RoundedCornerShape(22.dp)
    var menu by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.panel).border(1.dp, Theme.line.copy(alpha = 0.8f), shape).clickable(onClick = onOpen).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(s.trackName, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, false))
                if (live) Badge(L("In corso"), Theme.bad)
            }
            Text(Fmt.day(s.date), fontSize = 12.sp, color = Theme.sub)
            s.layoutName?.let { Text(it, fontSize = 12.sp, color = Theme.sub, maxLines = 1) }
            s.carName?.let { Text(it + (s.setupName?.let { n -> " · " + n + (s.setupVersion?.let { v -> " " + L("v%lld", v) } ?: "") } ?: ""), fontSize = 12.sp, color = Theme.accent, maxLines = 1) }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Badge(if (s.lapCount == 1) L("1 giro") else L("%lld giri", s.lapCount))
                Badge(s.source, Theme.sub)
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text("BEST", fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, color = Theme.sub)
            Text(Fmt.lap(s.best), style = Theme.numStyle(20.sp, FontWeight.Black, Theme.purple))
            s.ideal?.let { Text(L("ideale %@", Fmt.lap(it)), style = Theme.numStyle(11.sp, FontWeight.SemiBold, Theme.sub)) }
        }
        Box {
            Icon(Icons.Filled.UnfoldMore, null, tint = Theme.sub, modifier = Modifier.padding(start = 8.dp).size(20.dp).clickable { menu = true })
            DropdownMenu(menu, { menu = false }, containerColor = Theme.panel) {
                DropdownMenuItem({ Text(L("Elimina sessione"), color = Theme.bad) }, { menu = false; onDelete() }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.bad) })
            }
        }
    }
}

/** A lap to compare with: from this session, or the best of another session on the track. */
private data class Ref(val lap: Lap, val title: String, val id: String)

private enum class MapMode { speed, delta }

@Composable
fun SessionDetailScreen(id: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val context = LocalContext.current
    val session = remember(id, m.sessions.summaries) { m.sessions.load(id) }
    var share by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var sharing by remember { mutableStateOf<Lap?>(null) }
    Column(Modifier.fillMaxSize()) {
        TopBar(session?.trackName ?: L("Sessione"), onBack = { nav.pop(AppTab.sessions) }) {
            Box {
                RoundIconButton(Icons.Filled.Share) { share = true }
                DropdownMenu(share, { share = false }, containerColor = Theme.panel) {
                    if (session != null) {
                        session.best?.let { b ->
                            DropdownMenuItem({ Text(L("Condividi il giro migliore"), color = Theme.text) }, { share = false; sharing = b },
                                leadingIcon = { Icon(Icons.Filled.Groups, null, tint = Theme.accent) })
                        }
                        DropdownMenuItem({ Text(L("Esporta GPX"), color = Theme.text) }, { share = false; shareFile(context, Export.gpx(context, session), "application/gpx+xml") },
                            leadingIcon = { Icon(Icons.Filled.Map, null, tint = Theme.accent) })
                        DropdownMenuItem({ Text(L("Esporta CSV"), color = Theme.text) }, { share = false; shareFile(context, Export.csv(context, session), "text/csv") },
                            leadingIcon = { Icon(Icons.Filled.TableChart, null, tint = Theme.accent) })
                    }
                    DropdownMenuItem({ Text(L("Elimina sessione"), color = Theme.bad) }, { share = false; confirmDelete = true },
                        leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.bad) })
                }
            }
        }
        if (session == null || session.laps.isEmpty()) return@Column
        SessionBody(session) { sharing = it }
    }
    sharing?.let { lap -> if (session != null) ShareLapDialog(session, lap) { sharing = null } }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false }, containerColor = Theme.panel,
            title = { Text(L("Elimina sessione"), color = Theme.text) },
            confirmButton = {
                TextButton({
                    confirmDelete = false
                    m.sessions.delete(id)
                    nav.pop(AppTab.sessions)
                }) { Text(L("Elimina"), color = Theme.bad) }
            },
            dismissButton = { TextButton({ confirmDelete = false }) { Text(L("Annulla"), color = Theme.accent) } },
        )
    }
}

private fun shareFile(context: Context, file: File, type: String) {
    val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
    val send = Intent(Intent.ACTION_SEND).apply {
        this.type = type
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

@Composable
private fun SessionBody(s: Session, share: (Lap) -> Unit) {
    val m = LocalModel.current
    val best = s.best!!
    var lapID by remember { mutableStateOf(best.id) }
    val others: List<SessionLap> = remember(s.id) { m.sessions.bestLaps(s.trackID, s.layout, main = true, excluding = s.id) }
    val record = remember(s.id) { m.sessions.record(s.trackID, s.layout) }
    val refs = remember(s.id) {
        s.laps.map { Ref(it, L("Giro %lld", it.number) + " · " + Fmt.lap(it.time), it.id) } +
            others.map { Ref(it.lap, Fmt.dayShort(it.session.date) + " · " + Fmt.lap(it.lap.time), "other-" + it.lap.id) } +
            m.friends.laps(s.trackID).mapNotNull { f -> m.friends.lap(f.id)?.let { Ref(it, f.title, "friend-" + f.id) } }
    }
    val lap = s.laps.firstOrNull { it.id == lapID } ?: best
    var refID by remember { mutableStateOf<String?>(null) }
    // The reference by default: the best lap of the session, or the best before when this is the best.
    val ref = refs.firstOrNull { it.id == refID && it.lap.id != lap.id }
        ?: refs.firstOrNull { it.lap.id == best.id && best.id != lap.id }
        ?: others.firstOrNull()?.let { o -> refs.firstOrNull { it.id == "other-" + o.lap.id } }
        ?: refs.firstOrNull { it.lap.id != lap.id }
    var mapMode by remember { mutableStateOf(MapMode.speed) }
    var cursor by remember { mutableStateOf<Double?>(null) }
    val isTrackRecord = record?.lap?.id == best.id

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Panel {
            Text(s.trackName, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Theme.text)
            Text(Fmt.day(s.date), fontSize = 14.sp, color = Theme.sub)
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Badge(s.source, Theme.sub)
                s.summary.layoutName?.let { Badge(it, Theme.accent) }
                if (isTrackRecord) Badge(L("Record pista"), Theme.yellow)
            }
            s.carName?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.accent)
            }
            s.setup?.let { st ->
                var open by remember { mutableStateOf(false) }
                Text(L("%@ · v%lld", st.name, st.version), fontSize = 13.sp, color = Theme.yellow, modifier = Modifier.padding(top = 4.dp).clickable { open = true })
                if (open) AlertDialog(
                    onDismissRequest = { open = false }, containerColor = Theme.panel,
                    title = { Text(L("%@ · v%lld", st.name, st.version), color = Theme.text) },
                    text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) { SetupValuesView(st.values) } },
                    confirmButton = { TextButton({ open = false }) { Text(L("Fine"), color = Theme.accent) } },
                )
            }
        }
        val stats = listOf(
            Triple(L("Best"), Fmt.lap(best.time), Theme.purple),
            Triple(L("Ideale"), Fmt.lap(s.idealTime), Theme.text),
            Triple(L("Media"), Fmt.lap(s.averageTime), Theme.text),
            Triple(L("Giri"), "${s.laps.size}", Theme.text),
            Triple(L("V max"), Fmt.speed(s.laps.maxOf { it.maxSpeed }) + " " + Fmt.speedUnit, Theme.text),
            Triple(L("Lunghezza"), Fmt.distance(best.distance), Theme.text),
        )
        for (row in stats.chunked(3)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                for (t in row) StatTile(t.first, t.second, Modifier.weight(1f), color = t.third)
            }
        }
        if (s.laps.size > 1) {
            SectionLabel(L("Tempi sul giro"))
            Panel {
                LineChart(
                    listOf(ChartSeries(s.laps.map { it.number.toDouble() }, s.laps.map { it.time }, Theme.accent)),
                    Modifier.fillMaxWidth().height(150.dp),
                    marks = s.laps.map { ChartMark(it.number.toDouble(), it.time, if (it.id == best.id) Theme.purple else Theme.accent, if (it.id == best.id) 5f else 3f) },
                    xLabel = { "${it.toInt()}" }, yLabel = { Fmt.lapShort(it) },
                )
            }
        }

        SectionLabel(L("Analisi"))
        Panel {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Chooser(L("Giro %lld", lap.number) + " · " + Fmt.lap(lap.time), Theme.accent, Modifier.weight(1f),
                        s.laps.map { L("Giro %lld", it.number) + " · " + Fmt.lap(it.time) to it.id }) { lapID = it; cursor = null }
                    Chooser(ref?.title ?: L("Nessun altro giro da confrontare"), Theme.purple, Modifier.weight(1f),
                        refs.filter { it.lap.id != lap.id }.map { it.title to it.id }) { refID = it }
                }
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Theme.input).padding(3.dp)) {
                    for (mode in MapMode.entries) {
                        val on = mode == mapMode
                        Text(
                            if (mode == MapMode.speed) L("Velocità") else L("Guadagno"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                            color = if (on) Theme.text else Theme.sub, textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(if (on) Theme.button else Color.Transparent)
                                .clickable { mapMode = mode }.padding(vertical = 8.dp),
                        )
                    }
                }
                AnalysisMap(lap, ref?.lap, mapMode, cursor, Modifier.fillMaxWidth().height(260.dp).clip(RoundedCornerShape(16.dp)))
                Text(
                    if (mapMode == MapMode.delta) L("Verde dove guadagni sul riferimento, rosso dove perdi. Tratteggiato: la linea del riferimento.")
                    else L("I numeri sono la velocità minima in ogni curva."),
                    fontSize = 12.sp, color = Theme.sub,
                )
                CursorReadout(lap, ref?.lap, cursor)
            }
        }
        Panel {
            Text(L("Velocità"), fontSize = 12.sp, fontWeight = FontWeight.Black, color = Theme.text)
            Spacer(Modifier.height(8.dp))
            val a = thin(lap.trace)
            val series = arrayListOf(ChartSeries(a.map { it.d }, a.map { it.v * Fmt.speedFactor }, Theme.accent))
            ref?.lap?.let { r ->
                val c = LapComparison(lap, r)
                val b = thin(r.trace)
                series.add(0, ChartSeries(b.map { it.d / c.scale }, b.map { it.v * Fmt.speedFactor }, Theme.purple, 2f))
            }
            LineChart(series, Modifier.fillMaxWidth().height(190.dp), xLabel = { Fmt.distance(it) }, cursor = cursor, onCursor = { cursor = it })
        }
        ref?.lap?.let { r ->
            Panel {
                Text(L("Delta sul riferimento"), fontSize = 12.sp, fontWeight = FontWeight.Black, color = Theme.text)
                Spacer(Modifier.height(8.dp))
                val c = LapComparison(lap, r)
                val a = thin(lap.trace)
                LineChart(
                    listOf(ChartSeries(a.map { it.d }, a.map { c.delta(it.d) }, Theme.yellow, fill = false)),
                    Modifier.fillMaxWidth().height(150.dp), xLabel = { Fmt.distance(it) }, yLabel = { String.format(Locale.US, "%+.1f", it) },
                    zeroLine = true, cursor = cursor, onCursor = { cursor = it },
                )
            }
            if (s.sectorCount > 0 && lap.sectors.size == s.sectorCount && r.sectors.size == s.sectorCount) {
                SectionLabel(L("Settori"))
                Panel(padding = 4.dp) {
                    for (k in 0 until s.sectorCount) {
                        val d = lap.sectors[k] - r.sectors[k]
                        Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("S${k + 1}", fontSize = 13.sp, fontWeight = FontWeight.Black, color = Theme.sub, modifier = Modifier.width(40.dp))
                            Text(Fmt.sector(lap.sectors[k]), style = Theme.numStyle(16.sp), modifier = Modifier.weight(1f))
                            Text(Fmt.sector(r.sectors[k]), style = Theme.numStyle(14.sp, color = Theme.purple), modifier = Modifier.weight(1f))
                            Text(Fmt.delta(d), style = Theme.numStyle(15.sp, FontWeight.Black, if (d <= 0) Theme.good else Theme.bad))
                        }
                        if (k < s.sectorCount - 1) Hairline()
                    }
                }
            }
        }
        SectionLabel(L("Accelerazioni"))
        GGDiagram(lap)
        SectionLabel(L("Giri"))
        Panel(padding = 4.dp) {
            for ((i, l) in s.laps.withIndex()) {
                LapRow(l, best.time, l.id == lap.id, onShare = { share(l) }) { lapID = l.id; cursor = null }
                if (i < s.laps.size - 1) Hairline()
            }
        }
    }
}

@Composable
private fun Chooser(title: String, color: Color, modifier: Modifier, options: List<Pair<String, String>>, pick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box(modifier) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(color.copy(alpha = 0.12f)).clickable(enabled = options.isNotEmpty()) { open = true }
                .padding(horizontal = 10.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(color))
            Text(title, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (options.isNotEmpty()) Icon(Icons.Filled.UnfoldMore, null, tint = Theme.sub, modifier = Modifier.size(14.dp))
        }
        DropdownMenu(open, { open = false }, containerColor = Theme.panel) {
            for ((t, key) in options) DropdownMenuItem({ Text(t, color = Theme.text) }, { open = false; pick(key) })
        }
    }
}

/** The lap on the satellite map, coloured by speed with the corner speeds, or by where it gains on the reference. */
@Composable
private fun AnalysisMap(lap: Lap, ref: Lap?, mode: MapMode, cursor: Double?, modifier: Modifier) {
    val m = LocalModel.current
    val pts = remember(lap.id) { thin(lap.trace, 600) }
    val coords = pts.map { Coord(it.lat, it.lon) }
    val track = m.tracks.tracks.firstOrNull { t -> t.start != null && lap.trace.isNotEmpty() && win.tbsgaming.tracklap.model.Geo.distance(t.start.mid, Coord(lap.trace[0].lat, lap.trace[0].lon)) < 100 }
    val lines = ArrayList<MapLine>()
    if (track != null) lines += trackLines(emptyList(), track.start, track.sectors)
    if (mode == MapMode.speed) {
        val lo = pts.minOfOrNull { it.v } ?: 0.0
        val hi = pts.maxOfOrNull { it.v } ?: 1.0
        lines += MapLine(coords, Theme.accent, 4f, pts.map { speedColor(it.v, lo, hi) }, halo = true)
    } else if (ref != null) {
        val c = LapComparison(lap, ref)
        val r = thin(ref.trace, 600)
        lines += MapLine(r.map { Coord(it.lat, it.lon) }, Theme.purple.copy(alpha = 0.7f), 2f)
        val colors = pts.indices.map { i ->
            if (i == 0) Theme.sub else {
                val dd = pts[i].d - pts[i - 1].d
                if (dd <= 0) Theme.sub else gainColor((c.delta(pts[i].d) - c.delta(pts[i - 1].d)) / dd * 10)
            }
        }
        lines += MapLine(coords, Theme.accent, 4f, colors, halo = true)
    } else {
        lines += MapLine(coords, Theme.accent, 4f, halo = true)
    }
    val dots = ArrayList<MapDot>()
    if (mode == MapMode.speed) {
        for (a in remember(lap.id) { Corners.apexes(lap.trace) }) dots += MapDot(Coord(a.lat, a.lon), Theme.text, 3f, ring = false, label = Fmt.speed(a.v))
    }
    cursor?.let { d -> lap.trace.pointAtDistance(d)?.let { dots += MapDot(Coord(it.lat, it.lon), Theme.accent, 6f) } }
    if (cursor != null && ref != null) LapComparison(lap, ref).refPoint(cursor)?.let { dots += MapDot(Coord(it.lat, it.lon), Theme.purple, 5f) }
    SatelliteMap(modifier, frame = coords, frameKey = lap.id, lines = lines, dots = dots, interactive = true)
}

@Composable
private fun CursorReadout(lap: Lap, ref: Lap?, cursor: Double?) {
    if (cursor == null) {
        Text(L("Trascina sui grafici o sulla barra per muoverti nel giro"), fontSize = 12.sp, color = Theme.sub)
        return
    }
    val p = lap.trace.pointAtDistance(cursor) ?: return
    val c = ref?.let { LapComparison(lap, it) }
    val q = c?.refPoint(cursor)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        StatTile(L("Distanza"), Fmt.distance(cursor), Modifier.weight(1f))
        StatTile(L("Tempo"), Fmt.lap(p.t), Modifier.weight(1f))
        StatTile(L("Velocità"), Fmt.speed(p.v), Modifier.weight(1f), unit = Fmt.speedUnit, color = Theme.accent)
        if (q != null && c != null) {
            val d = c.delta(cursor)
            StatTile("Delta", Fmt.delta(d), Modifier.weight(1f), color = if (d <= 0) Theme.good else Theme.bad)
        }
    }
}

/** The friction circle: every point of the lap, with the strongest of each kind. */
@Composable
private fun GGDiagram(lap: Lap) {
    val g = remember(lap.id) { GForce.along(lap.trace) }
    val lateral = g.maxOfOrNull { abs(it.lateral) } ?: 0.0
    val braking = -(g.minOfOrNull { it.longitudinal } ?: 0.0)
    val accel = g.maxOfOrNull { it.longitudinal } ?: 0.0
    Panel {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            StatTile(L("Laterale"), String.format(Locale.US, "%.2f", lateral), Modifier.weight(1f), unit = "g")
            StatTile(L("Frenata"), String.format(Locale.US, "%.2f", max(0.0, braking)), Modifier.weight(1f), unit = "g")
            StatTile(L("Spinta"), String.format(Locale.US, "%.2f", max(0.0, accel)), Modifier.weight(1f), unit = "g")
        }
        Spacer(Modifier.height(12.dp))
        val scale = max(1.5, max(lateral, max(braking, accel)) * 1.1)
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxWidth(0.8f).aspectRatio(1f)) {
                val r = size.minDimension / 2
                val c = Offset(size.width / 2, size.height / 2)
                for (k in 1..3) drawCircle(Theme.line, r * k / 3, c, style = Stroke(1f))
                drawLine(Theme.line, Offset(c.x - r, c.y), Offset(c.x + r, c.y), 1f)
                drawLine(Theme.line, Offset(c.x, c.y - r), Offset(c.x, c.y + r), 1f)
                for (p in g) {
                    if (p.total == 0.0) continue
                    val x = c.x + (p.lateral / scale * r).toFloat()
                    val y = c.y - (p.longitudinal / scale * r).toFloat()
                    drawCircle(Theme.accent.copy(alpha = 0.5f), 2.5f * density, Offset(x, y))
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        val note = if (GForce.measured(lap.trace)) L("Misurate dall'accelerometro dell'ESP32, a ogni fix del GPS.")
        else L("Calcolate dal GPS: con l'ESP32 a 10 Hz sono affidabili, con il GPS dell'iPhone solo indicative.")
        Text(note, fontSize = 12.sp, color = Theme.sub)
    }
}

@Composable
private fun LapRow(lap: Lap, bestTime: Double, selected: Boolean, onShare: () -> Unit, onClick: () -> Unit) {
    val isBest = lap.time == bestTime
    Row(
        Modifier.fillMaxWidth().background(if (selected) Theme.accent.copy(alpha = 0.08f) else Color.Transparent).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(30.dp).clip(CircleShape).background(if (isBest) Theme.purple.copy(alpha = 0.2f) else Theme.input), contentAlignment = Alignment.Center) {
            Text("${lap.number}", fontSize = 13.sp, fontWeight = FontWeight.Black, color = if (isBest) Theme.purple else Theme.text)
        }
        Column(Modifier.weight(1f)) {
            Text(Fmt.lap(lap.time), style = Theme.numStyle(18.sp, FontWeight.Black, if (isBest) Theme.purple else Theme.text))
            if (lap.sectors.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for ((k, v) in lap.sectors.withIndex()) Text("S${k + 1} ${Fmt.sector(v)}", style = Theme.numStyle(11.sp, FontWeight.SemiBold, Theme.sub))
                }
            }
        }
        Text(if (isBest) L("BEST") else Fmt.delta(lap.time - bestTime), style = Theme.numStyle(14.sp, FontWeight.Black, if (isBest) Theme.purple else Theme.bad))
        if (selected) Icon(Icons.Filled.Check, null, tint = Theme.accent, modifier = Modifier.size(18.dp))
        Icon(Icons.Filled.Share, L("Condividi questo giro"), tint = Theme.sub, modifier = Modifier.size(18.dp).clickable(onClick = onShare))
    }
}
