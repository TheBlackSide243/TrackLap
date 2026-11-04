package win.tbsgaming.tracklap.ui

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.LruCache
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AddAPhoto
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalNav
import win.tbsgaming.tracklap.data.GarageLink
import win.tbsgaming.tracklap.data.GarageStore
import win.tbsgaming.tracklap.data.Net
import win.tbsgaming.tracklap.data.Server
import win.tbsgaming.tracklap.model.Car
import win.tbsgaming.tracklap.model.CarFmt
import win.tbsgaming.tracklap.model.CarInfo
import win.tbsgaming.tracklap.model.CarPhoto
import win.tbsgaming.tracklap.model.DragMeasure
import win.tbsgaming.tracklap.model.PublicGarage
import java.net.HttpURLConnection
import java.net.URL
import java.text.DateFormat
import java.util.Date

/** Photos from the server, kept in memory while the app runs. */
private object RemoteImages {
    val cache = LruCache<String, Bitmap>(24)

    suspend fun load(url: String): Bitmap? {
        cache.get(url)?.let { return it }
        return withContext(Dispatchers.IO) {
            runCatching {
                val c = URL(url).openConnection() as HttpURLConnection
                c.connectTimeout = 15_000
                c.readTimeout = 30_000
                c.setRequestProperty("User-Agent", Net.userAgent)
                try {
                    c.inputStream.use { BitmapFactory.decodeStream(it) }
                } finally {
                    c.disconnect()
                }
            }.getOrNull()?.also { cache.put(url, it) }
        }
    }
}

/** A car's photo filling its box, or a car icon on a dark gradient when there is none. */
@Composable
fun CarPhotoView(photo: CarPhoto, modifier: Modifier) {
    val m = LocalModel.current
    val bitmap by produceState<Bitmap?>(null, photo) {
        value = when (photo) {
            is CarPhoto.Local -> withContext(Dispatchers.IO) { m.garage.image(photo.id) }
            is CarPhoto.Remote -> RemoteImages.load(photo.url)
            CarPhoto.Empty -> null
        }
    }
    Box(modifier.background(Brush.verticalGradient(listOf(Theme.input, Theme.panel))), contentAlignment = Alignment.Center) {
        val b = bitmap
        if (b != null) Image(b.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else Icon(Icons.Filled.DirectionsCar, null, tint = Theme.sub.copy(alpha = 0.5f), modifier = Modifier.size(44.dp))
    }
}

@Composable
fun GarageScreen() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val g = m.garage
    val cars = g.cars
    val active = m.activeCar
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ScreenHeader(Icons.Filled.DirectionsCar, L("Garage"), if (cars.size == 1) L("1 auto") else L("%lld auto", cars.size)) {
            if (!g.isFull) RoundIconButton(Icons.Filled.Add) { nav.push(AppTab.garage, "editor:new") }
        }
        if (cars.isEmpty()) {
            Panel(padding = 24.dp, glow = Theme.accent) {
                Icon(Icons.Filled.DirectionsCar, null, tint = Theme.accent, modifier = Modifier.size(34.dp))
                Spacer(Modifier.height(10.dp))
                Text(L("Il tuo garage è vuoto"), fontSize = 20.sp, fontWeight = FontWeight.Black, color = Theme.text)
                Spacer(Modifier.height(6.dp))
                Text(L("Aggiungi le auto con cui giri in pista: una foto, i cavalli, il peso e tutte le modifiche. Scegli quella che usi in Live e i tuoi tempi in classifica porteranno a lei."), fontSize = 14.sp, color = Theme.sub)
                Spacer(Modifier.height(14.dp))
                PrimaryButton(L("Aggiungi la prima auto"), Icons.Filled.Add) { nav.push(AppTab.garage, "editor:new") }
            }
        } else {
            active?.let { CarHero(it) { nav.push(AppTab.garage, "car:${it.id}") } }
            val others = cars.filter { it.id != active?.id }
            if (others.isNotEmpty()) {
                SectionLabel(if (active == null) L("Le auto con cui giri in pista") else L("Le altre auto"))
                for (row in others.chunked(2)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        for (c in row) CarCard(c, Modifier.weight(1f)) { nav.push(AppTab.garage, "car:${c.id}") }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
            }
            if (g.isFull) Text(L("Il garage ha posto per %lld auto.", Car.MAX_CARS), fontSize = 12.sp, color = Theme.sub)
            else SecondaryButton(L("Aggiungi un'auto"), Icons.Filled.Add) { nav.push(AppTab.garage, "editor:new") }
        }
        PublicPanel()
    }
}

