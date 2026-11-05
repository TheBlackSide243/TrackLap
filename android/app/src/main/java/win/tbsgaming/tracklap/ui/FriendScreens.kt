package win.tbsgaming.tracklap.ui

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonAdd
import androidx.compose.material.icons.filled.PersonRemove
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalNav
import win.tbsgaming.tracklap.data.FriendStore
import win.tbsgaming.tracklap.data.Server
import win.tbsgaming.tracklap.data.ServerFailure
import win.tbsgaming.tracklap.model.Friend
import win.tbsgaming.tracklap.model.FriendProfile
import win.tbsgaming.tracklap.model.PublicGarage

/**
 * The Friends tab: the drivers you are friends with, and your invitation link. Whoever opens the
 * link in TrackLap becomes your friend, and you theirs; friends see each other's garage (also one
 * shown to friends only), their best lap on every track and a few numbers. Setups never go online.
 */
@Composable
fun FriendsScreen() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val store = m.friendList
    var removing by remember { mutableStateOf<Friend?>(null) }
    // Asked again every time the tab opens.
    LaunchedEffect(m.account.name) { store.refresh() }
    val n = store.friends.size
    val subtitle = when {
        !m.account.isSignedIn -> L("Garage e tempi dei tuoi amici")
        n == 0 -> L("Ancora nessun amico")
        n == 1 -> L("1 amico")
        else -> L("%lld amici", n)
    }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ScreenHeader(Icons.Filled.People, L("Amici"), subtitle)
        if (!m.account.isSignedIn) {
            Panel(padding = 20.dp) {
                Icon(Icons.Filled.People, null, tint = Theme.accent, modifier = Modifier.size(28.dp))
                Spacer(Modifier.height(8.dp))
                Text(L("Garage e tempi dei tuoi amici"), fontSize = 18.sp, fontWeight = FontWeight.Black, color = Theme.text)
                Spacer(Modifier.height(6.dp))
                Text(
                    L("Con un account TrackLap mandi un invito ai tuoi amici: quando lo aprono vedete i garage, i giri migliori su ogni pista e le statistiche l'uno dell'altro."),
                    fontSize = 13.sp, color = Theme.sub,
                )
                Spacer(Modifier.height(12.dp))
                PrimaryButton(L("Accedi o crea un account"), Icons.Filled.Person) { nav.push(AppTab.friends, "account") }
            }
            return@Column
        }
        InvitePanel()
        SectionLabel(L("I tuoi amici"))
        if (store.friends.isEmpty()) {
            when (val s = store.state) {
                FriendStore.Load.Idle, FriendStore.Load.Loading ->
                    Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Theme.accent) }
                is FriendStore.Load.Failed -> Panel {
                    Text(s.message, fontSize = 14.sp, color = Theme.yellow)
                    Spacer(Modifier.height(10.dp))
                    SecondaryButton(L("Riprova"), Icons.Filled.Refresh, Theme.yellow) { scope.launch { store.refresh() } }
                }
                FriendStore.Load.Loaded -> Panel(padding = 20.dp) {
                    Text(L("Ancora nessun amico"), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                    Spacer(Modifier.height(6.dp))
                    Text(L("Manda il tuo invito: chi lo apre in TrackLap diventa tuo amico, e tu suo."), fontSize = 13.sp, color = Theme.sub)
                }
            }
        } else {
            for (f in store.friends) MateRow(f, open = { nav.push(AppTab.friends, "friend:" + f.id) }, remove = { removing = f })
            (store.state as? FriendStore.Load.Failed)?.let { Text(it.message, fontSize = 12.sp, color = Theme.yellow) }
        }
    }
    removing?.let { f ->
        RemoveFriendDialog(f, onDismiss = { removing = null }) {
            removing = null
            scope.launch { runCatching { store.remove(f) } }
        }
    }
}

@Composable
private fun RemoveFriendDialog(friend: Friend, onDismiss: () -> Unit, confirm: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = Theme.panel,
        title = { Text(L("Togliere %@ dagli amici?", friend.name), color = Theme.text) },
        text = { Text(L("Non vedrete più garage e tempi l'uno dell'altro. Per tornare amici serve un invito nuovo."), color = Theme.sub) },
        confirmButton = { TextButton(confirm) { Text(L("Togli dagli amici"), color = Theme.bad) } },
        dismissButton = { TextButton(onDismiss) { Text(L("Annulla"), color = Theme.sub) } },
    )
}

