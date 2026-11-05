package win.tbsgaming.tracklap.ui

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SportsScore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalNav
import win.tbsgaming.tracklap.SourceKind
import win.tbsgaming.tracklap.data.FriendLap
import win.tbsgaming.tracklap.data.Leaderboard
import win.tbsgaming.tracklap.data.Server
import win.tbsgaming.tracklap.data.SessionLap
import win.tbsgaming.tracklap.model.Lap
import win.tbsgaming.tracklap.model.Session
import win.tbsgaming.tracklap.model.SharedLap
import win.tbsgaming.tracklap.model.nowSeconds
import win.tbsgaming.tracklap.multiplayer.GroupSession
import java.io.File
import java.util.Locale

/** The colours of the cars of a live group, in the order they joined. */
object GroupColors {
    private val all = listOf(Color(0xFFF472B6), Color(0xFFFB923C), Color(0xFFA3E635), Color(0xFF60A5FA), Color(0xFFC084FC), Color(0xFF2DD4BF), Color(0xFFFACC15))
    fun color(i: Int) = all[((i % all.size) + all.size) % all.size]
}

/** External GPS or phone: how a time on the leaderboard was set. */
@Composable
fun GpsBadge(source: String) {
    when (source) {
        "device" -> Badge(L("GPS esterno"), Theme.good)
        "phone" -> Badge(L("Telefono"), Theme.yellow)
    }
}

private enum class BoardFilter { all, device, phone }

/** The online leaderboard of a track: the best time of every driver, with the GPS it was set with and a link to the car. */
@Composable
fun LeaderboardScreen(trackID: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val track = m.tracks.track(trackID)
    var board by remember { mutableStateOf<Leaderboard?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var filter by remember { mutableStateOf(BoardFilter.all) }
    var attempt by remember { mutableStateOf(0) }
    var note by remember { mutableStateOf<String?>(null) }
    var sending by remember { mutableStateOf(false) }
    LaunchedEffect(trackID, attempt) {
        if (track == null) return@LaunchedEffect
        error = null
        runCatching { Server.board(track, track.length, m.account.token) }.onSuccess { board = it }.onFailure { error = it.message }
    }
    val record: SessionLap? = remember(trackID, m.sessions.summaries) {
        m.sessions.summaries.filter { it.trackID == trackID && it.best != null && SourceKind.ofSession(it.source) != SourceKind.demo }
            .minByOrNull { it.best ?: Double.MAX_VALUE }?.let { s -> m.sessions.load(s.id)?.best?.let { SessionLap(it, s) } }
    }
    Column(Modifier.fillMaxSize()) {
        TopBar(L("Classifica online"), onBack = { nav.pop(AppTab.tracks) }) {
            RoundIconButton(Icons.Filled.Refresh) { attempt += 1 }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(board?.track?.name ?: track?.name ?: "", fontSize = 22.sp, fontWeight = FontWeight.Black, color = Theme.text)
            Segmented(listOf(L("Tutti") to BoardFilter.all, L("GPS esterno") to BoardFilter.device, L("Telefono") to BoardFilter.phone), filter) { filter = it }
            Text(L("Il GPS esterno a 10 Hz misura al centesimo, quello dell'iPhone a 1 Hz è meno preciso: per questo ogni tempo dice con quale è stato fatto."), fontSize = 12.sp, color = Theme.sub)
            when {
                error != null -> {
                    Text(error ?: "", fontSize = 14.sp, color = Theme.sub)
                    SecondaryButton(L("Riprova"), Icons.Filled.Refresh) { attempt += 1 }
                }
                board == null -> Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Theme.accent) }
                else -> {
                    val laps = board!!.laps.filter { filter == BoardFilter.all || it.source == filter.name }
                    if (laps.isEmpty()) {
                        Panel {
                            Text(L("Ancora nessun tempo qui"), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                            Text(L("Il primo giro pubblicato su questa pista apre la classifica."), fontSize = 13.sp, color = Theme.sub)
                        }
                    } else {
                        Panel(padding = 4.dp) {
                            for ((i, e) in laps.withIndex()) {
                                BoardRow(if (filter == BoardFilter.all) i + 1 else e.rank, e) { e.carLink?.let { m.shownGarage = it } }
                                if (i < laps.size - 1) Hairline()
                            }
                        }
                    }
                }
            }
            SectionLabel(L("I tuoi giri"))
            Panel {
                if (!m.account.isSignedIn) {
                    Text(L("Per entrare in classifica serve un account: il tuo nome utente è quello che vedono tutti, accanto al tempo e all'auto."), fontSize = 13.sp, color = Theme.sub)
                    Spacer(Modifier.height(10.dp))
                    PrimaryButton(L("Accedi o crea un account"), Icons.Filled.Person) { nav.push(AppTab.tracks, "account") }
                } else {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(L("Pubblica i miei best"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
                            Text(L("Il giro migliore di ogni sessione va nella classifica della sua pista, come %@. Mai i giri della Demo.", m.account.name ?: ""), fontSize = 12.sp, color = Theme.sub)
                        }
                        Switch(m.profile.publishLaps, { m.profile.setPublish(it) }, colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Color.Black))
                    }
                    val car = m.activeCar
                    Spacer(Modifier.height(8.dp))
                    Text(
                        when {
                            car == null -> L("Scegli in Live l'auto che usi: i tuoi tempi porteranno a lei.")
                            m.garage.isShown -> L("I tuoi tempi portano a quest'auto del garage")
                            else -> L("Rendi pubblico il garage perché i tempi portino all'auto")
                        },
                        fontSize = 12.sp, color = Theme.sub,
                    )
                    if (record != null && track != null) {
                        Spacer(Modifier.height(10.dp))
                        SecondaryButton(L("Invia il mio record: %@", Fmt.lap(record.lap.time)), Icons.Filled.Send, enabled = !sending) {
                            val token = m.account.token ?: return@SecondaryButton
                            sending = true
                            scope.launch {
                                val kind = SourceKind.ofSession(record.session.source)
                                runCatching { Server.submit(record.lap, kind.name, track, record.session.carID, token) }
                                    .onSuccess { r ->
                                        note = L("Sei %lld° su %lld con %@.", r.rank, r.of, if (kind == SourceKind.device) L("GPS esterno") else L("Telefono"))
                                        attempt += 1
                                    }
                                    .onFailure { note = it.message }
                                sending = false
                            }
                        }
                    }
                    note?.let { Text(it, fontSize = 13.sp, color = Theme.good, modifier = Modifier.padding(top = 8.dp)) }
                }
            }
        }
    }
}

