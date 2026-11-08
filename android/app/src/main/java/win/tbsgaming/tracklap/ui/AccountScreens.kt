package win.tbsgaming.tracklap.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import win.tbsgaming.tracklap.AppTab
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalNav
import win.tbsgaming.tracklap.data.DriverProfile
import win.tbsgaming.tracklap.data.Server

/** Sign in, or make a new account: the username everyone sees, a password of at least 8 characters. */
@Composable
fun SignInScreen(tab: AppTab) {
    val m = LocalModel.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    var creating by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var repeated by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val nameOK = Server.isValidName(name.trim())
    val ready = if (creating) nameOK && password.length >= 8 && password == repeated else name.isNotBlank() && password.isNotEmpty()

    fun go() {
        if (!ready || busy) return
        busy = true
        error = null
        scope.launch {
            runCatching { if (creating) m.account.signUp(name, password) else m.account.signIn(name, password) }
                .onSuccess { nav.pop(tab) }
                .onFailure { error = it.message }
            busy = false
        }
    }

    Column(Modifier.fillMaxSize()) {
        TopBar(if (creating) L("Crea il tuo account") else L("Accedi a TrackLap"), onBack = { nav.pop(tab) })
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(L("Per mostrare il garage a tutti e mettere i tuoi tempi nelle classifiche delle piste, con il veicolo con cui li hai fatti."), fontSize = 14.sp, color = Theme.sub)
            Segmented(listOf(L("Accedi") to false, L("Nuovo account") to true), creating) { creating = it; error = null }
            OutlinedTextField(
                name, { name = it.take(20) }, Modifier.fillMaxWidth(), singleLine = true, label = { Text(L("Nome utente")) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii, imeAction = ImeAction.Next), colors = fieldColors(), shape = RoundedCornerShape(14.dp),
            )
            OutlinedTextField(
                password, { password = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text(L("Password")) },
                visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                colors = fieldColors(), shape = RoundedCornerShape(14.dp),
            )
            if (creating) {
                OutlinedTextField(
                    repeated, { repeated = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text(L("Ripeti la password")) },
                    visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    colors = fieldColors(), shape = RoundedCornerShape(14.dp),
                )
                Rule(nameOK, L("Nome utente da 3 a 20 caratteri: lettere, numeri, . - _ (è quello che vedono tutti)"))
                Rule(password.length >= 8, L("Password di almeno 8 caratteri"))
                Rule(repeated.isNotEmpty() && password == repeated, L("Le due password sono uguali"))
            }
            error?.let { Note(Icons.Filled.Warning, Theme.bad, it) }
            PrimaryButton(if (creating) L("Crea l'account") else L("Accedi"), Icons.Filled.Person, enabled = ready && !busy) { go() }
            Text(L("Il server di TrackLap tiene il nome utente e la password protetta (mai in chiaro). Puoi eliminare l'account quando vuoi da Dispositivo."), fontSize = 12.sp, color = Theme.sub)
        }
        if (busy) ProgressOverlay(if (creating) L("Crea l'account") else L("Accedi"))
    }
}

@Composable
private fun Rule(ok: Boolean, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(if (ok) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null, tint = if (ok) Theme.good else Theme.sub, modifier = Modifier.size(16.dp))
        Text(text, fontSize = 12.sp, color = if (ok) Theme.text else Theme.sub)
    }
}

/** The account in Dispositivo: who you are, the password, signing out and deleting it. */
@Composable
fun AccountPanel() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val scope = rememberCoroutineScope()
    val a = m.account
    var confirmSignOut by remember { mutableStateOf(false) }
    var passwordMode by remember { mutableStateOf<String?>(null) }
    Panel {
        if (a.isSignedIn) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AppGlyph(Icons.Filled.Person, 40.dp, Theme.good)
                Column(Modifier.weight(1f)) {
                    Text(a.name ?: "", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                    Text(m.garage.audience.summary, fontSize = 12.sp, color = Theme.sub)
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SecondaryButton(L("Password"), Icons.Filled.Key, modifier = Modifier.weight(1f)) { passwordMode = "change" }
                SecondaryButton(L("Esci"), Icons.AutoMirrored.Filled.Logout, Theme.bad, modifier = Modifier.weight(1f)) { confirmSignOut = true }
            }
            Spacer(Modifier.height(10.dp))
            Text(L("Elimina l'account"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.bad,
                modifier = Modifier.clickableNoRipple { passwordMode = "delete" })
        } else {
            Text(L("Con un account mostri il garage a tutti e i tuoi tempi entrano nelle classifiche delle piste con il tuo nome e il tuo veicolo."), fontSize = 13.sp, color = Theme.sub)
            Spacer(Modifier.height(12.dp))
            PrimaryButton(L("Accedi o crea un account"), Icons.Filled.Person) { nav.push(AppTab.device, "account") }
        }
    }
    if (confirmSignOut) {
        AlertDialog(
            onDismissRequest = { confirmSignOut = false }, containerColor = Theme.panel,
            title = { Text(L("Uscire dall'account?"), color = Theme.text) },
            text = { Text(L("Il garage resta sul telefono e online. Per pubblicare di nuovo basta accedere."), color = Theme.sub) },
            confirmButton = { TextButton({ confirmSignOut = false; scope.launch { a.signOut() } }) { Text(L("Esci"), color = Theme.bad) } },
            dismissButton = { TextButton({ confirmSignOut = false }) { Text(L("Annulla"), color = Theme.accent) } },
        )
    }
    passwordMode?.let { mode -> PasswordDialog(delete = mode == "delete") { passwordMode = null } }
}

