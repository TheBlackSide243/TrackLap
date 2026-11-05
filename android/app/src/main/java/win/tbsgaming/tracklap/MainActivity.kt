package win.tbsgaming.tracklap

import android.Manifest
import android.content.Intent
import android.net.Uri
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.TextButton
import win.tbsgaming.tracklap.ui.CarDetailScreen
import win.tbsgaming.tracklap.ui.CarEditorScreen
import win.tbsgaming.tracklap.ui.FriendDetailScreen
import win.tbsgaming.tracklap.ui.FriendInviteDialog
import win.tbsgaming.tracklap.ui.FriendLapsScreen
import win.tbsgaming.tracklap.ui.FriendsScreen
import win.tbsgaming.tracklap.ui.GarageScreen
import win.tbsgaming.tracklap.ui.LeaderboardScreen
import win.tbsgaming.tracklap.ui.PublicGarageScreen
import win.tbsgaming.tracklap.ui.SetupDetailScreen
import win.tbsgaming.tracklap.ui.SetupEditorScreen
import win.tbsgaming.tracklap.ui.SetupImportDialog
import win.tbsgaming.tracklap.ui.SignInScreen
import android.os.Build
import android.os.Bundle
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Sensors
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import win.tbsgaming.tracklap.ui.DeviceScreen
import win.tbsgaming.tracklap.ui.DragRunScreen
import win.tbsgaming.tracklap.ui.DragScreen
import win.tbsgaming.tracklap.ui.IntroScreen
import win.tbsgaming.tracklap.ui.L
import win.tbsgaming.tracklap.ui.LiveScreen
import win.tbsgaming.tracklap.ui.SessionDetailScreen
import win.tbsgaming.tracklap.ui.SessionsScreen
import win.tbsgaming.tracklap.ui.Theme
import win.tbsgaming.tracklap.ui.TrackEditorScreen
import win.tbsgaming.tracklap.ui.TrackSearchScreen
import win.tbsgaming.tracklap.ui.TracksScreen

val LocalModel = staticCompositionLocalOf<AppModel> { error("no model") }
val LocalNav = staticCompositionLocalOf<Nav> { error("no nav") }
val LocalPermissions = staticCompositionLocalOf<Permissions> { error("no permissions") }

/** Each tab's own pages above its first one: "run:<id>", "search", "editor:<id>", "session:<id>". */
class Nav {
    private val stacks = mutableStateMapOf<AppTab, List<String>>()
    fun top(tab: AppTab): String? = stacks[tab]?.lastOrNull()
    fun push(tab: AppTab, route: String) { stacks[tab] = (stacks[tab] ?: emptyList()) + route }
    fun pop(tab: AppTab) { stacks[tab] = (stacks[tab] ?: emptyList()).dropLast(1) }
    fun replaceTop(tab: AppTab, route: String) { stacks[tab] = (stacks[tab] ?: emptyList()).dropLast(1) + route }
    fun depth(tab: AppTab) = stacks[tab]?.size ?: 0
}

/** The permissions the app asks for when it needs them: location for the phone's GPS, Bluetooth for the ESP32. */
class Permissions(private val ask: (Array<String>) -> Unit) {
    fun location() = ask(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
    fun bluetooth() = ask(
        if (Build.VERSION.SDK_INT >= 31) arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
    )
}

class MainActivity : ComponentActivity() {
    private val model by lazy { shared ?: AppModel(applicationContext).also { shared = it } }
    private val nav by lazy { sharedNav ?: Nav().also { sharedNav = it } }

    private val request = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        model.permissionsChanged()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(SystemBarStyle.dark(android.graphics.Color.TRANSPARENT), SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        val permissions = Permissions { request.launch(it) }
        if (model.source == SourceKind.phone && !model.phone.hasPermission()) permissions.location()
        if (model.source == SourceKind.device && !model.ble.hasPermission()) permissions.bluetooth()
        setContent {
            CompositionLocalProvider(LocalModel provides model, LocalNav provides nav, LocalPermissions provides permissions) {
                Root()
            }
        }
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** A tracklap:// link (a group's QR, a garage page, a friend invitation), or a .tracklap / .tracklapsetup file from another app. */
    private fun handle(intent: Intent?) {
        intent ?: return
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            else -> null
        }
        uri ?: return
        if (uri.scheme == "tracklap") {
            model.openLink(uri)
            return
        }
        val text = runCatching {
            contentResolver.openInputStream(uri)?.use { it.readBytes().takeIf { b -> b.size < 20_000_000 }?.toString(Charsets.UTF_8) }
        }.getOrNull()
        if (text != null) model.openFile(text) else model.notice = L("Questo file non è un giro di TrackLap.")
        setIntent(Intent())
    }