@Composable
private fun BoardRow(rank: Int, e: Leaderboard.Entry, open: () -> Unit) {
    val link = e.carLink
    Row(
        Modifier.fillMaxWidth().background(if (e.mine) Theme.accent.copy(alpha = 0.08f) else Color.Transparent)
            .clickable(enabled = link != null, onClick = open).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val medal = when (rank) {
            1 -> Theme.yellow
            2 -> Color(0xFFC0C0C8)
            3 -> Color(0xFFCD7F32)
            else -> null
        }
        Box(Modifier.size(30.dp).clip(CircleShape).background((medal ?: Theme.input).copy(alpha = if (medal != null) 0.2f else 1f)), contentAlignment = Alignment.Center) {
            Text("$rank", fontSize = 13.sp, fontWeight = FontWeight.Black, color = medal ?: Theme.text)
        }
        Column(Modifier.weight(1f)) {
            Text(if (e.mine) L("%@ (tu)", e.name) else e.name, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                GpsBadge(e.source)
                if (e.vehicle.isNotEmpty()) {
                    if (link != null) Icon(Icons.Filled.DirectionsCar, null, tint = Theme.accent, modifier = Modifier.size(12.dp))
                    Text(e.vehicle, fontSize = 11.sp, color = if (link != null) Theme.accent else Theme.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(Fmt.lap(e.time), style = Theme.numStyle(17.sp, FontWeight.Black, if (rank == 1) Theme.purple else Theme.text))
            Text(Fmt.dayShort(e.date / 1000), fontSize = 10.sp, color = Theme.sub)
        }
        if (link != null) Icon(Icons.Filled.ChevronRight, null, tint = Theme.sub, modifier = Modifier.size(16.dp))
    }
}

/** A QR code as a bitmap, white on black like the app. */
fun qrBitmap(text: String, size: Int = 512): Bitmap {
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    for (x in 0 until size) for (y in 0 until size) bmp.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
    return bmp
}

/** The live group in Live: create or join one, then the standings, the gaps on track and the invitation. */
@Composable
fun MultiplayerCard() {
    val m = LocalModel.current
    val g = m.group
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val nav = LocalNav.current
    var dialog by remember { mutableStateOf<String?>(null) }
    var showQR by remember { mutableStateOf(false) }
    val signedIn = m.account.isSignedIn
    // Groups need an account: Crea or Entra first asks you to sign in, then carries on by itself.
    var afterSignIn by rememberSaveable { mutableStateOf<String?>(null) }
    var askSignIn by remember { mutableStateOf(false) }
    fun start(kind: String) {
        if (signedIn) dialog = kind else {
            afterSignIn = kind
            askSignIn = true
        }
    }
    LaunchedEffect(signedIn) {
        if (!signedIn) return@LaunchedEffect
        afterSignIn?.let { dialog = it; afterSignIn = null }
        m.pendingJoin?.let { c ->
            m.pendingJoin = null
            g.join(c, m.selectedTrack)
        }
    }
    val code = g.code
    Panel(glow = if (g.status == GroupSession.Status.live) Theme.purple else null) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.Groups, null, tint = Theme.purple, modifier = Modifier.size(22.dp))
            Text(if (code == null) L("Gruppo live") else L("GRUPPO") + " $code", fontSize = 15.sp, fontWeight = FontWeight.Black, color = Theme.text, modifier = Modifier.weight(1f))
            if (code != null) Text(
                when (g.status) {
                    GroupSession.Status.live -> L("Collegato")
                    else -> L("Collegamento…")
                },
                fontSize = 12.sp, color = if (g.status == GroupSession.Status.live) Theme.good else Theme.yellow,
            )
        }
        Spacer(Modifier.height(8.dp))
        if (code == null) {
            Text(L("Tempi, distacchi e posizioni degli amici in pista, in diretta."), fontSize = 13.sp, color = Theme.sub)
            g.problem?.let { Text(it, fontSize = 13.sp, color = Theme.bad, modifier = Modifier.padding(top = 6.dp)) }
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PrimaryButton(L("Crea"), Icons.Filled.PersonAdd, Theme.purple, modifier = Modifier.weight(1f)) { start("create") }
                SecondaryButton(L("Entra"), Icons.Filled.Groups, Theme.purple, modifier = Modifier.weight(1f)) { start("join") }
            }
        } else {
            val rows = g.standings
            if (rows.size <= 1) Text(L("Nessun altro qui per ora: invita gli amici con il QR."), fontSize = 13.sp, color = Theme.sub)
            for ((i, r) in rows.withIndex()) {
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("${i + 1}", style = Theme.numStyle(14.sp, FontWeight.Black, Theme.sub), modifier = Modifier.width(18.dp))
                    Box(Modifier.size(10.dp).clip(CircleShape).background(r.color?.let { GroupColors.color(it) } ?: Theme.accent))
                    Column(Modifier.weight(1f)) {
                        Text(if (r.isMe) L("%@ (tu)", r.name) else r.name, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = if (r.online) Theme.text else Theme.sub, maxLines = 1)
                        Text(
                            listOfNotNull(
                                r.vehicle.ifEmpty { null },
                                r.last?.let { L("ultimo %@", Fmt.lap(it)) },
                                if (!r.online) L("non in linea") else null,
                                if (r.laps == 0) L("ancora nessun giro") else if (r.laps == 1) L("1 giro") else L("%lld giri", r.laps),
                            ).joinToString(" · "),
                            fontSize = 11.sp, color = Theme.sub, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                    Text(Fmt.lap(r.best), style = Theme.numStyle(15.sp, FontWeight.Black, if (i == 0 && r.best != null) Theme.purple else Theme.text))
                }
            }
            val length = m.selectedTrack?.length ?: 0.0
            val (ahead, behind) = g.trackGaps(length)
            ahead?.let { Text(L("%@ davanti di %@ s", it.name, String.format(Locale.US, "%.1f", it.seconds)), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = GroupColors.color(it.color)) }
            behind?.let { Text(L("%@ dietro di %@ s", it.name, String.format(Locale.US, "%.1f", it.seconds)), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = GroupColors.color(it.color)) }
            if (g.elsewhere.isNotEmpty()) Text(L("Su un'altra pista: %@", g.elsewhere.joinToString(", ") { it.name }), fontSize = 12.sp, color = Theme.sub)
            Spacer(Modifier.height(10.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SecondaryButton(L("Invita"), Icons.Filled.Share, Theme.purple, modifier = Modifier.weight(1f)) { showQR = true }
                SecondaryButton(L("Esci dal gruppo"), Icons.Filled.Logout, Theme.bad, modifier = Modifier.weight(1f)) { g.leave() }
            }
        }
    }
    when (dialog) {
        "create" -> GroupDialog(create = true, done = { dialog = null }) {
            scope.launch {
                runCatching { g.create(m.selectedTrack) }.onFailure { g.problem = it.message }
            }
        }
        "join" -> GroupDialog(create = false, done = { dialog = null }) { c -> g.join(c, m.selectedTrack) }
    }
    val invite = m.pendingJoin
    if (!signedIn && (askSignIn || invite != null)) {
        val cancel = {
            askSignIn = false
            afterSignIn = null
            m.pendingJoin = null
        }
        AlertDialog(
            onDismissRequest = cancel, containerColor = Theme.panel,
            title = { Text(L("Serve un account"), color = Theme.text) },
            text = {
                Text(
                    if (invite != null) L("Ti hanno invitato nel gruppo %@. Accedi o crea un account e ci entri subito.", invite)
                    else L("Per creare un gruppo live o entrarci devi prima accedere. Dopo l'accesso torni qui e continui."),
                    fontSize = 13.sp, color = Theme.sub,
                )
            },
            confirmButton = {
                TextButton({
                    askSignIn = false
                    nav.push(AppTab.live, "account")
                }) { Text(L("Accedi o crea un account"), color = Theme.purple) }
            },
            dismissButton = { TextButton(cancel) { Text(L("Annulla"), color = Theme.sub) } },
        )
    }
    if (showQR && code != null) {
        val qr = remember(code) { qrBitmap(GroupSession.inviteURL(code)) }
        AlertDialog(
            onDismissRequest = { showQR = false }, containerColor = Theme.panel,
            title = { Text(L("GRUPPO") + " $code", color = Theme.text) },
            text = {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Image(qr.asImageBitmap(), null, Modifier.size(220.dp).clip(RoundedCornerShape(12.dp)))
                    Text(code, style = Theme.timeStyle(36.sp, Theme.purple))
                    Text(L("Gli amici inquadrano il QR con la Fotocamera dell'iPhone, oppure aprono TrackLap e scrivono il codice."), fontSize = 12.sp, color = Theme.sub)
                }
            },
            confirmButton = {
                TextButton({ shareText(context, L("Entra nel mio gruppo TrackLap, codice %@", code) + "\n" + GroupSession.inviteURL(code)) }) {
                    Text(L("Invita"), color = Theme.purple)
                }
            },
            dismissButton = { TextButton({ showQR = false }) { Text(L("Fine"), color = Theme.sub) } },
        )
    }
}