/** The car in use, big, with its numbers on the photo. */
@Composable
private fun CarHero(car: Car, open: () -> Unit) {
    val shape = RoundedCornerShape(22.dp)
    val info = car.info
    Box(Modifier.fillMaxWidth().aspectRatio(1.45f).clip(shape).border(1.5.dp, Theme.accent.copy(alpha = 0.7f), shape).clickable(onClick = open)) {
        CarPhotoView(info.photo, Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.75f)), startY = 200f)))
        Box(Modifier.padding(12.dp)) { Badge(L("In uso in Live")) }
        Column(Modifier.align(Alignment.BottomStart).padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(info.name, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                info.power?.let { SpecChip(CarFmt.power(it), CarFmt.powerUnit) }
                info.weight?.let { SpecChip(CarFmt.weight(it), CarFmt.weightUnit) }
                info.ratio?.let { SpecChip(CarFmt.ratio(it), CarFmt.ratioUnit) }
            }
        }
    }
}

@Composable
private fun SpecChip(value: String, unit: String) {
    Row(
        Modifier.clip(RoundedCornerShape(10.dp)).background(Color.Black.copy(alpha = 0.45f)).padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        Text(value, style = Theme.numStyle(15.sp, FontWeight.Black, Color.White))
        Text(unit, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.75f))
    }
}

@Composable
fun CarCard(car: Car, modifier: Modifier, open: () -> Unit) = InfoCard(car.info, modifier, open)

