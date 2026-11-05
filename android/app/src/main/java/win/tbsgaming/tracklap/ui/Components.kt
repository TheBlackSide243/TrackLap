package win.tbsgaming.tracklap.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.LocalFrame
import win.tbsgaming.tracklap.model.Track
import kotlin.math.max
import kotlin.math.min

@Composable
fun AppGlyph(icon: ImageVector, size: Dp = 40.dp, color: Color = Theme.accent) {
    val shape = RoundedCornerShape(size * 0.28f)
    Box(
        Modifier.size(size).clip(shape).background(Theme.panel).border(1.dp, Theme.line, shape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = color, modifier = Modifier.size(size * 0.5f))
    }
}

/** Icon, title in capitals in the accent colour, grey subtitle: the header of every screen. */
@Composable
fun ScreenHeader(icon: ImageVector, title: String, subtitle: String, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        AppGlyph(icon)
        Column(Modifier.weight(1f)) {
            Text(title.uppercase(), fontSize = 22.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp, color = Theme.accent, maxLines = 1)
            Text(subtitle, fontSize = 14.sp, color = Theme.sub, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        trailing()
    }
}

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.2.sp, color = Theme.sub,
        modifier = modifier.fillMaxWidth().padding(start = 4.dp, top = 4.dp),
    )
}

@Composable
fun Panel(modifier: Modifier = Modifier, padding: Dp = 16.dp, glow: Color? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(22.dp)
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Theme.panel)
            .then(
                if (glow != null) Modifier.drawBehind {
                    drawRect(Brush.radialGradient(listOf(glow.copy(alpha = 0.22f), Color.Transparent), center = Offset(size.width, 0f), radius = 280.dp.toPx()))
                } else Modifier,
            )
            .border(1.dp, (glow ?: Theme.line).copy(alpha = if (glow == null) 0.8f else 0.35f), shape)
            .padding(padding),
        content = content,
    )
}

@Composable
fun StatTile(title: String, value: String, modifier: Modifier = Modifier, unit: String? = null, color: Color = Theme.text) {
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier.clip(shape).background(Theme.panel).border(1.dp, Theme.line.copy(alpha = 0.8f), shape).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(title.uppercase(), fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, color = Theme.sub, maxLines = 1)
        Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(value, style = Theme.numStyle(22.sp, color = color), maxLines = 1)
            if (unit != null) Text(unit, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Theme.sub, modifier = Modifier.padding(bottom = 3.dp))
        }
    }
}

@Composable
fun StatusPill(icon: ImageVector, text: String, color: Color = Theme.accent) {
    Row(
        Modifier.clip(CircleShape).background(Theme.panel).border(1.dp, Theme.line, CircleShape).padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(7.dp).shadow(4.dp, CircleShape, ambientColor = color, spotColor = color).clip(CircleShape).background(color))
        Icon(icon, null, tint = Theme.sub, modifier = Modifier.size(12.dp))
        Text(text, style = Theme.numStyle(12.sp, FontWeight.SemiBold), maxLines = 1)
    }
}

@Composable
fun Badge(text: String, color: Color = Theme.accent) {
    Text(
        text.uppercase(), fontSize = 10.sp, fontWeight = FontWeight.Black, letterSpacing = 0.6.sp, color = color, maxLines = 1,
        modifier = Modifier.clip(CircleShape).background(color.copy(alpha = 0.14f)).padding(horizontal = 7.dp, vertical = 3.dp),
    )
}

@Composable
fun PrimaryButton(text: String, icon: ImageVector? = null, color: Color = Theme.accent, enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .scale(if (pressed) 0.98f else 1f)
            .alpha(if (enabled) 1f else 0.4f)
            .shadow(if (enabled) 10.dp else 0.dp, shape, ambientColor = color, spotColor = color)
            .clip(shape)
            .background(color.copy(alpha = if (pressed) 0.75f else 1f))
            .clickable(source, null, enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = Color.Black, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, fontSize = 16.sp, fontWeight = FontWeight.Black, color = Color.Black, maxLines = 1)
    }
}

@Composable
fun SecondaryButton(text: String, icon: ImageVector? = null, color: Color = Theme.accent, enabled: Boolean = true, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .scale(if (pressed) 0.98f else 1f)
            .alpha(if (enabled) 1f else 0.4f)
            .clip(shape)
            .background(Theme.button.copy(alpha = if (pressed) 0.7f else 1f))
            .border(BorderStroke(1.dp, if (pressed) color else Theme.line), shape)
            .clickable(source, null, enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = color, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = color, maxLines = 1)
    }
}