@Composable
private fun GroupDialog(create: Boolean, done: () -> Unit, go: (String) -> Unit) {
    val m = LocalModel.current
    var code by remember { mutableStateOf("") }
    var name by remember { mutableStateOf(m.profile.name.ifBlank { m.account.name ?: "" }) }
    val ready = name.isNotBlank() && (create || GroupSession.clean(code).length == 5)
    AlertDialog(
        onDismissRequest = done, containerColor = Theme.panel,
        title = { Text(if (create) L("Nuovo gruppo") else L("Entra in un gruppo"), color = Theme.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    if (create) L("Gli amici entrano con il codice o inquadrando il QR: ognuno vede tempi, distacchi e posizione degli altri sulla mappa.")
                    else L("Scrivi il codice di cinque caratteri di chi ha creato il gruppo, oppure inquadra il suo QR con la Fotocamera."),
                    fontSize = 13.sp, color = Theme.sub,
                )
                if (!create) OutlinedTextField(
                    code, { code = GroupSession.clean(it) }, Modifier.fillMaxWidth(), singleLine = true, label = { Text(L("Codice")) },
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters), colors = fieldColors(),
                )
                OutlinedTextField(name, { name = it.take(24) }, Modifier.fillMaxWidth(), singleLine = true, label = { Text(L("Il tuo nome")) }, colors = fieldColors())
                if (name.isBlank()) Text(L("Scrivi il tuo nome: è quello che vedranno gli amici."), fontSize = 12.sp, color = Theme.yellow)
                Text(L("In pista serve la connessione dati. I tempi li calcola sempre il tuo telefono: la rete serve solo a mandarli agli altri."), fontSize = 12.sp, color = Theme.sub)
            }
        },
        confirmButton = {
            TextButton({
                m.profile.setName(name)
                done()
                go(code)
            }, enabled = ready) { Text(if (create) L("Crea il gruppo") else L("Entra"), color = Theme.purple) }
        },
        dismissButton = { TextButton(done) { Text(L("Annulla"), color = Theme.sub) } },
    )
}