@Composable
fun InfoCard(info: CarInfo, modifier: Modifier, open: () -> Unit) {
    val shape = RoundedCornerShape(18.dp)
    Column(modifier.clip(shape).background(Theme.panel).border(1.dp, Theme.line.copy(alpha = 0.8f), shape).clickable(onClick = open)) {
        CarPhotoView(info.photo, Modifier.fillMaxWidth().aspectRatio(1.3f))
        Column(Modifier.padding(10.dp)) {
            Text(info.name, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val mods = info.mods.size
            val sub = listOfNotNull(info.subtitle.ifEmpty { null }, if (mods == 0) null else if (mods == 1) L("1 modifica") else L("%lld modifiche", mods)).joinToString(" · ")
            Text(sub.ifEmpty { L("Nessun dato") }, fontSize = 11.sp, color = Theme.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** The garage shown to everyone: its switch, its link and how the upload went. */
@Composable
private fun PublicPanel() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val context = LocalContext.current
    val g = m.garage
    val account = m.account
    SectionLabel(L("Garage pubblico"))
    Panel {
        if (!account.isSignedIn) {
            Text(L("Fallo vedere a tutti"), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
            Spacer(Modifier.height(4.dp))
            Text(L("Con un account TrackLap il garage ha un link da condividere, e le tue auto compaiono accanto ai tuoi tempi nelle classifiche delle piste."), fontSize = 13.sp, color = Theme.sub)
            Spacer(Modifier.height(12.dp))
            PrimaryButton(L("Accedi o crea un account"), Icons.Filled.Person) { nav.push(AppTab.garage, "account") }
            return@Panel
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(L("Mostra il garage a tutti"), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                Text(L("Con il nome %@. Chi ha il link lo vede anche senza l'app, e in classifica i tuoi tempi portano all'auto con cui li hai fatti.", account.name ?: ""), fontSize = 12.sp, color = Theme.sub)
            }
            Switch(g.isPublic, { g.updatePublic(it) }, colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Color.Black))
        }
        val code = account.garage
        if (g.isPublic && code != null) {
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SecondaryButton(L("Condividi il link"), Icons.Filled.Share, modifier = Modifier.weight(1f)) {
                    shareText(context, L("Il mio garage su TrackLap") + "\n" + Server.garageURL(code))
                }
                SecondaryButton(L("Apri la pagina"), Icons.Filled.OpenInBrowser, modifier = Modifier.weight(1f)) {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Server.garageURL(code))).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        when (val s = g.sync) {
            GarageStore.Sync.Syncing -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(Modifier.size(14.dp), color = Theme.accent, strokeWidth = 2.dp)
                Text(L("Aggiorno il garage online…"), fontSize = 12.sp, color = Theme.sub)
            }
            is GarageStore.Sync.Done -> Text(L("Online, aggiornato alle %@", DateFormat.getTimeInstance(DateFormat.SHORT).format(Date((s.at * 1000).toLong()))), fontSize = 12.sp, color = Theme.good)
            is GarageStore.Sync.Failed -> Row(verticalAlignment = Alignment.CenterVertically) {
                Text(s.message, fontSize = 12.sp, color = Theme.bad, modifier = Modifier.weight(1f))
                Text(L("Riprova"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Theme.accent, modifier = Modifier.clickable { g.publishSoon(now = true) })
            }
            GarageStore.Sync.Idle -> {}
        }
    }
}

fun shareText(context: android.content.Context, text: String) {
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
    }
    context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

/** The numbers of a car in tiles. */
@Composable
fun SpecGrid(info: CarInfo) {
    val tiles = listOf(
        Triple(L("Potenza"), info.power?.let { CarFmt.power(it) } ?: "—", CarFmt.powerUnit),
        Triple(L("Peso"), info.weight?.let { CarFmt.weight(it) } ?: "—", CarFmt.weightUnit),
        Triple(L("Peso/potenza"), info.ratio?.let { CarFmt.ratio(it) } ?: "—", CarFmt.ratioUnit),
        Triple(L("Anno"), info.year?.toString() ?: "—", ""),
    )
    for (row in tiles.chunked(2)) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (t in row) StatTile(t.first, t.second, Modifier.weight(1f), unit = t.third.ifEmpty { null }, color = if (t.second == "—") Theme.sub else Theme.accent)
        }
    }
}

@Composable
fun ModsPanel(info: CarInfo) {
    if (info.mods.isNotEmpty()) {
        SectionLabel(if (info.mods.size == 1) L("1 modifica") else L("%lld modifiche", info.mods.size))
        Panel(padding = 4.dp) {
            for ((i, mod) in info.mods.withIndex()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Box(Modifier.size(24.dp).clip(CircleShape).background(Theme.accent.copy(alpha = 0.15f)), contentAlignment = Alignment.Center) {
                        Text("${i + 1}", fontSize = 11.sp, fontWeight = FontWeight.Black, color = Theme.accent)
                    }
                    Text(mod, fontSize = 15.sp, color = Theme.text)
                }
                if (i < info.mods.size - 1) Hairline()
            }
        }
    }
    if (info.notes.isNotBlank()) {
        SectionLabel(L("Note"))
        Panel { Text(info.notes, fontSize = 14.sp, color = Theme.text) }
    }
}

/** One of your cars: the photo, the numbers, the mods, its setups and your best times with it. */
@Composable
fun CarDetailScreen(id: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val context = LocalContext.current
    val car = m.garage.car(id)
    var menu by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    if (car == null) {
        LaunchedEffect(Unit) { nav.pop(AppTab.garage) }
        return
    }
    val info = car.info
    val active = m.activeCarID == car.id
    Column(Modifier.fillMaxSize()) {
        TopBar(info.name, onBack = { nav.pop(AppTab.garage) }) {
            Box {
                RoundIconButton(Icons.Filled.MoreVert) { menu = true }
                DropdownMenu(menu, { menu = false }, containerColor = Theme.panel) {
                    DropdownMenuItem({ Text(L("Modifica"), color = Theme.text) }, { menu = false; nav.push(AppTab.garage, "editor:${car.id}") }, leadingIcon = { Icon(Icons.Filled.Edit, null, tint = Theme.accent) })
                    val code = m.account.garage
                    if (m.garage.isPublic && code != null) {
                        DropdownMenuItem({ Text(L("Condividi quest'auto"), color = Theme.text) }, {
                            menu = false
                            shareText(context, L("%@ nel mio garage su TrackLap", info.name) + "\n" + Server.garageURL(code, car.id))
                        }, leadingIcon = { Icon(Icons.Filled.Share, null, tint = Theme.accent) })
                    }
                    DropdownMenuItem({ Text(L("Sposta prima"), color = Theme.text) }, { menu = false; m.garage.move(car.id, -1) }, leadingIcon = { Icon(Icons.Filled.ArrowUpward, null, tint = Theme.sub) })
                    DropdownMenuItem({ Text(L("Sposta dopo"), color = Theme.text) }, { menu = false; m.garage.move(car.id, 1) }, leadingIcon = { Icon(Icons.Filled.ArrowDownward, null, tint = Theme.sub) })
                    DropdownMenuItem({ Text(L("Elimina l'auto"), color = Theme.bad) }, { menu = false; confirmDelete = true }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Theme.bad) })
                }
            }
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            CarPhotoView(info.photo, Modifier.fillMaxWidth().aspectRatio(1.45f).clip(RoundedCornerShape(22.dp)))
            Column {
                if (active) Badge(L("In uso in Live"))
                Text(info.name, fontSize = 26.sp, fontWeight = FontWeight.Black, color = Theme.text)
                info.year?.let { Text("$it", fontSize = 15.sp, color = Theme.sub) }
            }
            SpecGrid(info)
            if (active) {
                Note(Icons.Filled.CheckCircle, Theme.good, L("La stai usando in Live") + ". " + L("Le prossime sessioni e i tempi in classifica sono con quest'auto."))
                SecondaryButton(L("Non usarla più in Live"), Icons.Filled.Close, Theme.sub) { m.setActiveCar(null) }
            } else {
                PrimaryButton(L("Usa quest'auto in Live"), Icons.Filled.Timer) { m.setActiveCar(car.id) }
            }
            ModsPanel(info)
            SetupsSection(car)
            BestTimes(car)
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false }, containerColor = Theme.panel,
            title = { Text(L("Eliminare %@?", info.name), color = Theme.text) },
            text = { Text(L("Le sessioni restano, senza il collegamento all'auto."), color = Theme.sub) },
            confirmButton = { TextButton({ confirmDelete = false; m.deleteCar(car.id); nav.pop(AppTab.garage) }) { Text(L("Elimina l'auto"), color = Theme.bad) } },
            dismissButton = { TextButton({ confirmDelete = false }) { Text(L("Annulla"), color = Theme.accent) } },
        )
    }
}

