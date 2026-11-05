package win.tbsgaming.tracklap.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
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
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bluetooth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import win.tbsgaming.tracklap.BuildConfig
import win.tbsgaming.tracklap.DeltaReference
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalPermissions
import win.tbsgaming.tracklap.SourceKind
import win.tbsgaming.tracklap.gps.BleManager
import win.tbsgaming.tracklap.model.Units
import kotlin.math.roundToInt

@Composable
fun DeviceScreen() {
    val m = LocalModel.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        ScreenHeader(Icons.Filled.Sensors, L("Dispositivo"), m.source.title)
        SectionLabel(L("Sorgente GPS"))
        for (k in SourceKind.entries) SourceCard(k)
        when (m.source) {
            SourceKind.device -> BleSection()
            SourceKind.phone -> PhoneSection()
            SourceKind.demo -> DemoSection()
        }
        SectionLabel(L("Cronometro"))
        SettingsPanel()
        SectionLabel(L("Account"))
        AccountPanel()
        SectionLabel(L("Tu e gli amici"))
        FriendsPanel()
        SectionLabel(L("Informazioni"))
        AboutPanel()
    }
}

@Composable
private fun SourceCard(k: SourceKind) {
    val m = LocalModel.current
    val permissions = LocalPermissions.current
    val selected = m.source == k
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(if (selected) Theme.accent.copy(alpha = 0.1f) else Theme.panel)
            .border(if (selected) 1.5.dp else 1.dp, if (selected) Theme.accent else Theme.line.copy(alpha = 0.8f), shape)
            .clickable {
                m.setSource(k)
                if (k == SourceKind.phone && !m.phone.hasPermission()) permissions.location()
                if (k == SourceKind.device && !m.ble.hasPermission()) permissions.bluetooth()
            }.padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AppGlyph(k.icon, 40.dp, if (selected) Theme.accent else Theme.sub)
        Column(Modifier.weight(1f)) {
            Text(k.title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
            Text(k.detail, fontSize = 12.sp, color = Theme.sub)
        }
        Icon(if (selected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (selected) Theme.accent else Theme.line, modifier = Modifier.size(22.dp))
    }
}

@Composable
private fun BleSection() {
    val m = LocalModel.current
    val ble = m.ble
    val permissions = LocalPermissions.current
    val context = LocalContext.current
    var pins by remember { mutableStateOf(false) }
    SectionLabel("ESP32")
    Panel(glow = if (ble.state == BleManager.State.connected) Theme.good else null) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AppGlyph(Icons.Filled.Bluetooth, 40.dp, if (ble.state == BleManager.State.connected) Theme.good else Theme.sub)
                Column(Modifier.weight(1f)) {
                    Text(ble.stateTitle, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                    Text(ble.stateDetail, fontSize = 12.sp, color = Theme.sub)
                }
            }
            when (ble.state) {
                BleManager.State.unauthorized -> PrimaryButton(L("Consenti il Bluetooth"), Icons.Filled.Bluetooth) { permissions.bluetooth() }
                BleManager.State.off -> SecondaryButton(L("Apri le impostazioni Bluetooth"), Icons.Filled.Bluetooth) {
                    context.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
                BleManager.State.connected -> {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        StatTile(L("Satelliti"), "${ble.sats}", Modifier.weight(1f), color = if (ble.sats >= 8) Theme.good else Theme.yellow)
                        StatTile(L("Frequenza"), "${ble.rateHz}", Modifier.weight(1f), unit = "Hz")
                        StatTile(L("Firmware"), ble.info?.fw ?: "—", Modifier.weight(1f))
                    }
                    ble.info?.let { info ->
                        if (info.gps.isNullOrEmpty()) Note(Icons.Filled.Warning, Theme.yellow, L("Nessun GPS risponde: controlla i fili e i pin."))
                        else Text(L("Modulo GPS: %@", info.gps), fontSize = 12.sp, color = Theme.sub)
                        if (info.rx != null && info.tx != null) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(L("GPS su RX %lld · TX %lld", info.rx, info.tx), style = Theme.numStyle(12.sp, FontWeight.Normal, Theme.sub), modifier = Modifier.weight(1f))
                                Text(L("Cambia pin"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Theme.accent, modifier = Modifier.clickable { pins = true })
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        SecondaryButton(L("Invia pista"), Icons.AutoMirrored.Filled.Send, modifier = Modifier.weight(1f), enabled = m.selectedTrack?.isReady == true) {
                            m.selectedTrack?.let { ble.sendTrack(it) }
                        }
                        SecondaryButton(L("Scollega"), Icons.Filled.Close, Theme.bad, modifier = Modifier.weight(1f)) { ble.disconnect() }
                    }
                }
                else -> {
                    for (d in ble.devices) {
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Theme.input).clickable { ble.connect(d) }.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Icon(Icons.Filled.Sensors, null, tint = Theme.accent, modifier = Modifier.size(20.dp))
                            Text(d.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Theme.text, modifier = Modifier.weight(1f))
                            Text("${d.rssi} dBm", style = Theme.numStyle(12.sp, FontWeight.Normal, Theme.sub))
                        }
                    }
                    val scanning = ble.state == BleManager.State.scanning
                    PrimaryButton(if (scanning) L("Ferma la ricerca") else L("Cerca dispositivi"), if (scanning) Icons.Filled.Stop else Icons.Filled.Search) {
                        if (!ble.hasPermission()) permissions.bluetooth() else if (scanning) ble.stopScan() else ble.scan()
                    }
                }
            }
        }
    }
    if (pins) PinsDialog(ble.info?.rx ?: 17, ble.info?.tx ?: 16, onDismiss = { pins = false }) { rx, tx ->
        ble.setGpsPins(rx, tx)
        pins = false
    }
}