/** The laps friends sent: chase one in Live, or delete it. */
@Composable
fun FriendLapsScreen() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val laps = m.friends.laps
    Column(Modifier.fillMaxSize()) {
        TopBar(L("Giri degli amici"), onBack = { nav.pop(AppTab.sessions) })
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (laps.isEmpty()) {
                Panel(padding = 20.dp) {
                    Text(L("Ancora nessun giro degli amici"), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                    Spacer(Modifier.height(6.dp))
                    Text(L("Chiedi a un amico di aprire una sua sessione e toccare Condividi il giro migliore: il file .tracklap che ti manda si apre con TrackLap e finisce qui."), fontSize = 13.sp, color = Theme.sub)
                }
            }
            for ((track, list) in laps.groupBy { it.trackName }) {
                SectionLabel(track)
                for (f in list.sortedBy { it.time }) FriendRow(f)
            }
        }
    }
}

@Composable
private fun FriendRow(f: FriendLap) {
    val m = LocalModel.current
    val chasing = m.challenge?.id == f.id
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.panel).border(1.dp, if (chasing) Theme.yellow.copy(alpha = 0.6f) else Theme.line.copy(alpha = 0.8f), shape).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(f.driver, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1)
            Text(listOfNotNull(f.vehicle.ifEmpty { null }, f.sourceTitle, Fmt.dayShort(f.date)).joinToString(" · "), fontSize = 12.sp, color = Theme.sub, maxLines = 1)
            Spacer(Modifier.height(4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (chasing) Badge(L("In sfida"), Theme.yellow)
            }
        }
        Text(Fmt.lap(f.time), style = Theme.numStyle(17.sp, FontWeight.Black, Theme.yellow))
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(L("Sfida"), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Theme.accent, modifier = Modifier.clickable { m.chase(f) })
            Icon(Icons.Filled.Delete, L("Elimina"), tint = Theme.bad, modifier = Modifier.size(20.dp).clickable { m.deleteFriendLap(f.id) })
        }
    }
}