@Composable
private fun SetupsSection(car: Car) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val list = m.garage.setups(car.id)
    Row(verticalAlignment = Alignment.CenterVertically) {
        SectionLabel(if (list.isEmpty()) L("Assetti") else L("Assetti (%lld)", list.size), Modifier.weight(1f))
        Text(L("Nuovo"), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Theme.accent, modifier = Modifier.clickable { nav.push(AppTab.garage, "setupEdit:${car.id}:new") })
    }
    if (list.isEmpty()) {
        Panel {
            Text(L("Salva qui i tuoi assetti"), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.text)
            Spacer(Modifier.height(4.dp))
            Text(L("Uno per il bagnato, uno per l'asciutto, uno per pista: pressioni, campanature, ammortizzatori e tutto il resto. Ogni modifica tiene la versione di prima, e ogni sessione si ricorda l'assetto con cui l'hai fatta. Restano solo sul telefono."), fontSize = 13.sp, color = Theme.sub)
        }
    } else {
        for (s in list) SetupRow(s, active = s.id == m.activeSetupID) { nav.push(AppTab.garage, "setup:${s.id}") }
    }
}

/** Your best lap on each track and your drag records, with this car. */
@Composable
private fun BestTimes(car: Car) {
    val m = LocalModel.current
    val bests = m.sessions.summaries.filter { it.carID == car.id && it.best != null }
        .groupBy { it.trackID }.mapNotNull { (_, list) -> list.minByOrNull { it.best ?: Double.MAX_VALUE } }.sortedBy { it.trackName }
    if (bests.isNotEmpty()) {
        SectionLabel(L("I tuoi migliori tempi con quest'auto"))
        Panel(padding = 4.dp) {
            for ((i, s) in bests.withIndex()) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(s.trackName, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text, maxLines = 1)
                        Text(Fmt.dayShort(s.date), fontSize = 11.sp, color = Theme.sub)
                    }
                    Text(Fmt.lap(s.best), style = Theme.numStyle(16.sp, FontWeight.Black, Theme.purple))
                }
                if (i < bests.size - 1) Hairline()
            }
        }
    }
    val records = m.drags.records(car.id)
    val measures = DragMeasure.all().filter { it.headline && records[it.name] != null }
    if (measures.isNotEmpty()) {
        SectionLabel(L("I tuoi migliori Drag con quest'auto"))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (mm in measures) {
                val r = records.getValue(mm.name).result
                StatTile(mm.name, if (r.kind == DragMeasure.Kind.braking) Fmt.shortDistance(r.distance) else Fmt.dragTime(r.time), Modifier.weight(1f),
                    unit = if (r.kind == DragMeasure.Kind.braking) Fmt.shortDistanceUnit else "s", color = Theme.purple)
            }
        }
    }
}