    override fun onResume() {
        super.onResume()
        model.resume()
    }

    override fun onPause() {
        super.onPause()
        model.pause()
    }

    @Composable
    private fun Root() {
        val m = LocalModel.current
        // The screen stays on while timing: the phone sits in its mount.
        val awake = m.isRunning || (m.dragOn && m.drag.inProgress)
        LaunchedEffect(awake) {
            if (awake) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        LaunchedEffect(m.tab) { m.setDragMode(m.tab == AppTab.drag) }
        Box(Modifier.fillMaxSize().background(Theme.bg)) {
            if (!m.introSeen) IntroScreen { m.setIntroSeen(true) } else Tabs()
            m.shownGarage?.let { link ->
                BackHandler { m.shownGarage = null }
                Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) { PublicGarageScreen(link) { m.shownGarage = null } }
            }
        }
        m.importedSetup?.let { SetupImportDialog(it) { m.importedSetup = null } }
        // A friend invitation: accepted here, or after signing in (the dialog waits while you do).
        val nav = LocalNav.current
        m.pendingInvite?.takeIf { !(m.tab == AppTab.friends && nav.top(AppTab.friends) == "account") }?.let { code ->
            FriendInviteDialog(code, signIn = {
                m.tab = AppTab.friends
                nav.push(AppTab.friends, "account")
            }) { m.pendingInvite = null }
        }
        m.notice?.let { text ->
            AlertDialog(
                onDismissRequest = { m.notice = null }, containerColor = Theme.panel,
                text = { Text(text, color = Theme.text) },
                confirmButton = { TextButton({ m.notice = null }) { Text("OK", color = Theme.accent) } },
            )
        }
    }

    companion object {
        private var shared: AppModel? = null
        private var sharedNav: Nav? = null
    }
}

private data class TabItem(val tab: AppTab, val title: String, val icon: ImageVector)

private fun tabItems() = listOf(
    TabItem(AppTab.live, L("Live"), Icons.Filled.Timer),
    TabItem(AppTab.drag, "Drag", Icons.Filled.Speed),
    TabItem(AppTab.tracks, L("Piste"), Icons.Filled.Map),
    TabItem(AppTab.sessions, L("Sessioni"), Icons.Filled.BarChart),
    TabItem(AppTab.garage, L("Garage"), Icons.Filled.DirectionsCar),
    TabItem(AppTab.friends, L("Amici"), Icons.Filled.People),
    TabItem(AppTab.device, L("Dispositivo"), Icons.Filled.Sensors),
)

@Composable
private fun Tabs() {
    val m = LocalModel.current
    val nav = LocalNav.current
    val states = rememberSaveableStateHolder()
    BackHandler(enabled = nav.depth(m.tab) > 0) { nav.pop(m.tab) }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // On its side in the car mount: the tabs go in a column on the right, where the thumb is.
        val side = maxWidth > maxHeight
        val content: @Composable (Modifier) -> Unit = { mod ->
            val sides = if (side) WindowInsetsSides.Vertical + WindowInsetsSides.Start else WindowInsetsSides.Top + WindowInsetsSides.Horizontal
            Box(mod.windowInsetsPadding(WindowInsets.safeDrawing.only(sides))) {
                AnimatedContent(m.tab to nav.top(m.tab), transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "page") { (tab, route) ->
                    states.SaveableStateProvider(tab.name + "/" + (route ?: "")) { Page(tab, route) }
                }
            }
        }
        if (side) {
            Row(Modifier.fillMaxSize()) {
                content(Modifier.weight(1f).fillMaxHeight())
                // A phone on its side is short: seven tabs fit as icons alone.
                SideBar(compact = maxHeight < 480.dp)
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                content(Modifier.weight(1f).fillMaxWidth())
                BottomBar()
            }
        }
    }
}

