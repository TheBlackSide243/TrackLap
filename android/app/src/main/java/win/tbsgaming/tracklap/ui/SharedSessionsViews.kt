package win.tbsgaming.tracklap.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.data.GarageStore
import win.tbsgaming.tracklap.data.Server
import win.tbsgaming.tracklap.data.SessionAudience
import win.tbsgaming.tracklap.data.SharedSession
import win.tbsgaming.tracklap.data.SharedSessions

/** Who sees your sessions in your garage: nobody, your friends or everyone, like the garage. */
@Composable
fun SharingPanel() {
    val m = LocalModel.current
    val shared = m.sharedSessions
    Panel {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(Icons.Filled.Share, null, tint = Theme.accent, modifier = Modifier.size(18.dp))
                Text(L("Condivisione"), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text, modifier = Modifier.weight(1f))
                if (shared.sync == GarageStore.Sync.Syncing) CircularProgressIndicator(Modifier.size(16.dp), color = Theme.accent, strokeWidth = 2.dp)
            }
            if (m.account.isSignedIn) {
                Segmented(SessionAudience.entries.map { it.title to it }, shared.audience) { shared.updateAudience(it) }
                Text(shared.audience.summary, fontSize = 12.sp, color = Theme.sub)
                (shared.sync as? GarageStore.Sync.Failed)?.let { Text(it.message, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.bad) }
            } else {
                Text(L("Accedi al tuo account in Dispositivo per mostrare le sessioni a tutti o solo agli amici."), fontSize = 12.sp, color = Theme.sub)
            }
        }
    }
}

/** Someone's shared sessions, in their garage or on a friend's page: nothing at all when they share none with you. */
@Composable
fun SharedSessionsSection(code: String) {
    val m = LocalModel.current
    var shared by remember(code) { mutableStateOf<SharedSessions?>(null) }
    var open by remember(code) { mutableStateOf<String?>(null) }
    var all by remember(code) { mutableStateOf(false) }
    LaunchedEffect(code) {
        // Your own garage: your sessions are in the Sessions tab already.
        if (code != m.account.garage) shared = runCatching { Server.sessions(code, m.account.token) }.getOrNull()
    }
    val list = shared?.sessions.orEmpty()
    if (list.isEmpty()) return
    SectionLabel(L("Sessioni"))
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (s in if (all) list else list.take(FIRST)) {
            SharedSessionRow(s, open == s.id) { open = if (open == s.id) null else s.id }
        }
        if (!all && list.size > FIRST) SecondaryButton(L("Mostra tutte (%lld)", list.size), modifier = Modifier.fillMaxWidth()) { all = true }
    }
}

private const val FIRST = 10

@Composable
private fun SharedSessionRow(s: SharedSession, open: Boolean, toggle: () -> Unit) {
    Panel(Modifier.clickable(onClick = toggle), padding = 14.dp) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(s.track, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text(Fmt.lap(s.best), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Theme.purple)
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Badge(if (s.source == "device") "ESP32" else L("Telefono"), Theme.sub)
                Text(Fmt.day(s.date / 1000), fontSize = 12.sp, color = Theme.sub, modifier = Modifier.weight(1f))
                Text(if (s.laps.size == 1) L("1 giro") else L("%lld giri", s.laps.size), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.sub)
                Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = Theme.sub, modifier = Modifier.size(18.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(s.vehicle.icon, null, tint = Theme.sub, modifier = Modifier.size(14.dp))
                Text(s.car ?: s.vehicle.title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.sub, maxLines = 1)
            }
            if (open) {
                for (row in s.laps.withIndex().chunked(3)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        for ((i, t) in row) {
                            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text("${i + 1}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Theme.sub, modifier = Modifier.width(20.dp))
                                Text(Fmt.lap(t), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (t == s.best) Theme.purple else Theme.text)
                            }
                        }
                        repeat(3 - row.size) { Row(Modifier.weight(1f)) {} }
                    }
                }
            }
        }
    }
}