@Composable
private fun PinsDialog(rx0: Int, tx0: Int, onDismiss: () -> Unit, save: (Int?, Int?) -> Unit) {
    var rx by remember { mutableIntStateOf(rx0) }
    var tx by remember { mutableIntStateOf(tx0) }
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = Theme.panel,
        title = { Text(L("Pin del GPS"), color = Theme.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(L("Il TX del GPS va sul pin RX dell'ESP32, l'RX del GPS sul pin TX. L'ESP32 salva i pin e si riavvia."), fontSize = 13.sp, color = Theme.sub)
                PinStepper(L("RX, dal TX del GPS"), rx) { rx = it }
                PinStepper(L("TX, verso l'RX del GPS"), tx) { tx = it }
                Text(L("Pin predefiniti del chip"), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Theme.accent, modifier = Modifier.clickable { save(null, null) })
            }
        },
        confirmButton = { TextButton({ save(rx, tx) }) { Text(L("Salva e riavvia"), color = Theme.accent) } },
        dismissButton = { TextButton(onDismiss) { Text(L("Annulla"), color = Theme.sub) } },
    )
}

@Composable
private fun PinStepper(title: String, value: Int, set: (Int) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, fontSize = 14.sp, color = Theme.text, modifier = Modifier.weight(1f))
        StepButton("−") { set((value - 1).coerceAtLeast(0)) }
        Text("$value", style = Theme.numStyle(16.sp), modifier = Modifier.padding(horizontal = 6.dp))
        StepButton("+") { set((value + 1).coerceAtMost(48)) }
    }
}

@Composable
private fun StepButton(text: String, onClick: () -> Unit) {
    Box(Modifier.size(36.dp).clip(CircleShape).background(Theme.button).clickable(onClick = onClick), contentAlignment = Alignment.Center) {
        Text(text, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Theme.accent)
    }
}

@Composable
private fun PhoneSection() {
    val m = LocalModel.current
    val permissions = LocalPermissions.current
    val context = LocalContext.current
    SectionLabel(L("Telefono"))
    Panel {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile(L("Precisione"), m.phone.accuracy?.roundToInt()?.toString() ?: "—", Modifier.weight(1f), unit = "m")
                StatTile(L("Frequenza"), Fmt.hz(m.gpsRate), Modifier.weight(1f))
            }
            if (!m.phone.hasPermission()) {
                Text(L("Posizione negata: abilitala in Impostazioni → TrackLap → Posizione."), fontSize = 12.sp, color = Theme.bad)
                SecondaryButton(L("Consenti la posizione"), Icons.Filled.Sensors) { permissions.location() }
                SecondaryButton(L("Apri le impostazioni"), Icons.Filled.Refresh) {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }
            } else {
                Text(L("TrackLap tiene lo schermo acceso mentre cronometra: lascia il telefono nel supporto."), fontSize = 12.sp, color = Theme.sub)
            }
        }
    }
}