/** A friend in the list: the initial, the name and since when. */
@Composable
private fun MateRow(friend: Friend, open: () -> Unit, remove: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.panel).border(1.dp, Theme.line.copy(alpha = 0.8f), shape).clickable(onClick = open).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Avatar(friend.initial, 46.dp)
        Column(Modifier.weight(1f)) {
            Text(friend.name, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            friend.since?.let { Text(L("Amici dal %@", Fmt.dayShort(it / 1000)), fontSize = 12.sp, color = Theme.sub) }
        }
        Icon(Icons.Filled.PersonRemove, L("Togli dagli amici"), tint = Theme.sub, modifier = Modifier.size(20.dp).clickable(onClick = remove))
        Icon(Icons.Filled.ChevronRight, null, tint = Theme.sub, modifier = Modifier.size(20.dp))
    }
}

/** The initial of a name in a circle. */
@Composable
private fun Avatar(initial: String, size: Dp) {
    Box(Modifier.size(size).clip(CircleShape).background(Theme.accent), contentAlignment = Alignment.Center) {
        Text(initial, fontSize = (size.value * 0.43f).sp, fontWeight = FontWeight.Black, color = Color.Black)
    }
}

/** Your invitation link, to send to a friend however you like. */
@Composable
private fun InvitePanel() {
    val m = LocalModel.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var url by remember(m.account.name) { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var renewing by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }
    LaunchedEffect(m.account.name, attempt) {
        error = null
        runCatching { m.friendList.inviteURL() }.onSuccess { url = it }.onFailure { error = it.message }
    }
    Panel(glow = Theme.accent) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.PersonAdd, null, tint = Theme.accent, modifier = Modifier.size(26.dp))
            Column(Modifier.weight(1f)) {
                Text(L("Invita un amico"), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                Text(L("Mandagli il tuo link: quando lo apre in TrackLap diventate amici. Il link vale una settimana e funziona per più amici."), fontSize = 12.sp, color = Theme.sub)
            }
        }
        Spacer(Modifier.height(12.dp))
        val link = url
        when {
            link != null -> {
                PrimaryButton(L("Manda l'invito"), Icons.Filled.Share) {
                    shareText(context, L("Apri il link per diventare mio amico su TrackLap: vedrai il mio garage e i miei tempi.") + "\n" + link)
                }
                Spacer(Modifier.height(10.dp))
                Text(
                    L("Fai un link nuovo"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.sub,
                    modifier = Modifier.fillMaxWidth().clickable { renewing = true }, textAlign = TextAlign.Center,
                )
            }
            error != null -> {
                Text(error ?: "", fontSize = 12.sp, color = Theme.yellow)
                Spacer(Modifier.height(8.dp))
                SecondaryButton(L("Riprova"), Icons.Filled.Refresh, Theme.yellow) { attempt += 1 }
            }
            else -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { CircularProgressIndicator(Modifier.size(24.dp), color = Theme.accent) }
        }
    }
    if (renewing) {
        AlertDialog(
            onDismissRequest = { renewing = false }, containerColor = Theme.panel,
            title = { Text(L("Fare un link nuovo?"), color = Theme.text) },
            text = { Text(L("Il link che hai già mandato smette di funzionare. Gli amici che hai già restano."), color = Theme.sub) },
            confirmButton = {
                TextButton({
                    renewing = false
                    scope.launch { runCatching { m.friendList.inviteURL(renew = true) }.onSuccess { url = it }.onFailure { error = it.message } }
                }) { Text(L("Fai un link nuovo"), color = Theme.accent) }
            },
            dismissButton = { TextButton({ renewing = false }) { Text(L("Annulla"), color = Theme.sub) } },
        )
    }
}

