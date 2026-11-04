package win.tbsgaming.tracklap.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.LocationCity
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.NearMe
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SportsMotorsports
import androidx.compose.material.icons.filled.SportsScore
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalNav
import win.tbsgaming.tracklap.LocalPermissions
import win.tbsgaming.tracklap.data.AutoLines
import win.tbsgaming.tracklap.data.Catalog
import win.tbsgaming.tracklap.data.FinderBusy
import win.tbsgaming.tracklap.data.Overpass
import win.tbsgaming.tracklap.data.Photon
import win.tbsgaming.tracklap.data.PlaceCandidate
import win.tbsgaming.tracklap.data.TrackCandidate
import win.tbsgaming.tracklap.data.TrackFinder
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.GateLine
import win.tbsgaming.tracklap.model.Geo
import win.tbsgaming.tracklap.model.GeoBox
import win.tbsgaming.tracklap.model.LocalFrame
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.model.TrackLayout
import win.tbsgaming.tracklap.model.Vec
import win.tbsgaming.tracklap.model.nowSeconds
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

object TrackGeometry {
    /** A line across the track where it was tapped: perpendicular to the nearest raceway segment. */
    fun gate(tap: Coord, outline: List<List<Coord>>, width: Double): GateLine? {
        val f = LocalFrame(tap)
        var bestDist = Double.POSITIVE_INFINITY
        var bestP = Vec.ZERO
        var bestDir = Vec.ZERO
        for (way in outline) {
            if (way.size < 2) continue
            for (i in 1 until way.size) {
                val a = f.xy(way[i - 1])
                val b = f.xy(way[i])
                val ab = b - a
                val len2 = ab.dot(ab)
                if (len2 <= 0) continue
                val t = min(1.0, max(0.0, -a.dot(ab) / len2))
                val p = a + ab * t
                if (p.length < bestDist) {
                    bestDist = p.length
                    bestP = p
                    bestDir = ab
                }
            }
        }
        if (bestDist >= 60) return null
        val n = bestDir.normalized.perpendicular * (width / 2)
        return GateLine(f.coord(bestP - n), f.coord(bestP + n))
    }

    /** A line through a point, perpendicular to the direction of travel. */
    fun gate(c: Coord, heading: Double, width: Double): GateLine {
        val f = LocalFrame(c)
        val h = heading * Math.PI / 180
        val n = Vec(sin(h), cos(h)).perpendicular * (width / 2)
        return GateLine(f.coord(n * -1.0), f.coord(n))
    }
}

@Composable
fun TracksScreen() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val permissions = LocalPermissions.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf<Track?>(null) }
    val n = m.tracks.tracks.size
    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            ScreenHeader(Icons.Filled.Map, L("Piste"), if (n == 1) L("1 pista salvata") else L("%lld piste salvate", n))
            PrimaryButton(L("Cerca pista"), Icons.Filled.Search) { nav.push(AppTab.tracks, "search") }
            SecondaryButton(L("Crea qui"), Icons.Filled.MyLocation) {
                if (!m.phone.hasPermission()) {
                    permissions.location()
                    return@SecondaryButton
                }
                scope.launch {
                    busy = true
                    val c = m.phone.currentLocation()
                    if (c == null) {
                        error = L("Posizione non disponibile.")
                    } else {
                        val t = TrackFinder.track(L("Nuova pista"), L("Creata sul posto"), c, GeoBox.around(c, 900.0), false)
                        m.save(t)
                        nav.push(AppTab.tracks, "editor:${t.id}")
                    }
                    busy = false
                }
            }
            SectionLabel(L("Le tue piste"))
            for (t in m.tracks.tracks) {
                TrackCard(t, selected = t.id == m.selectedTrackID, onUse = { m.select(t.id) }, onEdit = { nav.push(AppTab.tracks, "editor:${t.id}") },
                    onBoard = { nav.push(AppTab.tracks, "board:${t.id}") }, onDelete = { confirmDelete = t })
            }
        }
        if (busy) ProgressOverlay(L("Cerco la pista qui intorno…"))
    }
    error?.let { e ->
        AlertDialog(
            onDismissRequest = { error = null }, containerColor = Theme.panel,
            text = { Text(e, color = Theme.text) },
            confirmButton = { TextButton({ error = null }) { Text("OK", color = Theme.accent) } },
        )
    }
    confirmDelete?.let { t ->
        AlertDialog(
            onDismissRequest = { confirmDelete = null }, containerColor = Theme.panel,
            title = { Text(L("Eliminare la pista?"), color = Theme.text) },
            text = { Text(t.name, color = Theme.sub) },
            confirmButton = { TextButton({ m.deleteTrack(t.id); confirmDelete = null }) { Text(L("Elimina"), color = Theme.bad) } },
            dismissButton = { TextButton({ confirmDelete = null }) { Text(L("Annulla"), color = Theme.accent) } },
        )
    }
}

