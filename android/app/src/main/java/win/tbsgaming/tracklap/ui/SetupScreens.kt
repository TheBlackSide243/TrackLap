package win.tbsgaming.tracklap.ui

import android.content.Context
import android.content.Intent
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Thunderstorm
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.WbSunny
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalNav
import win.tbsgaming.tracklap.model.CarSetup
import win.tbsgaming.tracklap.model.SetupField
import win.tbsgaming.tracklap.model.SetupItem
import win.tbsgaming.tracklap.model.SetupRevision
import win.tbsgaming.tracklap.model.SetupValues
import win.tbsgaming.tracklap.model.SetupWeather
import win.tbsgaming.tracklap.model.SharedSetup
import java.io.File
import java.text.NumberFormat
import java.util.Locale

/** Sun, sun and clouds, rain: the conditions a setup is for. */
@Composable
fun WeatherGlyph(w: SetupWeather?, size: Dp) {
    val (icon, color) = when (w) {
        SetupWeather.wet -> Icons.Filled.Thunderstorm to Theme.blue
        SetupWeather.mixed -> Icons.Filled.Cloud to Theme.sub
        else -> Icons.Filled.WbSunny to Theme.yellow
    }
    Icon(icon, null, tint = color, modifier = Modifier.size(size))
}

@Composable
fun SetupRow(s: CarSetup, active: Boolean, open: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(Theme.panel).border(1.dp, if (active) Theme.accent.copy(alpha = 0.6f) else Theme.line.copy(alpha = 0.8f), shape)
            .clickable(onClick = open).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(40.dp).clip(RoundedCornerShape(12.dp)).background(Theme.input), contentAlignment = Alignment.Center) { WeatherGlyph(s.weather, 22.dp) }
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(s.displayName, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, false))
                if (active) Badge(L("In uso"))
            }
            Text(listOfNotNull(s.weather.title, s.track.ifEmpty { null }, L("v%lld", s.version)).joinToString(" · "), fontSize = 12.sp, color = Theme.sub, maxLines = 1)
        }
        Icon(Icons.Filled.ChevronRight, null, tint = Theme.sub, modifier = Modifier.size(18.dp))
    }
}

/** The values of a setup by group, only the ones that are set. */
@Composable
fun SetupValuesView(v: SetupValues) {
    if (v.isEmpty) {
        Panel { Text(L("Ancora nessun valore: tocca Modifica per scriverli."), fontSize = 13.sp, color = Theme.sub) }
        return
    }
    for (g in SetupField.Group.entries) {
        val rows = SetupField.all.filter { it.group == g }.mapNotNull { f -> f.display(v)?.let { f.title to it } }
        val extra = if (g == SetupField.Group.aero) v.extra.filter { it.label.isNotBlank() }.map { it.label to it.value } else emptyList()
        if (rows.isEmpty() && extra.isEmpty()) continue
        Panel(padding = 4.dp) {
            Text(g.title, fontSize = 12.sp, fontWeight = FontWeight.Black, color = Theme.accent, modifier = Modifier.padding(start = 12.dp, top = 10.dp, bottom = 4.dp))
            for ((i, r) in (rows + extra).withIndex()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 9.dp)) {
                    Text(r.first, fontSize = 14.sp, color = Theme.sub, modifier = Modifier.weight(1f))
                    Text(r.second, style = Theme.numStyle(14.sp, FontWeight.SemiBold))
                }
                if (i < rows.size + extra.size - 1) Hairline()
            }
        }
    }
    if (v.notes.isNotBlank()) Panel { Text(v.notes, fontSize = 14.sp, color = Theme.text) }
}