/** A friend: their numbers, their garage and their best lap on every track, from the online leaderboards. */
@Composable
fun FriendDetailScreen(id: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val friend = m.friendList.friend(id)
    var profile by remember { mutableStateOf<FriendProfile?>(null) }
    var garage by remember { mutableStateOf<PublicGarage?>(null) }
    var garageError by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var openCar by remember { mutableStateOf<String?>(null) }
    var removing by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }
    if (friend == null) {
        LaunchedEffect(Unit) { nav.pop(AppTab.friends) }
        return
    }
    LaunchedEffect(id, attempt) {
        error = null
        try {
            val p = m.friendList.profile(friend)
            profile = p
            garageError = null
            garage = p.garage?.let { code ->
                try {
                    Server.garage(code, m.account.token)
                } catch (e: ServerFailure) {
                    if (e.kind != ServerFailure.Kind.notFound) garageError = e.message
                    null
                }
            }
        } catch (e: ServerFailure) {
            if (e.kind == ServerFailure.Kind.notFriend) nav.pop(AppTab.friends) else error = e.message
        }
    }
    val g = garage
    val car = g?.cars?.firstOrNull { it.id == openCar }
    Column(Modifier.fillMaxSize()) {
        TopBar(car?.name ?: friend.name, onBack = { if (car != null) openCar = null else nav.pop(AppTab.friends) }) {
            if (car == null) RoundIconButton(Icons.Filled.PersonRemove, Theme.sub) { removing = true }
        }
        if (car != null && g != null) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                val info = g.info(car) { Server.photoURL(g.code, it) }
                CarPhotoView(info.photo, Modifier.fillMaxWidth().aspectRatio(1.45f).clip(RoundedCornerShape(22.dp)))
                Text(L("Dal garage di %@", g.name), fontSize = 13.sp, color = Theme.sub)
                Text(info.name, fontSize = 26.sp, fontWeight = FontWeight.Black, color = Theme.text)
                SpecGrid(info)
                ModsPanel(info)
            }
            return@Column
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Avatar(friend.initial, 60.dp)
                Column(Modifier.weight(1f)) {
                    Text(friend.name, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    friend.since?.let { Text(L("Amici dal %@", Fmt.dayShort(it / 1000)), fontSize = 13.sp, color = Theme.sub) }
                }
            }
            val p = profile
            when {
                p != null -> {
                    val s = p.stats
                    if (s != null && p.laps.isNotEmpty()) Numbers(s)
                    SectionLabel(L("Garage"))
                    if (g != null && g.cars.isNotEmpty()) {
                        for (row in g.cars.chunked(2)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                for (c in row) InfoCard(g.info(c) { Server.photoURL(g.code, it) }, Modifier.weight(1f)) { openCar = c.id }
                                if (row.size == 1) Spacer(Modifier.weight(1f))
                            }
                        }
                    } else {
                        Empty(Icons.Filled.DirectionsCar, L("Nessuna auto da vedere"), garageError ?: L("%@ non mostra il garage, oppure non ci ha ancora messo auto.", friend.name))
                    }
                    SectionLabel(L("Giri migliori"))
                    if (p.laps.isEmpty()) {
                        Empty(Icons.Filled.Timer, L("Nessun giro in classifica"), L("I giri migliori compaiono qui quando li manda nelle classifiche online delle piste."))
                    } else {
                        for (lap in p.laps) BestRow(lap, g) { openCar = it }
                    }
                }
                error != null -> Panel {
                    Text(error ?: "", fontSize = 14.sp, color = Theme.yellow)
                    Spacer(Modifier.height(10.dp))
                    SecondaryButton(L("Riprova"), Icons.Filled.Refresh, Theme.yellow) { attempt += 1 }
                }
                else -> Box(Modifier.fillMaxWidth().padding(48.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Theme.accent) }
            }
        }
    }
    if (removing) {
        RemoveFriendDialog(friend, onDismiss = { removing = false }) {
            removing = false
            scope.launch {
                runCatching { m.friendList.remove(friend) }
                nav.pop(AppTab.friends)
            }
        }
    }
}