/** Change the password, or delete the account for good: both ask for the password of now. */
@Composable
private fun PasswordDialog(delete: Boolean, done: () -> Unit) {
    val m = LocalModel.current
    val scope = rememberCoroutineScope()
    var current by remember { mutableStateOf("") }
    var new by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val ready = current.isNotEmpty() && (delete || new.length >= 8)
    AlertDialog(
        onDismissRequest = { if (!busy) done() }, containerColor = Theme.panel,
        title = { Text(if (delete) L("Elimina l'account") else L("Cambia password"), color = Theme.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (delete) {
                    Note(Icons.Filled.Warning, Theme.bad, L("Non si torna indietro"))
                    Text(L("Vengono cancellati dal server l'account, il garage online con le foto e tutti i tuoi tempi nelle classifiche. I veicoli e le sessioni sul telefono restano."), fontSize = 13.sp, color = Theme.sub)
                }
                OutlinedTextField(
                    current, { current = it }, Modifier.fillMaxWidth(), singleLine = true,
                    label = { Text(if (delete) L("La tua password") else L("Password attuale")) },
                    visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), colors = fieldColors(),
                )
                if (!delete) {
                    OutlinedTextField(
                        new, { new = it }, Modifier.fillMaxWidth(), singleLine = true, label = { Text(L("Nuova password (almeno 8 caratteri)")) },
                        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), colors = fieldColors(),
                    )
                    Text(L("Gli altri telefoni con questo account escono e devono accedere con la nuova password."), fontSize = 12.sp, color = Theme.sub)
                }
                error?.let { Text(it, fontSize = 13.sp, color = Theme.bad) }
            }
        },
        confirmButton = {
            TextButton({
                if (!ready || busy) return@TextButton
                busy = true
                error = null
                scope.launch {
                    runCatching { if (delete) m.account.delete(current) else m.account.changePassword(current, new) }
                        .onSuccess { done() }
                        .onFailure { error = it.message }
                    busy = false
                }
            }, enabled = ready && !busy) { Text(if (delete) L("Elimina per sempre") else L("Cambia password"), color = if (delete) Theme.bad else Theme.accent) }
        },
        dismissButton = { TextButton({ if (!busy) done() }) { Text(L("Annulla"), color = Theme.sub) } },
    )
}

/** Your name and vehicle for your friends, and the switch that sends your best laps to the leaderboards. */
@Composable
fun FriendsPanel() {
    val m = LocalModel.current
    val p = m.profile
    Panel {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                p.name, { p.setName(it); m.group.profileChanged() }, Modifier.fillMaxWidth(), singleLine = true, label = { Text(L("Il tuo nome")) },
                colors = fieldColors(), shape = RoundedCornerShape(14.dp),
            )
            OutlinedTextField(
                p.vehicle, { p.setVehicle(it.take(DriverProfile.MAX)); m.group.profileChanged() }, Modifier.fillMaxWidth(), singleLine = true,
                label = { Text(L("Auto o moto (facoltativo)")) }, colors = fieldColors(), shape = RoundedCornerShape(14.dp),
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(L("Pubblica i miei best"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
                    Text(L("Il giro migliore di ogni sessione va nella classifica online della sua pista, con il nome del tuo account e il veicolo in uso. Mai i giri della Demo."), fontSize = 12.sp, color = Theme.sub)
                }
                Switch(p.publishLaps, { p.setPublish(it) }, enabled = m.account.isSignedIn,
                    colors = SwitchDefaults.colors(checkedTrackColor = Theme.accent, checkedThumbColor = Color.Black))
            }
            if (!m.account.isSignedIn) Text(L("Per pubblicare i tempi serve un account: lo crei qui sopra."), fontSize = 12.sp, color = Theme.yellow)
            Text(
                L("I gruppi live, le classifiche e il garage pubblico passano dal server di TrackLap: riceve il nome, il veicolo, i tempi, i veicoli che mostri con le loro foto e, solo mentre sei in un gruppo, la posizione in pista."),
                fontSize = 12.sp, color = Theme.sub,
            )
        }
    }
}