private fun shareSetup(context: Context, shared: SharedSetup) {
    val f = shared.write(File(context.cacheDir, "exports"))
    val uri = FileProvider.getUriForFile(context, context.packageName + ".files", f)
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "application/octet-stream"
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    context.startActivity(Intent.createChooser(send, f.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

@Composable
fun SetupDetailScreen(id: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val context = LocalContext.current
    val s = m.garage.setup(id)
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var revision by remember { mutableStateOf<SetupRevision?>(null) }
    if (s == null) {
        LaunchedEffect(Unit) { nav.pop(AppTab.garage) }
        return
    }
    val car = m.garage.car(s.carID)
    val active = m.activeSetupID == s.id
    Column(Modifier.fillMaxSize()) {
        TopBar(s.displayName, onBack = { nav.pop(AppTab.garage) }) {
            Box {
                RoundIconButton(Icons.Filled.MoreVert) { menu = true }
                DropdownMenu(menu, { menu = false }, containerColor = Theme.panel) {
                    DropdownMenuItem({ Text(L("Modifica"), color = Theme.text) }, { menu = false; nav.push(AppTab.garage, "setupEdit:${s.carID}:${s.id}") }, leadingIcon = { Icon(Icons.Filled.Edit, null, tint = Theme.accent) })
                    DropdownMenuItem({ Text(L("Duplica"), color = Theme.text) }, {
                        menu = false
                        m.garage.duplicate(s.id)?.let { nav.replaceTop(AppTab.garage, "setup:${it.id}") }
                    }, leadingIcon = { Icon(Icons.Filled.ContentCopy, null, tint = Theme.accent) })
                    DropdownMenuItem({ Text(L("Esporta in un file"), color = Theme.text) }, {
                        menu = false
                        shareSetup(context, SharedSetup(car = car?.displayName ?: "", setup = s))
                    }, leadingIcon = { Icon(Icons.Filled.Share, null, tint = Theme.accent) })
                    DropdownMenuItem({ Text(L("Elimina l'assetto"), color = Theme.bad) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.bad) })
                }
            }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.size(52.dp).clip(RoundedCornerShape(14.dp)).background(Theme.input), contentAlignment = Alignment.Center) { WeatherGlyph(s.weather, 30.dp) }
                    Column(Modifier.weight(1f)) {
                        Text(s.displayName, fontSize = 20.sp, fontWeight = FontWeight.Black, color = Theme.text)
                        Text(listOfNotNull(s.weather.title, s.track.ifEmpty { null }, car?.displayName).joinToString(" · "), fontSize = 13.sp, color = Theme.sub)
                        Text(L("Versione %lld · aggiornato il %@", s.version, Fmt.dayShort(s.updated)), fontSize = 12.sp, color = Theme.sub)
                    }
                }
            }
            if (active) Note(Icons.Filled.CheckCircle, Theme.good, L("Lo stai usando in Live: le prossime sessioni se lo ricordano"))
            else PrimaryButton(L("Usa questo assetto in Live"), Icons.Filled.Timer) { m.drive(s) }
            SetupValuesView(s.values)
            Note(Icons.Filled.Lock, Theme.sub, L("Gli assetti restano su questo telefono: non vanno mai online. Per darli a qualcuno si esportano in un file."))
            val sessions = m.sessions.summaries.filter { it.setupID == s.id }
            if (sessions.isNotEmpty()) {
                SectionLabel(L("Sessioni con questo assetto"))
                Panel(padding = 4.dp) {
                    for ((i, x) in sessions.withIndex()) {
                        Row(Modifier.fillMaxWidth().clickable { m.tab = AppTab.sessions; nav.push(AppTab.sessions, "session:${x.id}") }.padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(x.trackName, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text, maxLines = 1)
                                Text(Fmt.dayShort(x.date) + (x.setupVersion?.let { " · " + L("v%lld", it) } ?: ""), fontSize = 11.sp, color = Theme.sub)
                            }
                            Text(Fmt.lap(x.best), style = Theme.numStyle(16.sp, FontWeight.Black, Theme.purple))
                        }
                        if (i < sessions.size - 1) Hairline()
                    }
                }
            }
            if (s.history.isNotEmpty()) {
                SectionLabel(L("Versioni precedenti"))
                var newer = s.values
                for (r in s.history) {
                    val changes = newer.changes(r.values)
                    newer = r.values
                    Panel(modifier = Modifier.clickable { revision = r }) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Icon(Icons.Filled.History, null, tint = Theme.sub, modifier = Modifier.size(18.dp))
                            Text(L("Versione %lld", r.version), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Theme.text, modifier = Modifier.weight(1f))
                            Text(L("fino al %@", Fmt.dayShort(r.date)), fontSize = 12.sp, color = Theme.sub)
                        }
                        for (c in changes.take(3)) Text(c, fontSize = 12.sp, color = Theme.sub, modifier = Modifier.padding(top = 4.dp))
                        if (changes.size > 3) Text(L("e altre %lld modifiche", changes.size - 3), fontSize = 12.sp, color = Theme.sub)
                    }
                }
            }
        }
    }
    revision?.let { r ->
        AlertDialog(
            onDismissRequest = { revision = null }, containerColor = Theme.panel,
            title = { Text(L("Versione %lld", r.version), color = Theme.text) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SetupValuesView(r.values)
                    Text(L("La versione di adesso non si perde: va anche lei nello storico."), fontSize = 12.sp, color = Theme.sub)
                }
            },
            confirmButton = { TextButton({ m.garage.save(s.copy(values = r.values)); revision = null }) { Text(L("Torna a questa versione"), color = Theme.accent) } },
            dismissButton = { TextButton({ revision = null }) { Text(L("Fine"), color = Theme.sub) } },
        )
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false }, containerColor = Theme.panel,
            title = { Text(L("Eliminare questo assetto?"), color = Theme.text) },
            text = { Text(L("Le sessioni restano, con l'assetto com'era quel giorno."), color = Theme.sub) },
            confirmButton = { TextButton({ confirmDelete = false; m.deleteSetup(s.id); nav.pop(AppTab.garage) }) { Text(L("Elimina l'assetto"), color = Theme.bad) } },
            dismissButton = { TextButton({ confirmDelete = false }) { Text(L("Annulla"), color = Theme.accent) } },
        )
    }
}