private val COMMON_MODS = listOf("Scarico", "Centralina", "Aspirazione", "Intercooler", "Turbo", "Assetto", "Freni", "Gomme", "Cerchi",
    "Differenziale", "Frizione", "Sedili", "Roll-bar", "Alleggerimento", "Aerodinamica")

/** A new car or a change to one: the photo, the name, the numbers, the mods and the notes. */
@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
fun CarEditorScreen(id: String) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val existing = m.garage.car(id)
    var draft by remember { mutableStateOf(existing ?: Car()) }
    var year by remember { mutableStateOf(existing?.year?.toString() ?: "") }
    var power by remember { mutableStateOf(existing?.power?.let { CarFmt.power(it) } ?: "") }
    var weight by remember { mutableStateOf(existing?.weight?.let { CarFmt.weight(it) } ?: "") }
    var newMod by remember { mutableStateOf("") }
    var loadingPhoto by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            loadingPhoto = true
            val old = draft.photo
            m.garage.storePhoto(uri)?.let { photo ->
                draft = draft.copy(photo = photo)
                // A photo picked and replaced in the same editor goes away.
                if (old != null && old != existing?.photo) m.garage.discardPhoto(old)
            }
            loadingPhoto = false
        }
    }

    fun close(save: Boolean) {
        if (save) {
            m.garage.save(
                draft.copy(
                    name = draft.name.take(Car.MAX_NAME), year = year.toIntOrNull()?.takeIf { it in 1900..2100 },
                    power = power.toIntOrNull()?.let { CarFmt.cv(it) }?.takeIf { it in 1..5000 },
                    weight = weight.toIntOrNull()?.let { CarFmt.kg(it) }?.takeIf { it in 50..10000 },
                    mods = draft.mods.map { it.trim() }.filter { it.isNotEmpty() }, notes = draft.notes.take(Car.MAX_NOTES),
                ),
            )
            if (existing == null && m.activeCarID == null) m.setActiveCar(draft.id)
        } else {
            draft.photo?.let { if (it != existing?.photo) m.garage.discardPhoto(it) }
        }
        nav.pop(AppTab.garage)
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(if (existing == null) L("Nuova auto") else L("Modifica auto"), onBack = { close(false) }) {
            Text(L("Salva"), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Theme.accent, modifier = Modifier.clickable { close(true) })
        }
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(
                Modifier.fillMaxWidth().aspectRatio(1.45f).clip(RoundedCornerShape(22.dp)).border(1.dp, Theme.line, RoundedCornerShape(22.dp))
                    .clickable { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
            ) {
                CarPhotoView(draft.photo?.let { CarPhoto.Local(it) } ?: CarPhoto.Empty, Modifier.fillMaxSize())
                Column(Modifier.align(Alignment.BottomStart).padding(12.dp)) {
                    Row(
                        Modifier.clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(Icons.Filled.AddAPhoto, null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Text(if (draft.photo == null) L("Aggiungi una foto") else L("Cambia"), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
                    }
                    if (draft.photo == null) Text(L("La più bella: è quella che vedono tutti"), fontSize = 11.sp, color = Theme.sub, modifier = Modifier.padding(top = 4.dp))
                }
                if (loadingPhoto) CircularProgressIndicator(Modifier.align(Alignment.Center), color = Theme.accent)
            }
            SectionLabel(L("L'auto"))
            Field(draft.name, L("Marca e modello")) { draft = draft.copy(name = it.take(Car.MAX_NAME)) }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Field(year, L("Anno"), Modifier.weight(1f), number = true) { year = it.filter(Char::isDigit).take(4) }
                Field(power, L("Potenza") + " (" + CarFmt.powerUnit + ")", Modifier.weight(1f), number = true) { power = it.filter(Char::isDigit).take(4) }
                Field(weight, L("Peso") + " (" + CarFmt.weightUnit + ")", Modifier.weight(1f), number = true) { weight = it.filter(Char::isDigit).take(5) }
            }
            val p = power.toIntOrNull()
            val w = weight.toIntOrNull()
            if (p != null && w != null && p > 0) {
                Text(L("Peso/potenza: %@ %@", CarFmt.ratio(CarFmt.kg(w).toDouble() / CarFmt.cv(p)), CarFmt.ratioUnit), fontSize = 12.sp, color = Theme.sub)
            }
            SectionLabel(L("Modifiche"))
            for ((i, mod) in draft.mods.withIndex()) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Field(mod, L("Es. scarico, centralina, freni"), Modifier.weight(1f)) { v -> draft = draft.copy(mods = draft.mods.toMutableList().also { it[i] = v.take(Car.MAX_MOD) }) }
                    Icon(Icons.Filled.Close, L("Togli"), tint = Theme.bad, modifier = Modifier.size(22.dp).clickable { draft = draft.copy(mods = draft.mods.filterIndexed { k, _ -> k != i }) })
                }
            }
            if (draft.mods.size < Car.MAX_MODS) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Field(newMod, L("Aggiungi una modifica"), Modifier.weight(1f)) { newMod = it.take(Car.MAX_MOD) }
                    RoundIconButton(Icons.Filled.Add) {
                        if (newMod.isNotBlank()) {
                            draft = draft.copy(mods = draft.mods + newMod.trim())
                            newMod = ""
                        }
                    }
                }
                androidx.compose.foundation.layout.FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (k in COMMON_MODS) {
                        val label = L(k)
                        if (draft.mods.any { it.equals(label, true) }) continue
                        Text(
                            "+ $label", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.accent,
                            modifier = Modifier.clip(CircleShape).background(Theme.accent.copy(alpha = 0.1f)).clickable { draft = draft.copy(mods = draft.mods + label) }
                                .padding(horizontal = 10.dp, vertical = 5.dp),
                        )
                    }
                }
            }
            SectionLabel(L("Note"))
            OutlinedTextField(
                draft.notes, { draft = draft.copy(notes = it.take(Car.MAX_NOTES)) }, Modifier.fillMaxWidth().height(120.dp),
                placeholder = { Text(L("Gomme, assetto, com'è in pista…"), color = Theme.sub) }, colors = fieldColors(), shape = RoundedCornerShape(14.dp),
            )
            PrimaryButton(L("Salva"), Icons.Filled.CheckCircle) { close(true) }
        }
    }
}

