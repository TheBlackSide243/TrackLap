package win.tbsgaming.tracklap.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.RecordVoiceOver
import androidx.compose.material.icons.filled.ShowChart
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import win.tbsgaming.tracklap.LocalModel
import win.tbsgaming.tracklap.LocalPermissions
import win.tbsgaming.tracklap.SourceKind

/** Four pages at the first start: the logo's circuit drawing itself, the delta, what is there, where the GPS comes from. */
@Composable
fun IntroScreen(done: () -> Unit) {
    var page by remember { mutableIntStateOf(0) }
    val last = 3
    Column(Modifier.fillMaxSize().background(Theme.bg).windowInsetsPadding(WindowInsets.safeDrawing).padding(24.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
            if (page < last) Text(L("Salta"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Theme.sub,
                modifier = Modifier.clip(CircleShape).clickableNoRipple { done() }.padding(8.dp))
        }
        AnimatedContent(page, Modifier.weight(1f).fillMaxWidth(), transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "intro") { p ->
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically),
                horizontalAlignment = Alignment.CenterHorizontally) {
                when (p) {
                    0 -> {
                        LogoCircuit(Modifier.size(220.dp))
                        Title("TrackLap")
                        Body(L("Il cronometro da pista che sta in tasca."))
                        Body(L("Giri, intermedi e delta dal GPS, per i track day."))
                    }
                    1 -> {
                        Panel(glow = Theme.good) {
                            Text(L("GIRO %lld", 4), fontSize = 13.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp, color = Theme.accent)
                            BigText("1:52.37", 56.sp)
                            Spacer(Modifier.height(8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("DELTA", fontSize = 13.sp, fontWeight = FontWeight.Black, color = Theme.sub, modifier = Modifier.weight(1f))
                                BigText("−0.42", 36.sp, Theme.good)
                            }
                            Spacer(Modifier.height(8.dp))
                            DeltaBar(-0.42, 1.0)
                        }
                        Title(L("Delta in diretta"))
                        Body(L("Il passaggio sulla linea è calcolato tra due fix GPS: a 10 Hz i tempi sono precisi a pochi centesimi."))
                        Body(L("Verde quando guadagni sul giro migliore, rosso quando perdi, viola per i settori più veloci."))
                    }
                    2 -> {
                        Title(L("Tutto quello che serve"))
                        Feature(Icons.Filled.Map, Theme.accent, L("Oltre 60 circuiti"), L("E la ricerca di qualsiasi pista nel mondo, con il tracciato già pronto."))
                        Feature(Icons.Filled.ShowChart, Theme.purple, L("Analisi dei giri"), L("Confronta due giri curva per curva: velocità, delta e g."))
                        Feature(Icons.Filled.RecordVoiceOver, Theme.good, L("Tempi a voce"), L("A fine giro tempo e distacco, senza guardare il telefono."))
                        Feature(Icons.Filled.Memory, Theme.yellow, L("Il cruscotto sull'ESP32"), L("Con lo schermo della Waveshare i tempi li vedi anche senza iPhone."))
                    }
                    else -> SourcePage()
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
            for (i in 0..last) Box(Modifier.size(if (i == page) 22.dp else 7.dp, 7.dp).clip(CircleShape).background(if (i == page) Theme.accent else Theme.line))
        }
        PrimaryButton(if (page < last) L("Avanti") else L("Inizia")) { if (page < last) page += 1 else done() }
    }
}

@Composable
private fun SourcePage() {
    val m = LocalModel.current
    val permissions = LocalPermissions.current
    Title(L("Da dove arriva il GPS?"))
    Body(L("Puoi cambiarlo quando vuoi in Dispositivo."))
    for (k in SourceKind.entries) {
        val on = m.source == k
        Panel(glow = if (on) Theme.accent else null, modifier = Modifier.clickableNoRipple {
            m.setSource(k)
            if (k == SourceKind.phone && !m.phone.hasPermission()) permissions.location()
            if (k == SourceKind.device && !m.ble.hasPermission()) permissions.bluetooth()
        }) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AppGlyph(k.icon, 40.dp, if (on) Theme.accent else Theme.sub)
                Column(Modifier.weight(1f)) {
                    Text(k.title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
                    Text(k.detail, fontSize = 12.sp, color = Theme.sub)
                }
            }
        }
    }
}

@Composable
private fun Title(text: String) = Text(text, fontSize = 28.sp, fontWeight = FontWeight.Black, color = Theme.text, textAlign = TextAlign.Center)

@Composable
private fun Body(text: String) = Text(text, fontSize = 16.sp, color = Theme.sub, textAlign = TextAlign.Center)

@Composable
private fun Feature(icon: androidx.compose.ui.graphics.vector.ImageVector, color: androidx.compose.ui.graphics.Color, title: String, text: String) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        AppGlyph(icon, 46.dp, color)
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Theme.text)
            Text(text, fontSize = 13.sp, color = Theme.sub)
        }
    }
}

/** The circuit of the icon, drawing itself. */
@Composable
private fun LogoCircuit(modifier: Modifier) {
    var go by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { go = 1 }
    val f by animateFloatAsState(go.toFloat(), tween(1600), label = "draw")
    Canvas(modifier) {
        val path = Path().apply {
            moveTo(300f, 770f)
            cubicTo(170f, 770f, 150f, 610f, 250f, 545f)
            lineTo(420f, 432f)
            cubicTo(482f, 392f, 470f, 300f, 545f, 266f)
            cubicTo(650f, 220f, 830f, 250f, 846f, 384f)
            cubicTo(862f, 505f, 760f, 525f, 700f, 565f)
            cubicTo(640f, 605f, 705f, 705f, 640f, 752f)
            cubicTo(600f, 782f, 520f, 770f, 470f, 770f)
            close()
        }
        val measure = PathMeasure().apply { setPath(path, false) }
        val part = Path()
        measure.getSegment(0f, measure.length * f, part, true)
        val s = size.minDimension / 1024f
        scale(s, s, pivot = androidx.compose.ui.geometry.Offset.Zero) {
            drawPath(path, Theme.line, style = Stroke(118f, join = StrokeJoin.Round))
            drawPath(part, Theme.accent, style = Stroke(46f, cap = StrokeCap.Round, join = StrokeJoin.Round))
            if (f >= 0.99f) {
                drawCircle(Theme.accent.copy(alpha = 0.28f), 54f, androidx.compose.ui.geometry.Offset(846f, 384f))
                drawCircle(androidx.compose.ui.graphics.Color.White, 30f, androidx.compose.ui.geometry.Offset(846f, 384f))
                drawCircle(Theme.accent, 16f, androidx.compose.ui.geometry.Offset(846f, 384f))
            }
        }
    }
}

/** A tap without the ripple: for text links and cards that light up by themselves. */
fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier = this.pointerInput(onClick) { detectTapGestures { onClick() } }