/** A new setup or a change to one. Saving keeps the values of now in the earlier versions. */
@Composable
fun SetupEditorScreen(carID: String, setupID: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val existing = m.garage.setup(setupID)
    var draft by remember { mutableStateOf(existing ?: CarSetup(carID = carID)) }
    // What each number field shows, as typed: a field left alone keeps its stored value.
    val typed = remember { mutableStateMapOf<String, String>() }
    val numbers = remember { NumberFormat.getNumberInstance(Locale.getDefault()) }

    fun shownText(f: SetupField): String = typed[f.id] ?: f.number?.invoke(draft.values)?.let { SetupField.format(f.shown(it), f.shownDecimals) } ?: ""

    fun save() {
        var v = draft.values
        for ((id, text) in typed) {
            val f = SetupField.all.firstOrNull { it.id == id } ?: continue
            val x = text.trim().replace(',', '.').toDoubleOrNull()
                ?: runCatching { numbers.parse(text.trim())?.toDouble() }.getOrNull()
            v = f.setNumber?.invoke(v, x?.let { f.kept(it) }) ?: v
        }
        m.garage.save(draft.copy(values = v.copy(extra = v.extra.filter { it.label.isNotBlank() || it.value.isNotBlank() })))
        nav.pop(AppTab.garage)
        if (existing == null) nav.push(AppTab.garage, "setup:${draft.id}")
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(if (existing == null) L("Nuovo assetto") else L("Modifica assetto"), onBack = { nav.pop(AppTab.garage) }) {
            Text(L("Salva"), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.accent, modifier = Modifier.clickable { save() })
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Field(draft.name, L("Nome (es. Mugello bagnato)")) { draft = draft.copy(name = it.take(40)) }
            Field(draft.track, L("Pista (facoltativa)")) { draft = draft.copy(track = it.take(60)) }
            Text(L("Condizioni"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
            Segmented(SetupWeather.entries.map { it.title to it }, draft.weather) { draft = draft.copy(weather = it) }
            for (g in SetupField.Group.entries) {
                SectionLabel(g.title)
                for (f in SetupField.all.filter { it.group == g }) {
                    if (f.text != null) {
                        Field(f.text.invoke(draft.values), f.title) { t -> draft = draft.copy(values = f.setText!!(draft.values, t.take(60))) }
                    } else {
                        val unit = f.shownUnit
                        Field(shownText(f), f.title + if (unit.isEmpty()) "" else " ($unit)", number = false) { t -> typed[f.id] = t.filter { it.isDigit() || it == ',' || it == '.' || it == '-' }.take(8) }
                    }
                }
                if (g == SetupField.Group.aero) {
                    for ((i, item) in draft.values.extra.withIndex()) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Field(item.label, L("Voce"), Modifier.weight(1f)) { t -> draft = draft.copy(values = draft.values.copy(extra = draft.values.extra.toMutableList().also { it[i] = item.copy(label = t.take(40)) })) }
                            Field(item.value, L("Valore"), Modifier.weight(1f)) { t -> draft = draft.copy(values = draft.values.copy(extra = draft.values.extra.toMutableList().also { it[i] = item.copy(value = t.take(40)) })) }
                            Icon(Icons.Filled.Close, null, tint = Theme.bad, modifier = Modifier.size(22.dp).clickable {
                                draft = draft.copy(values = draft.values.copy(extra = draft.values.extra.filterIndexed { k, _ -> k != i }))
                            })
                        }
                    }
                    SecondaryButton(L("Aggiungi una voce"), Icons.Filled.Add) {
                        draft = draft.copy(values = draft.values.copy(extra = draft.values.extra + SetupItem(label = "", value = "")))
                    }
                }
            }
            SectionLabel(L("Note"))
            OutlinedTextField(
                draft.values.notes, { draft = draft.copy(values = draft.values.copy(notes = it.take(1000))) }, Modifier.fillMaxWidth().height(120.dp),
                placeholder = { Text(L("Come andava, cosa provare la prossima volta…"), color = Theme.sub) }, colors = fieldColors(), shape = RoundedCornerShape(14.dp),
            )
            if (existing != null) Text(L("Salvando, i valori di adesso restano nelle versioni precedenti."), fontSize = 12.sp, color = Theme.sub)
            PrimaryButton(L("Salva"), Icons.Filled.CheckCircle) { save() }
        }
    }
}