@Composable
private fun TrackCard(track: Track, selected: Boolean, onUse: () -> Unit, onEdit: () -> Unit, onBoard: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(22.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.panel)
            .border(if (selected) 1.5.dp else 1.dp, if (selected) Theme.accent.copy(alpha = 0.7f) else Theme.line.copy(alpha = 0.8f), shape)
            .clickable(onClick = onUse).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(76.dp).clip(RoundedCornerShape(16.dp)).background(Theme.input)) {
            TrackShape(track, Modifier.fillMaxSize(), lineWidth = 2f)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(track.name, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (track.place.isNotEmpty()) Text(track.place, fontSize = 12.sp, color = Theme.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (track.isReady) Badge(L("Pronta"), Theme.good) else Badge(L("Manca il via"), Theme.yellow)
                if (track.sectorCount > 0) Badge(L("%lld settori", track.sectorCount), Theme.purple)
                if (selected) Badge(L("In uso"))
            }
        }
        Box {
            RoundIconButton(Icons.Filled.MoreVert, Theme.sub) { menu = true }
            DropdownMenu(menu, { menu = false }, containerColor = Theme.panel) {
                DropdownMenuItem({ Text(L("Modifica"), color = Theme.text) }, { menu = false; onEdit() }, leadingIcon = { Icon(Icons.Filled.Edit, null, tint = Theme.accent) })
                if (track.isReady && !track.isDemo) {
                    DropdownMenuItem({ Text(L("Classifica online"), color = Theme.text) }, { menu = false; onBoard() }, leadingIcon = { Icon(Icons.Filled.EmojiEvents, null, tint = Theme.yellow) })
                }
                DropdownMenuItem({ Text(L("Elimina"), color = Theme.bad) }, { menu = false; onDelete() }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.bad) })
            }
        }
    }
}