@Composable
private fun Page(tab: AppTab, route: String?) {
    when {
        route == "account" -> SignInScreen(tab)
        tab == AppTab.live -> LiveScreen()
        tab == AppTab.drag && route?.startsWith("run:") == true -> DragRunScreen(route.removePrefix("run:"))
        tab == AppTab.drag -> DragScreen()
        tab == AppTab.tracks && route == "search" -> TrackSearchScreen()
        tab == AppTab.tracks && route?.startsWith("editor:") == true -> TrackEditorScreen(route.removePrefix("editor:"))
        tab == AppTab.tracks && route?.startsWith("board:") == true -> LeaderboardScreen(route.removePrefix("board:"))
        tab == AppTab.tracks -> TracksScreen()
        tab == AppTab.sessions && route?.startsWith("session:") == true -> SessionDetailScreen(route.removePrefix("session:"))
        tab == AppTab.sessions && route == "friends" -> FriendLapsScreen()
        tab == AppTab.sessions -> SessionsScreen()
        tab == AppTab.garage && route?.startsWith("car:") == true -> CarDetailScreen(route.removePrefix("car:"))
        tab == AppTab.garage && route?.startsWith("editor:") == true -> CarEditorScreen(route.removePrefix("editor:"))
        tab == AppTab.garage && route?.startsWith("setup:") == true -> SetupDetailScreen(route.removePrefix("setup:"))
        tab == AppTab.garage && route?.startsWith("setupEdit:") == true -> route.removePrefix("setupEdit:").split(":").let { SetupEditorScreen(it[0], it.getOrElse(1) { "new" }) }
        tab == AppTab.garage -> GarageScreen()
        tab == AppTab.friends && route?.startsWith("friend:") == true -> FriendDetailScreen(route.removePrefix("friend:"))
        tab == AppTab.friends -> FriendsScreen()
        else -> DeviceScreen()
    }
}

@Composable
private fun BottomBar() {
    val m = LocalModel.current
    val view = LocalView.current
    Column(Modifier.fillMaxWidth().background(Theme.bg.copy(alpha = 0.97f))) {
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(Theme.line.copy(alpha = 0.6f)))
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp).windowInsetsPadding(WindowInsets.navigationBars)) {
            for (item in tabItems()) {
                val selected = m.tab == item.tab
                Column(
                    Modifier.weight(1f).clickable(remember { MutableInteractionSource() }, null) {
                        if (!selected) view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        m.tab = item.tab
                    }.padding(top = 8.dp, bottom = 6.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Icon(item.icon, item.title, tint = if (selected) Theme.accent else Theme.sub, modifier = Modifier.size(24.dp))
                    FitText(item.title, 10.sp, if (selected) Theme.accent else Theme.sub)
                }
            }
        }
    }
}

@Composable
private fun SideBar(compact: Boolean) {
    val m = LocalModel.current
    Row(Modifier.fillMaxHeight().background(Theme.bg)) {
        Box(Modifier.fillMaxHeight().width(0.5.dp).background(Theme.line.copy(alpha = 0.6f)))
        Column(
            Modifier.fillMaxHeight().width(84.dp).windowInsetsPadding(WindowInsets.safeDrawing).padding(4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
        ) {
            for (item in tabItems()) {
                val selected = m.tab == item.tab
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(if (selected) Theme.button else Theme.bg)
                        .clickable { m.tab = item.tab }.padding(vertical = if (compact) 6.dp else 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(item.icon, item.title, tint = if (selected) Theme.accent else Theme.sub, modifier = Modifier.size(22.dp))
                    if (!compact) FitText(item.title, 11.sp, if (selected) Theme.accent else Theme.sub)
                }
            }
            Spacer(Modifier.height(0.dp))
        }
    }
}

/** A tab's name on one line, a little smaller when it does not fit ("Dispositivo" among seven tabs). */
@Composable
private fun FitText(text: String, size: TextUnit, color: androidx.compose.ui.graphics.Color) {
    var scale by remember(text) { mutableStateOf(1f) }
    Text(
        text, fontSize = size * scale, fontWeight = FontWeight.Medium, color = color, maxLines = 1, softWrap = false,
        onTextLayout = { if (it.didOverflowWidth && scale > 0.6f) scale -= 0.08f },
    )
}