@Composable
private fun Numbers(s: FriendProfile.Stats) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatTile(L("Piste"), "${s.tracks}", Modifier.weight(1f))
            StatTile(L("Sessioni"), "${s.sessions}", Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatTile(L("Primo in classifica"), "${s.wins}", Modifier.weight(1f), unit = if (s.wins == 1) L("pista") else L("piste"),
                color = if (s.wins > 0) Theme.purple else Theme.text)
            StatTile(L("Ultima volta in pista"), s.last?.let { Fmt.dayShort(it / 1000) } ?: "–", Modifier.weight(1f))
        }
        s.favourite?.let { fav ->
            Panel(padding = 14.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(Icons.Filled.Favorite, null, tint = Theme.accent, modifier = Modifier.size(18.dp))
                    Text(L("Pista preferita"), fontSize = 14.sp, color = Theme.sub, modifier = Modifier.weight(1f))
                    Text(fav, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** A friend's best lap on one track: the time, the place, the sessions and the car, which opens when you can see it. */
@Composable
private fun BestRow(lap: FriendProfile.Best, garage: PublicGarage?, openCar: (String) -> Unit) {
    val first = lap.rank == 1
    Panel(padding = 14.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(lap.track.name, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text(Fmt.lap(lap.time), style = Theme.timeStyle(22.sp, if (first) Theme.purple else Theme.text))
        }
        Spacer(Modifier.height(6.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            GpsBadge(lap.source)
            Text(if (lap.of == 1) L("Unico in classifica") else L("%lld° su %lld", lap.rank, lap.of), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = if (first) Theme.purple else Theme.sub)
        }
        Spacer(Modifier.height(4.dp))
        val day = Fmt.dayShort(lap.last / 1000)
        Text(if (lap.sessions == 1) L("1 sessione, il %@", day) else L("%lld sessioni, l'ultima il %@", lap.sessions, day), fontSize = 12.sp, color = Theme.sub)
        if (lap.vehicle.isNotEmpty()) {
            val visible = garage != null && garage.code == lap.garage && garage.cars.any { it.id == lap.car }
            Spacer(Modifier.height(6.dp))
            Row(
                Modifier.then(if (visible) Modifier.clickable { openCar(lap.car) } else Modifier),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Filled.DirectionsCar, null, tint = if (visible) Theme.accent else Theme.sub, modifier = Modifier.size(16.dp))
                Text(lap.vehicle, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = if (visible) Theme.accent else Theme.sub)
            }
        }
    }
}

@Composable
private fun Empty(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, text: String) {
    Panel(padding = 18.dp) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(icon, null, tint = Theme.sub, modifier = Modifier.size(24.dp))
            Column {
                Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                Text(text, fontSize = 12.sp, color = Theme.sub)
            }
        }
    }
}

/**
 * A friend invitation opened from its link (tracklap://friend/<code>): who it is from, and the button
 * that makes you friends. Signed out, you sign in or make an account first, then accept here.
 */
@Composable
fun FriendInviteDialog(code: String, signIn: () -> Unit, onDone: () -> Unit) {
    val m = LocalModel.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }
    LaunchedEffect(code, attempt) {
        error = null
        runCatching { Server.inviter(code) }.onSuccess { name = it }.onFailure { error = it.message }
    }
    val from = name
    val mine = from != null && m.account.name?.equals(from, ignoreCase = true) == true
    AlertDialog(
        onDismissRequest = onDone, containerColor = Theme.panel,
        icon = { if (from != null) Avatar(from.take(1).uppercase(), 56.dp) },
        title = { if (from != null) Text(L("%@ ti invita su TrackLap", from), color = Theme.text, textAlign = TextAlign.Center) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                when {
                    from != null -> {
                        Text(L("Diventate amici: vedrete i vostri garage, i giri migliori su ogni pista e le statistiche."), color = Theme.sub)
                        if (!m.account.isSignedIn) Text(L("Serve un account TrackLap: accedi o creane uno, poi accetti."), fontSize = 13.sp, color = Theme.sub)
                        if (mine) Text(L("È il tuo invito: mandalo a un amico."), fontWeight = FontWeight.SemiBold, color = Theme.yellow)
                    }
                    error == null -> Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Theme.accent) }
                }
                error?.let { Text(it, fontSize = 13.sp, color = Theme.yellow) }
            }
        },
        confirmButton = {
            when {
                from == null && error != null -> TextButton({ attempt += 1 }) { Text(L("Riprova"), color = Theme.accent) }
                from == null || mine -> {}
                !m.account.isSignedIn -> TextButton(signIn) { Text(L("Accedi o crea un account"), color = Theme.accent) }
                else -> TextButton(onClick = {
                    if (!busy) {
                        busy = true
                        error = null
                        scope.launch {
                            runCatching { m.friendList.accept(code) }
                                .onSuccess {
                                    m.tab = AppTab.friends
                                    onDone()
                                }
                                .onFailure { error = it.message }
                            busy = false
                        }
                    }
                }) { Text(L("Accetta"), color = Theme.accent, fontWeight = FontWeight.Bold) }
            }
        },
        dismissButton = { TextButton(onDone) { Text(L("Non ora"), color = Theme.sub) } },
    )
}