@Composable
private fun DemoSection() {
    val m = LocalModel.current
    SectionLabel("Demo")
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(L("Ritmo del pilota"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text, modifier = Modifier.weight(1f))
            Text("${(m.demo.pace * 100).roundToInt()}%", style = Theme.numStyle(14.sp, FontWeight.Bold, Theme.accent))
        }
        Slider(
            m.demo.pace.toFloat(), { m.demo.pace = (it * 100).roundToInt() / 100.0 }, valueRange = 0.85f..1.05f,
            colors = SliderDefaults.colors(thumbColor = Theme.accent, activeTrackColor = Theme.accent, inactiveTrackColor = Theme.line),
        )
        Text(L("L'auto segue il tracciato di OpenStreetMap quando forma un anello chiuso; altrimenti gira su un circuito generato che passa dalla tua linea del via."), fontSize = 12.sp, color = Theme.sub)
    }
}

@Composable
private fun SettingsPanel() {
    val m = LocalModel.current
    Panel {
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(L("Giro minimo: %lld s", m.minLapTime.toInt()), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
                    Text(L("Passaggi sul via più ravvicinati vengono ignorati."), fontSize = 12.sp, color = Theme.sub)
                }
                StepButton("−") { m.setMinLapTime((m.minLapTime - 5).coerceAtLeast(5.0)) }
                StepButton("+") { m.setMinLapTime((m.minLapTime + 5).coerceAtMost(180.0)) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L("Scala della barra del delta"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
                Segmented(listOf("± 0,5 s" to 0.5, "± 1 s" to 1.0, "± 2 s" to 2.0, "± 5 s" to 5.0), m.deltaScale) { m.setDeltaScale(it) }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L("Delta rispetto a"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
                Segmented(DeltaReference.entries.map { it.title to it }, m.deltaReference) { m.setDeltaReference(it) }
                Text(L("Il record è il giro più veloce delle sessioni precedenti su questa pista."), fontSize = 12.sp, color = Theme.sub)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(L("Annuncio vocale"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
                    Text(L("A fine giro legge tempo e distacco, nel Drag i tempi principali, abbassando la musica."), fontSize = 12.sp, color = Theme.sub)
                }
                Switch(m.voiceOn, { m.setVoice(it) }, colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Color.Black))
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(L("Unità"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
                Segmented(Units.entries.map { it.title to it }, m.units) { m.setUnits(it) }
            }
        }
    }
}

@Composable
fun <T> Segmented(options: List<Pair<String, T>>, selected: T, pick: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Theme.input).padding(3.dp)) {
        for ((title, value) in options) {
            val on = value == selected
            Text(
                title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (on) Theme.text else Theme.sub, maxLines = 1,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(if (on) Theme.button else Color.Transparent)
                    .clickable { pick(value) }.padding(vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun AboutPanel() {
    val m = LocalModel.current
    Panel {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AboutRow(L("Versione"), "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
            AboutRow(L("Protocollo BLE"), "TrackLap v1")
            AboutRow(L("Mappe e piste"), "© OpenStreetMap")
            AboutRow(L("Immagini satellitari"), "© Esri, Maxar")
            Text(L("Il cronometraggio interpola il passaggio sulla linea tra due fix GPS: a 10 Hz la precisione è di qualche centesimo."), fontSize = 12.sp, color = Theme.sub)
            SecondaryButton(L("Rivedi l'introduzione"), Icons.Filled.AutoAwesome) { m.setIntroSeen(false) }
        }
    }
}

@Composable
private fun AboutRow(title: String, value: String) {
    Row {
        Text(title, fontSize = 14.sp, color = Theme.text, modifier = Modifier.weight(1f))
        Text(value, fontSize = 14.sp, color = Theme.sub)
    }
}