/** A lap of yours as a .tracklap file for a friend: the share sheet, after your name is there. */
fun shareLap(context: Context, session: Session, lap: Lap, driver: String, vehicle: String, track: win.tbsgaming.tracklap.model.Track) {
    val shared = SharedLap(driver = driver, vehicle = vehicle, source = SourceKind.ofSession(session.source).name, date = nowSeconds(), track = track, lap = lap)
    val f = shared.write(File(context.cacheDir, "exports"))
    val uri = FileProvider.getUriForFile(context, context.packageName + ".files", f)
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "application/octet-stream"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, f.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** Before sharing a lap: your name, which the friend sees. */
@Composable
fun ShareLapDialog(session: Session, lap: Lap, done: () -> Unit) {
    val m = LocalModel.current
    val context = LocalContext.current
    var name by remember { mutableStateOf(m.profile.name) }
    val track = session.trackID?.let { m.tracks.track(it) }
    AlertDialog(
        onDismissRequest = done, containerColor = Theme.panel,
        title = { Text(L("Condividi il giro"), color = Theme.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(L("Giro %lld", lap.number) + " · " + Fmt.lap(lap.time), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                if (track?.start == null) {
                    Text(L("La pista di questa sessione non c'è più: senza la sua linea del via il giro non si può condividere."), fontSize = 13.sp, color = Theme.yellow)
                } else {
                    Text(L("Chi lo riceve lo apre con TrackLap: lo sfida in Live, anche sul cruscotto dell'ESP32, e lo confronta curva per curva nell'analisi."), fontSize = 13.sp, color = Theme.sub)
                    OutlinedTextField(name, { name = it.take(24) }, Modifier.fillMaxWidth(), singleLine = true, label = { Text(L("Il tuo nome")) }, colors = fieldColors())
                    if (name.isBlank()) Text(L("Scrivi il tuo nome: è quello che vedranno gli amici."), fontSize = 12.sp, color = Theme.yellow)
                }
            }
        },
        confirmButton = {
            TextButton({
                if (track?.start == null) return@TextButton
                m.profile.setName(name)
                shareLap(context, session, lap, m.profile.displayName, session.carName ?: m.profile.displayVehicle, track)
                done()
            }, enabled = track?.start != null && name.isNotBlank()) { Text(L("Invia il giro"), color = Theme.accent) }
        },
        dismissButton = { TextButton(done) { Text(L("Annulla"), color = Theme.sub) } },
    )
}