@Composable
fun TrackSearchScreen() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val permissions = LocalPermissions.current
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var found by remember { mutableStateOf<List<TrackCandidate>>(emptyList()) }
    var places by remember { mutableStateOf<List<PlaceCandidate>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var searchFailed by remember { mutableStateOf(false) }
    var near by remember { mutableStateOf<List<TrackCandidate>>(emptyList()) }
    var nearTitle by remember { mutableStateOf<String?>(null) }
    var nearBusy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var downloading by remember { mutableStateOf<String?>(null) }
    var nearJob by remember { mutableStateOf<Job?>(null) }
    val trimmed = query.trim()
    val radius = 50.0

    // A moment after you stop typing; a new letter cancels the search in flight.
    LaunchedEffect(trimmed) {
        if (trimmed.length < 3) {
            found = emptyList()
            places = emptyList()
            searching = false
            return@LaunchedEffect
        }
        delay(400)
        searching = true
        searchFailed = false
        val t = async { runCatching { Photon.tracks(trimmed) }.getOrNull() }
        val p = async { runCatching { Photon.places(trimmed) }.getOrNull() }
        val tracks = t.await()
        val towns = p.await()
        val known = Catalog.matching(trimmed)
        found = TrackFinder.merge(tracks ?: emptyList()).filter { c -> known.none { TrackFinder.same(it, c) } }
        places = towns ?: emptyList()
        searchFailed = tracks == null && towns == null
        searching = false
    }

    fun startNearby(place: PlaceCandidate?) {
        nearJob?.cancel()
        message = null
        near = emptyList()
        nearTitle = place?.let { L("Vicino a %@", it.name) } ?: L("Vicino a te")
        if (place == null && !m.phone.hasPermission()) {
            permissions.location()
            nearTitle = null
            return
        }
        nearBusy = true
        nearJob = scope.launch {
            val center = place?.center ?: m.phone.currentLocation()
            if (center == null) {
                message = L("Posizione non disponibile.")
                nearTitle = null
                nearBusy = false
                return@launch
            }
            val known = Catalog.all.filter { Geo.distance(it.center, center) <= radius * 1000 }
            val quick = Photon.nearby(GeoBox.around(center, radius * 1000))
            near = TrackFinder.sorted(TrackFinder.merge(known + quick), center).filter { (it.distanceKm ?: 0.0) <= radius }
            val full = runCatching { Overpass.nearby(center, radius) }.getOrNull()
            if (full != null) near = TrackFinder.sorted(TrackFinder.merge(known + full + near), center)
            if (near.isEmpty()) message = if (full == null) FinderBusy().message else L("Nessuna pista trovata entro 50 km.")
            nearBusy = false
        }
    }

    fun pick(c: TrackCandidate) {
        scope.launch {
            downloading = L("Scarico il tracciato di %@…", c.name)
            val t = TrackFinder.track(c.name, c.place.ifEmpty { c.kindTitle }, c.center, c.searchBox, c.kind == TrackCandidate.Kind.karting)
            m.save(t)
            m.select(t.id)
            downloading = null
            nav.replaceTop(AppTab.tracks, "editor:${t.id}")
        }
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            TopBar(L("Cerca pista"), onBack = { nav.pop(AppTab.tracks) })
            OutlinedTextField(
                query, { query = it },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                placeholder = { Text(L("Circuito, kartodromo o città"), color = Theme.sub) },
                leadingIcon = { Icon(Icons.Filled.Search, null, tint = Theme.sub) },
                trailingIcon = { if (query.isNotEmpty()) Icon(Icons.Filled.Close, null, tint = Theme.sub, modifier = Modifier.clickable { query = "" }) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                shape = RoundedCornerShape(16.dp),
                colors = fieldColors(),
            )
            LazyColumn(Modifier.fillMaxSize(), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (trimmed.isEmpty()) {
                    item {
                        ListRow(Icons.Filled.NearMe, L("Piste vicino a me"), L("Entro 50 km, da OpenStreetMap"), Theme.accent) { startNearby(null) }
                    }
                }
                message?.let { msg -> item { Text(msg, fontSize = 14.sp, color = Theme.sub, modifier = Modifier.padding(4.dp)) } }
                if (nearTitle != null) {
                    item { SectionLabel(nearTitle ?: "") }
                    if (nearBusy) item { ProgressRow(L("Cerco su OpenStreetMap: a volte i server sono lenti…")) }
                    items(near, key = { "near-" + it.id }) { c -> CandidateRow(c) { pick(c) } }
                }
                item { SectionLabel(if (trimmed.isEmpty()) L("Circuiti famosi") else L("Dal catalogo")) }
                items(Catalog.matching(trimmed), key = { "cat-" + it.id }) { c -> CandidateRow(c) { pick(c) } }
                if (trimmed.length >= 3) {
                    item { SectionLabel(L("Su OpenStreetMap")) }
                    if (searching && found.isEmpty() && places.isEmpty()) item { ProgressRow(L("Cerco…")) }
                    if (!searching && found.isEmpty() && places.isEmpty()) {
                        item {
                            Text(
                                if (searchFailed) L("La ricerca non risponde: controlla la connessione e riprova.")
                                else L("Nessun risultato. Prova con il paese più vicino e scegli «Piste vicino a…»."),
                                fontSize = 14.sp, color = Theme.sub, modifier = Modifier.padding(4.dp),
                            )
                        }
                    }
                    items(found, key = { "osm-" + it.id }) { c -> CandidateRow(c) { pick(c) } }
                    items(places, key = { "place-" + it.id }) { p ->
                        ListRow(Icons.Filled.LocationCity, L("Piste vicino a %@", p.name), p.detail, Theme.yellow) { startNearby(p) }
                    }
                }
            }
        }
        downloading?.let { ProgressOverlay(it) }
    }
}

@Composable
fun fieldColors() = OutlinedTextFieldDefaults.colors(
    focusedTextColor = Theme.text, unfocusedTextColor = Theme.text,
    focusedContainerColor = Theme.input, unfocusedContainerColor = Theme.input,
    focusedBorderColor = Theme.accent, unfocusedBorderColor = Theme.line, cursorColor = Theme.accent,
)