/** A small round button with an icon, for headers and toolbars. */
@Composable
fun RoundIconButton(icon: ImageVector, tint: Color = Theme.accent, onClick: () -> Unit) {
    Box(
        Modifier.size(40.dp).clip(CircleShape).background(Theme.panel).border(1.dp, Theme.line, CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun ProgressOverlay(text: String) {
    Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.45f)).clickable(enabled = true, onClick = {}), contentAlignment = Alignment.Center) {
        Column(
            Modifier.clip(RoundedCornerShape(22.dp)).background(Theme.panel).padding(28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CircularProgressIndicator(color = Theme.accent)
            Text(text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Theme.text)
        }
    }
}

@Composable
fun Note(icon: ImageVector, color: Color, text: String) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier.fillMaxWidth().clip(shape).background(color.copy(alpha = 0.08f)).border(1.dp, color.copy(alpha = 0.3f), shape).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(icon, null, tint = color, modifier = Modifier.size(18.dp))
        Text(text, fontSize = 12.sp, color = Theme.sub, modifier = Modifier.weight(1f))
    }
}

@Composable
fun BigText(text: String, size: TextUnit, color: Color = Theme.text, modifier: Modifier = Modifier) {
    Text(text, style = Theme.timeStyle(size, color), maxLines = 1, modifier = modifier)
}

/** Fits a track in a rectangle, north up. */
class Projector private constructor(
    private val frame: LocalFrame, private val scale: Double, private val minX: Double, private val maxY: Double,
    private val ox: Double, private val oy: Double,
) {
    fun point(c: Coord): Offset {
        val p = frame.xy(c)
        return Offset((ox + (p.x - minX) * scale).toFloat(), (oy + (maxY - p.y) * scale).toFloat())
    }

    companion object {
        fun make(points: List<Coord>, size: Size, inset: Float): Projector? {
            val first = points.firstOrNull() ?: return null
            if (size.width <= 2 * inset || size.height <= 2 * inset) return null
            val f = LocalFrame(first)
            val xy = points.map { f.xy(it) }
            val minX = xy.minOf { it.x }
            val maxX = xy.maxOf { it.x }
            val minY = xy.minOf { it.y }
            val maxY = xy.maxOf { it.y }
            val w = max(maxX - minX, 1.0)
            val h = max(maxY - minY, 1.0)
            val s = min((size.width - 2 * inset) / w, (size.height - 2 * inset) / h)
            return Projector(f, s, minX, maxY, (size.width - w * s) / 2, (size.height - h * s) / 2)
        }
    }
}

/** The track outline drawn as a glowing line, with the start line, the intermediates and the car. */
@Composable
fun TrackShape(track: Track, modifier: Modifier = Modifier, position: Coord? = null, lineWidth: Float = 3f) {
    Canvas(modifier) {
        val lw = lineWidth * density
        val proj = Projector.make(track.allPoints, size, lw * 2 + 6 * density) ?: return@Canvas
        val path = Path()
        for (way in track.outline) {
            if (way.size < 2) continue
            val p0 = proj.point(way[0])
            path.moveTo(p0.x, p0.y)
            for (c in way.drop(1)) proj.point(c).let { path.lineTo(it.x, it.y) }
        }
        drawPath(path, Theme.line, style = Stroke(lw + 5 * density, cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawPath(
            path, Brush.linearGradient(listOf(Theme.accent, Theme.accent.copy(alpha = 0.5f)), Offset.Zero, Offset(size.width, size.height)),
            style = Stroke(lw, cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
        for (g in track.sectors) drawLine(Theme.yellow, proj.point(g.a), proj.point(g.b), max(2f * density, lw * 0.8f), StrokeCap.Round)
        track.start?.let { drawLine(Color.White, proj.point(it.a), proj.point(it.b), lw + 2 * density, StrokeCap.Round) }
        if (position != null) {
            val c = proj.point(position)
            val r = lw + 4 * density
            drawCircle(Theme.accent.copy(alpha = 0.25f), r * 2, c)
            drawCircle(Color.White, r, c)
            drawCircle(Theme.accent, r * 0.55f, c)
        }
    }
}
