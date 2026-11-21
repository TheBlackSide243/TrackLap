package win.tbsgaming.tracklap.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import win.tbsgaming.tracklap.LocalModel
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** A lean angle with the side it is on: "← 38°", "38° →". */
fun leanText(degrees: Double): String {
    val n = abs(degrees).roundToInt()
    if (n == 0) return "0°"
    return if (degrees < 0) "← $n°" else "$n° →"
}

/** Cyan, then yellow from 45° and red from 55°: where the tyres are near their edge. */
fun leanColor(lean: Double): Color = when {
    abs(lean) < 45 -> Theme.accent
    abs(lean) < 55 -> Theme.yellow
    else -> Theme.bad
}

/** The lean angle on two wheels: now, and the furthest to each side in this session. */
@Composable
fun LeanCard() {
    val e = LocalModel.current.engine
    val lean = e.leanAngle
    val color = leanColor(lean)
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(L("Piega").uppercase(), fontSize = 13.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp, color = Theme.sub)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${abs(lean).roundToInt()}°", style = Theme.timeStyle(46.sp, if (abs(lean) < 3) Theme.sub else color))
                    if (abs(lean) >= 3) {
                        Icon(if (lean < 0) Icons.AutoMirrored.Filled.ArrowBack else Icons.AutoMirrored.Filled.ArrowForward, null, tint = color, modifier = Modifier.size(22.dp))
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Furthest(left = true, e.maxLeanLeft)
                    Furthest(left = false, e.maxLeanRight)
                }
            }
            LeanDial(lean, e.maxLeanLeft, e.maxLeanRight, Modifier.width(150.dp).height(96.dp))
        }
    }
}

/** The furthest lean to one side, in the purple of the bests. */
@Composable
private fun Furthest(left: Boolean, degrees: Double) {
    val color = if (degrees >= 1) Theme.purple else Theme.sub
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        Icon(if (left) Icons.AutoMirrored.Filled.ArrowBack else Icons.AutoMirrored.Filled.ArrowForward, null, tint = color, modifier = Modifier.size(12.dp))
        Text(if (degrees >= 1) "${degrees.roundToInt()}°" else "—", style = Theme.numStyle(14.sp, FontWeight.Bold, color))
    }
}

/**
 * A bike seen from behind on an arc of 60° to each side: the line leans as it does, the arc fills
 * from upright, and the two marks stay at the furthest lean to each side.
 */
@Composable
fun LeanDial(lean: Double, maxLeft: Double, maxRight: Double, modifier: Modifier = Modifier) {
    val range = 60f
    val shown by animateFloatAsState(lean.toFloat().coerceIn(-range, range), spring(dampingRatio = 0.9f, stiffness = 300f), label = "lean")
    val color = leanColor(lean)
    Canvas(modifier) {
        val pivot = Offset(size.width / 2, size.height - 10.dp.toPx())
        val r = min((size.width / 2 - 8.dp.toPx()) / sin(Math.toRadians(range.toDouble())).toFloat(), size.height - 22.dp.toPx())
        fun point(degrees: Float, radius: Float): Offset {
            val a = Math.toRadians(degrees.toDouble())
            return Offset(pivot.x + radius * sin(a).toFloat(), pivot.y - radius * cos(a).toFloat())
        }
        val box = Size(r * 2, r * 2)
        val corner = Offset(pivot.x - r, pivot.y - r)
        val thick = 8.dp.toPx()

        // The ground.
        drawLine(Theme.line, Offset(pivot.x - r * 0.55f, pivot.y + 5.dp.toPx()), Offset(pivot.x + r * 0.55f, pivot.y + 5.dp.toPx()), 2.dp.toPx(), StrokeCap.Round)

        drawArc(Theme.input, -90f - range, range * 2, false, corner, box, style = Stroke(thick, cap = StrokeCap.Round))
        var tick = -range
        while (tick <= range) {
            drawLine(
                if (tick == 0f) Theme.sub else Theme.line, point(tick, r - 9.dp.toPx()), point(tick, r - (if (tick == 0f) 17 else 13).dp.toPx()),
                1.5.dp.toPx(), StrokeCap.Round,
            )
            tick += 15f
        }

        if (abs(shown) > 0.5f) {
            drawArc(color.copy(alpha = 0.25f), -90f + min(0f, shown), abs(shown), false, corner, box, style = Stroke(thick * 1.9f, cap = StrokeCap.Round))
            drawArc(color, -90f + min(0f, shown), abs(shown), false, corner, box, style = Stroke(thick, cap = StrokeCap.Round))
        }

        for (mark in listOf(-min(maxLeft, range.toDouble()), min(maxRight, range.toDouble()))) {
            if (abs(mark) < 1) continue
            drawLine(Theme.purple, point(mark.toFloat(), r - 7.dp.toPx()), point(mark.toFloat(), r + 7.dp.toPx()), 3.dp.toPx(), StrokeCap.Round)
        }

        // The bike: from where the tyre touches the ground up to just inside the arc.
        val head = point(shown, max(0f, r - 22.dp.toPx()))
        drawLine(Theme.text, pivot, head, 4.dp.toPx(), StrokeCap.Round)
        drawCircle(Theme.text, 5.dp.toPx(), pivot)
        drawCircle(color, 4.dp.toPx(), head)
    }
}