/** A setup file opened from another app: which of your cars it goes to. */
@Composable
fun SetupImportDialog(shared: SharedSetup, done: () -> Unit) {
    val m = LocalModel.current
    val nav = LocalNav.current
    AlertDialog(
        onDismissRequest = done, containerColor = Theme.panel,
        title = { Text(L("Importa assetto"), color = Theme.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(shared.setup.displayName, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                if (shared.car.isNotBlank()) Text(L("Assetto per %@", shared.car), fontSize = 13.sp, color = Theme.sub)
                if (m.garage.cars.isEmpty()) {
                    Text(L("Aggiungi prima un'auto nel Garage: l'assetto va con un'auto."), fontSize = 13.sp, color = Theme.yellow)
                } else {
                    Text(L("Aggiungilo a"), fontSize = 13.sp, color = Theme.sub)
                    for (c in m.garage.cars) {
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Theme.input).clickable {
                                val s = m.garage.importSetup(shared, c.id)
                                done()
                                m.tab = AppTab.garage
                                nav.push(AppTab.garage, "setup:${s.id}")
                            }.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(c.displayName, fontSize = 15.sp, color = Theme.text, modifier = Modifier.weight(1f))
                            Icon(Icons.Filled.ChevronRight, null, tint = Theme.sub, modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(done) { Text(L("Annulla"), color = Theme.sub) } },
    )
}