@Composable
fun Field(value: String, label: String, modifier: Modifier = Modifier.fillMaxWidth(), number: Boolean = false, set: (String) -> Unit) {
    OutlinedTextField(
        value, set, modifier, singleLine = true, label = { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        keyboardOptions = if (number) KeyboardOptions(keyboardType = KeyboardType.Number) else KeyboardOptions.Default,
        colors = fieldColors(), shape = RoundedCornerShape(14.dp),
    )
}

/** Someone's public garage, from a link or a leaderboard: their cars, opened on the one asked for. */
@Composable
fun PublicGarageScreen(link: GarageLink, onClose: () -> Unit) {
    val m = LocalModel.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var garage by remember { mutableStateOf<PublicGarage?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var openCar by remember { mutableStateOf(link.car) }
    var reporting by remember { mutableStateOf(false) }
    var reported by remember { mutableStateOf(false) }
    var attempt by remember { mutableStateOf(0) }
    LaunchedEffect(link, attempt) {
        error = null
        runCatching { Server.garage(link.code, m.account.token) }.onSuccess { garage = it }.onFailure { error = it.message }
    }
    val g = garage
    Column(Modifier.fillMaxSize().background(Theme.bg)) {
        val car = g?.cars?.firstOrNull { it.id == openCar }
        TopBar(
            if (car != null) car.name else g?.let { L("Il garage di %@", it.name) } ?: L("Garage"),
            onBack = { if (car != null) openCar = null else onClose() },
        ) {
            if (g != null) RoundIconButton(Icons.Filled.Share) { shareText(context, L("Il garage di %@", g.name) + "\n" + Server.garageURL(g.code, openCar)) }
        }
        when {
            error != null -> Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(error ?: "", fontSize = 15.sp, color = Theme.sub)
                SecondaryButton(L("Riprova"), Icons.Filled.Refresh) { attempt += 1 }
            }
            g == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Theme.accent) }
            car != null -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                val info = g.info(car) { Server.photoURL(g.code, it) }
                CarPhotoView(info.photo, Modifier.fillMaxWidth().aspectRatio(1.45f).clip(RoundedCornerShape(22.dp)))
                Text(L("Dal garage di %@", g.name), fontSize = 13.sp, color = Theme.sub)
                Text(info.name, fontSize = 26.sp, fontWeight = FontWeight.Black, color = Theme.text)
                SpecGrid(info)
                ModsPanel(info)
                if (g.mine != true) SecondaryButton(L("Segnala"), Icons.Filled.Flag, Theme.bad) { reporting = true }
            }
            else -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L("Il garage di %@", g.name), fontSize = 24.sp, fontWeight = FontWeight.Black, color = Theme.text)
                Text(if (g.cars.size == 1) L("1 auto") else L("%lld auto", g.cars.size), fontSize = 14.sp, color = Theme.sub)
                if (g.cars.isEmpty()) {
                    Panel {
                        Text(L("Nessuna auto in questo garage"), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                        Text(L("Le auto compaiono qui quando il pilota le mostra a tutti."), fontSize = 13.sp, color = Theme.sub)
                    }
                }
                for (row in g.cars.chunked(2)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        for (c in row) InfoCard(g.info(c) { Server.photoURL(g.code, it) }, Modifier.weight(1f)) { openCar = c.id }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                if (g.mine != true) SecondaryButton(L("Segnala"), Icons.Filled.Flag, Theme.bad) { reporting = true }
            }
        }
    }
    if (reporting && g != null) {
        AlertDialog(
            onDismissRequest = { reporting = false }, containerColor = Theme.panel,
            title = { Text(L("Perché lo segnali?"), color = Theme.text) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(L("La segnalazione arriva a chi gestisce TrackLap. Con più segnalazioni il garage viene nascosto finché non viene controllato."), fontSize = 13.sp, color = Theme.sub)
                    for ((key, reason) in listOf("photo" to L("Foto inadatta"), "text" to L("Testo offensivo"), "notTheirs" to L("Non è la sua auto"), "spam" to L("Spam"))) {
                        Text(reason, fontSize = 15.sp, color = Theme.accent, modifier = Modifier.fillMaxWidth().clickable {
                            reporting = false
                            scope.launch { runCatching { Server.report(g.code, openCar, key) }; reported = true }
                        }.padding(vertical = 10.dp))
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton({ reporting = false }) { Text(L("Annulla"), color = Theme.sub) } },
        )
    }
    if (reported) {
        AlertDialog(
            onDismissRequest = { reported = false }, containerColor = Theme.panel,
            title = { Text(L("Grazie della segnalazione"), color = Theme.text) },
            text = { Text(L("La controlliamo il prima possibile."), color = Theme.sub) },
            confirmButton = { TextButton({ reported = false }) { Text("OK", color = Theme.accent) } },
        )
    }
}