@Composable
private fun CandidateRow(c: TrackCandidate, onClick: () -> Unit) {
    ListRow(if (c.kind == TrackCandidate.Kind.karting) Icons.Filled.SportsMotorsports else Icons.Filled.SportsScore, c.name, c.subtitle, Theme.accent, onClick)
}

@Composable
fun ListRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String, tint: Color, onClick: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.panel).clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, color = Theme.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (subtitle.isNotEmpty()) Text(subtitle, fontSize = 12.sp, color = Theme.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Icon(Icons.Filled.ChevronRight, null, tint = Theme.sub, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun ProgressRow(text: String) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Theme.panel).padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        CircularProgressIndicator(color = Theme.accent, modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
        Text(text, fontSize = 14.sp, color = Theme.sub)
    }
}

private enum class Tool { start, sector }

/** The track on satellite imagery: tap to put the start line and the intermediates, pick a layout. */
@Composable
fun TrackEditorScreen(trackID: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val track = m.tracks.track(trackID)
    var tool by remember { mutableStateOf(if (track?.start == null) Tool.start else Tool.sector) }
    var width by remember { mutableStateOf(track?.start?.width?.let { max(8.0, min(60.0, it.roundToInt().toDouble())) } ?: 24.0) }
    var pending by remember { mutableStateOf<Coord?>(null) }
    var hint by remember { mutableStateOf<String?>(null) }
    var placing by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }
    var layoutMenu by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    var confirmDelete by remember { mutableStateOf(false) }
    var frameKey by remember { mutableStateOf<Any>(trackID) }
    if (track == null) {
        LaunchedEffect(Unit) { nav.pop(AppTab.tracks) }
        return
    }

    fun update(change: (Track) -> Track) {
        val t = m.tracks.track(trackID) ?: return
        m.save(change(t))
    }

    fun place(gate: GateLine) {
        when (tool) {
            Tool.start -> {
                update { it.copy(start = gate, autoLines = null).keepLinesInLayout() }
                hint = L("Linea del via messa. Ora aggiungi gli intermedi, se vuoi.")
                tool = Tool.sector
            }
            Tool.sector -> {
                if (track.sectors.size >= 4) {
                    hint = L("Massimo 4 intermedi.")
                    return
                }
                update { it.copy(sectors = it.sectors + gate, autoLines = null).keepLinesInLayout() }
                hint = null
            }
        }
        haptic(view)
    }

    fun tap(c: Coord) {
        val p = pending
        val gate = if (p != null) {
            pending = null
            GateLine(p, c)
        } else {
            TrackGeometry.gate(c, track.outline, width) ?: run {
                pending = c
                hint = null
                return
            }
        }
        place(gate)
    }

    fun autoPlace() {
        scope.launch {
            placing = true
            val pts = track.outline.flatten()
            val box = if (pts.isNotEmpty()) GeoBox(pts.minOf { it.lat }, pts.minOf { it.lon }, pts.maxOf { it.lat }, pts.maxOf { it.lon }).padded(150.0)
            else GeoBox.around(track.center, 1500.0)
            val data = TrackFinder.raceways(box)
            if (data == null) {
                hint = L("OpenStreetMap non risponde in questo momento: riprova tra poco.")
                placing = false
                return@launch
            }
            val w = width
            val found = withContext(Dispatchers.Default) { AutoLines.layouts(data, w) }
            if (found.isEmpty()) {
                hint = L("Su OpenStreetMap non trovo un giro chiuso qui: metti il via toccando la mappa.")
                placing = false
                return@launch
            }
            update { t -> (if (t.outline.isEmpty()) t.copy(outline = data.outline) else t).applyAuto(found) }
            hint = null
            tool = Tool.sector
            frameKey = nowSeconds()
            placing = false
            haptic(view, true)
        }
    }

    fun markHere() {
        scope.launch {
            var coord: Coord? = null
            var heading: Double? = null
            val p = m.engine.position
            val w = m.lastFixWall
            if (p != null && w != null && nowSeconds() - w < 3) {
                coord = p
                if (m.engine.speed > 2) heading = m.engine.heading
            } else {
                coord = m.phone.currentLocation()
            }
            val here = coord
            if (here == null) {
                hint = L("Posizione non disponibile.")
                return@launch
            }
            val h = heading
            val gate = if (h != null) TrackGeometry.gate(here, h, width) else TrackGeometry.gate(here, track.outline, width)
            if (gate == null) {
                hint = L("Sei lontano dal tracciato: fermati sulla linea e riprova, oppure tocca la mappa.")
                return@launch
            }
            place(gate)
        }
    }

    val defaultHint = when {
        pending != null -> L("Tocca l'altro lato della pista.")
        tool == Tool.start && track.outline.isEmpty() -> L("Nessun tracciato su OpenStreetMap: tocca i due lati della pista per il via.")
        tool == Tool.start -> if (track.start == null) L("Tocca la pista nel punto del traguardo.") else L("Tocca di nuovo per spostare il via.")
        track.sectors.size < 4 -> L("Tocca la pista per aggiungere un intermedio (%lld/4).", track.sectors.size)
        else -> L("Hai già 4 intermedi: toccane uno sotto per toglierlo.")
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            TopBar(track.name, onBack = { nav.pop(AppTab.tracks) }) {
                Box {
                    RoundIconButton(Icons.Filled.MoreVert) { menu = true }
                    DropdownMenu(menu, { menu = false }, containerColor = Theme.panel) {
                        DropdownMenuItem({ Text(L("Rinomina"), color = Theme.text) }, { menu = false; newName = track.name; renaming = true }, leadingIcon = { Icon(Icons.Filled.Edit, null, tint = Theme.accent) })
                        DropdownMenuItem({ Text(L("Via e intermedi automatici"), color = Theme.text) }, { menu = false; autoPlace() }, leadingIcon = { Icon(Icons.Filled.AutoAwesome, null, tint = Theme.accent) })
                        DropdownMenuItem({ Text(L("Togli gli intermedi"), color = Theme.text) }, { menu = false; update { it.copy(sectors = emptyList(), autoLines = null).keepLinesInLayout() } }, leadingIcon = { Icon(Icons.Filled.RemoveCircle, null, tint = Theme.yellow) })
                        DropdownMenuItem({ Text(L("Togli la linea del via"), color = Theme.text) }, { menu = false; update { it.copy(start = null, autoLines = null) }; tool = Tool.start }, leadingIcon = { Icon(Icons.Filled.Flag, null, tint = Theme.yellow) })
                        DropdownMenuItem({ Text(L("Elimina pista"), color = Theme.bad) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.bad) })
                    }
                }
            }
            val lines = trackLines(track.outline, track.start, track.sectors) +
                listOfNotNull(pending?.let { MapLine(listOf(it, it), Theme.accent, 10f) })
            SatelliteMap(
                Modifier.fillMaxWidth().weight(1f), frame = track.allPoints.ifEmpty { listOf(track.center) }, frameKey = frameKey,
                lines = lines, dots = listOfNotNull(pending?.let { MapDot(it, Theme.accent, 6f) }, m.engine.position?.let { MapDot(it, Theme.blue, 6f) }),
                interactive = true, minMeters = 500.0, onTap = { tap(it) },
            )
            Column(Modifier.fillMaxWidth().background(Theme.bg).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                val layouts = track.layouts
                if (layouts != null && layouts.size > 1) {
                    val index = layouts.indexOfFirst { it.key == track.activeLayout }.coerceAtLeast(0)
                    Box {
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Theme.panel).clickable { layoutMenu = true }.padding(horizontal = 12.dp, vertical = 9.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(Icons.Filled.Route, null, tint = Theme.accent, modifier = Modifier.size(18.dp))
                            Text(layouts[index].title(index), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Theme.text, maxLines = 1, modifier = Modifier.weight(1f))
                            Text(L("Tracciato"), fontSize = 13.sp, color = Theme.sub)
                            Icon(Icons.Filled.UnfoldMore, null, tint = Theme.sub, modifier = Modifier.size(16.dp))
                        }
                        DropdownMenu(layoutMenu, { layoutMenu = false }, containerColor = Theme.panel) {
                            for ((i, l) in layouts.withIndex()) {
                                DropdownMenuItem(
                                    { Text(l.title(i), color = Theme.text) },
                                    {
                                        layoutMenu = false
                                        update { it.use(l) }
                                        width = max(8.0, min(60.0, l.start.width.roundToInt().toDouble()))
                                    },
                                    leadingIcon = { if (i == index) Icon(Icons.Filled.Check, null, tint = Theme.accent) },
                                )
                            }
                        }
                    }
                }
                if (track.outline.isEmpty() && track.start == null) {
                    PrimaryButton(L("Scarica il tracciato"), Icons.Filled.Download) { autoPlace() }
                }
                track.autoLines?.let { src ->
                    Note(Icons.Filled.AutoAwesome, Theme.accent, when (src) {
                        TrackLayout.Source.mapped -> L("Via sul traguardo segnato su OpenStreetMap, intermedi a un terzo e a due terzi del giro.")
                        TrackLayout.Source.pits -> L("Via messo accanto ai box, dove di solito è il traguardo: controllalo. Intermedi a un terzo e a due terzi del giro.")
                        TrackLayout.Source.named -> L("Via sul rettilineo di partenza: controllalo. Intermedi a un terzo e a due terzi del giro.")
                        TrackLayout.Source.straight -> L("Via sul rettilineo più lungo: spostalo se il traguardo è altrove. Intermedi a un terzo e a due terzi del giro.")
                    })
                }
                Text(hint ?: defaultHint, fontSize = 13.sp, color = Theme.sub)
                // Which line a tap puts.
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Theme.input).padding(3.dp)) {
                    for (t in Tool.entries) {
                        val on = tool == t
                        Text(
                            if (t == Tool.start) L("Linea del via") else L("Intermedio"),
                            fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (on) Theme.text else Theme.sub,
                            modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(if (on) Theme.button else Color.Transparent)
                                .clickable { tool = t; pending = null }.padding(vertical = 8.dp),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        )
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Slider(
                        width.toFloat(), { width = it.roundToInt().toDouble() }, Modifier.weight(1f), valueRange = 8f..60f,
                        onValueChangeFinished = {
                            val w = width
                            update { t -> t.copy(start = t.start?.resized(w), sectors = t.sectors.map { it.resized(w) }).keepLinesInLayout() }
                        },
                        colors = SliderDefaults.colors(thumbColor = Theme.accent, activeTrackColor = Theme.accent, inactiveTrackColor = Theme.line),
                    )
                    Text("${width.toInt()} m", style = Theme.numStyle(12.sp, FontWeight.Bold, Theme.sub))
                }
                if (track.sectors.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for ((i, _) in track.sectors.withIndex()) {
                            Row(
                                Modifier.clip(RoundedCornerShape(12.dp)).background(Theme.yellow.copy(alpha = 0.14f))
                                    .clickable { update { t -> t.copy(sectors = t.sectors.filterIndexed { k, _ -> k != i }, autoLines = null).keepLinesInLayout() } }
                                    .padding(horizontal = 10.dp, vertical = 6.dp),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Icon(Icons.Filled.Close, null, tint = Theme.yellow, modifier = Modifier.size(14.dp))
                                Text("I${i + 1}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Theme.yellow)
                            }
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SecondaryButton(L("Segna qui"), Icons.Filled.MyLocation, modifier = Modifier.weight(1f)) { markHere() }
                    PrimaryButton(if (m.selectedTrackID == track.id) L("In uso") else L("Usa pista"), Icons.Filled.Check, modifier = Modifier.weight(1f)) {
                        m.select(track.id)
                        haptic(view, true)
                    }
                }
            }
        }
        if (placing) ProgressOverlay(L("Cerco il traguardo su OpenStreetMap…"))
    }
    if (renaming) {
        AlertDialog(
            onDismissRequest = { renaming = false }, containerColor = Theme.panel,
            title = { Text(L("Rinomina pista"), color = Theme.text) },
            text = { OutlinedTextField(newName, { newName = it }, singleLine = true, label = { Text(L("Nome")) }, colors = fieldColors()) },
            confirmButton = {
                TextButton({
                    val n = newName.trim()
                    if (n.isNotEmpty()) update { it.copy(name = n) }
                    renaming = false
                }) { Text(L("Salva"), color = Theme.accent) }
            },
            dismissButton = { TextButton({ renaming = false }) { Text(L("Annulla"), color = Theme.sub) } },
        )
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false }, containerColor = Theme.panel,
            title = { Text(L("Eliminare la pista?"), color = Theme.text) },
            confirmButton = {
                TextButton({
                    confirmDelete = false
                    m.deleteTrack(trackID)
                    nav.pop(AppTab.tracks)
                }) { Text(L("Elimina"), color = Theme.bad) }
            },
            dismissButton = { TextButton({ confirmDelete = false }) { Text(L("Annulla"), color = Theme.accent) } },
        )
    }
}