/** The car in use, under the header of Live and Drag: tap to pick another. */
@Composable
fun ActiveCarChip() {
    val m = LocalModel.current
    var open by remember { mutableStateOf(false) }
    val car = m.activeCar
    Box {
        Row(
            Modifier.clip(CircleShape).background(Theme.panel).border(1.dp, if (car != null) Theme.accent.copy(alpha = 0.5f) else Theme.line, CircleShape)
                .clickable { open = true }.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(Icons.Filled.DirectionsCar, null, tint = if (car != null) Theme.accent else Theme.sub, modifier = Modifier.size(14.dp))
            Text(car?.displayName ?: L("Scegli l'auto"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        DropdownMenu(open, { open = false }, containerColor = Theme.panel) {
            Text(L("Auto in uso"), fontSize = 12.sp, color = Theme.sub, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            DropdownMenuItem({ Text(L("Nessuna"), color = Theme.text) }, { open = false; m.setActiveCar(null) },
                leadingIcon = { if (car == null) Icon(Icons.Filled.CheckCircle, null, tint = Theme.accent) })
            for (c in m.garage.cars) {
                DropdownMenuItem({ Text(c.displayName, color = Theme.text) }, { open = false; m.setActiveCar(c.id) },
                    leadingIcon = { if (c.id == car?.id) Icon(Icons.Filled.CheckCircle, null, tint = Theme.accent) })
            }
            DropdownMenuItem({ Text(if (m.garage.cars.isEmpty()) L("Aggiungi un'auto al garage") else L("Apri il garage"), color = Theme.accent) },
                { open = false; m.tab = AppTab.garage }, leadingIcon = { Icon(Icons.Filled.DirectionsCar, null, tint = Theme.accent) })
        }
    }
}

/** The setup in use with the active car, next to its chip. */
@Composable
fun ActiveSetupChip() {
    val m = LocalModel.current
    val car = m.activeCar ?: return
    val list = m.garage.setups(car.id)
    if (list.isEmpty()) return
    var open by remember { mutableStateOf(false) }
    val s = m.activeSetup
    Box {
        Row(
            Modifier.clip(CircleShape).background(Theme.panel).border(1.dp, if (s != null) Theme.yellow.copy(alpha = 0.5f) else Theme.line, CircleShape)
                .clickable { open = true }.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            WeatherGlyph(s?.weather, 14.dp)
            Text(s?.displayName ?: L("Assetto"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        DropdownMenu(open, { open = false }, containerColor = Theme.panel) {
            Text(L("Assetto in uso"), fontSize = 12.sp, color = Theme.sub, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            DropdownMenuItem({ Text(L("Nessuno"), color = Theme.text) }, { open = false; m.setActiveSetup(null) },
                leadingIcon = { if (s == null) Icon(Icons.Filled.CheckCircle, null, tint = Theme.accent) })
            for (x in list) {
                DropdownMenuItem({ Text(x.displayName + " · " + L("v%lld", x.version), color = Theme.text) }, { open = false; m.setActiveSetup(x.id) },
                    leadingIcon = { if (x.id == s?.id) Icon(Icons.Filled.CheckCircle, null, tint = Theme.accent) else WeatherGlyph(x.weather, 18.dp) })
            }
        }
    }
}
