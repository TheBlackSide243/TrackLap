package win.tbsgaming.tracklap.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/** A line of a chart: x and y in data units. */
data class ChartSeries(val xs: List<Double>, val ys: List<Double>, val color: Color, val width: Float = 2.5f, val fill: Boolean = false, val dashed: Boolean = false)

/** A point marked on a chart, with an optional label. */
data class ChartMark(val x: Double, val y: Double, val color: Color, val radius: Float = 4f, val label: String? = null)

/** Round steps for an axis: 1, 2 or 5 times a power of ten. */
private fun niceStep(span: Double, ticks: Int): Double {
    if (span <= 0) return 1.0
    val raw = span / ticks
    val mag = 10.0.pow(floor(log10(raw)))
    val n = raw / mag
    return mag * when {
        n < 1.5 -> 1.0
        n < 3 -> 2.0
        n < 7 -> 5.0
        else -> 10.0
    }
}

/**
 * A simple chart drawn on a canvas: grey grid, labels on the left and below, lines (with an area
 * under them if asked), marks, a zero line, and a cursor you drag along x.
 */
@Composable
fun LineChart(
    series: List<ChartSeries>,
    modifier: Modifier = Modifier,
    marks: List<ChartMark> = emptyList(),
    xLabel: (Double) -> String = { it.toInt().toString() },
    yLabel: (Double) -> String = { it.toInt().toString() },
    yMin: Double? = null,
    yMax: Double? = null,
    zeroLine: Boolean = false,
    cursor: Double? = null,
    onCursor: ((Double?) -> Unit)? = null,
) {
    val allX = series.flatMap { it.xs }
    val allY = series.flatMap { it.ys } + marks.map { it.y }
    if (allX.isEmpty() || allY.isEmpty()) return
    val x0 = allX.min()
    val x1 = max(allX.max(), x0 + 1e-6)
    var lo = yMin ?: allY.min()
    var hi = yMax ?: allY.max()
    if (hi - lo < 1e-6) { hi += 1; lo -= 1 }
    val yStep = niceStep(hi - lo, 4)
    lo = floor(lo / yStep) * yStep
    hi = ceil(hi / yStep) * yStep
    val xStep = niceStep(x1 - x0, 5)

    val gestures = if (onCursor == null) Modifier else Modifier
        .pointerInput(x0, x1) {
            detectTapGestures { p -> onCursor(xAt(p.x, size.width.toFloat(), 40 * density, x0, x1)) }
        }
        .pointerInput(x0, x1) {
            detectDragGestures(onDragEnd = {}) { change, _ -> onCursor(xAt(change.position.x, size.width.toFloat(), 40 * density, x0, x1)) }
        }

    Canvas(modifier.then(gestures)) {
        val left = 40.dpx(this)
        val bottom = 18.dpx(this)
        val w = size.width - left
        val h = size.height - bottom
        fun px(x: Double) = left + ((x - x0) / (x1 - x0) * w).toFloat()
        fun py(y: Double) = (h - (y - lo) / (hi - lo) * h).toFloat()
        val label = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
            color = Theme.sub.toArgb()
            textSize = 10.dpx(this@Canvas)
        }
        // Grid and labels.
        var y = lo
        while (y <= hi + yStep / 2) {
            drawLine(Theme.line.copy(alpha = 0.6f), Offset(left, py(y)), Offset(size.width, py(y)), 1f)
            label.textAlign = android.graphics.Paint.Align.RIGHT
            drawContext.canvas.nativeCanvas.drawText(yLabel(y), left - 6.dpx(this), py(y) + 4.dpx(this), label)
            y += yStep
        }
        var x = ceil(x0 / xStep) * xStep
        label.textAlign = android.graphics.Paint.Align.CENTER
        while (x <= x1) {
            drawContext.canvas.nativeCanvas.drawText(xLabel(x), px(x), size.height - 4.dpx(this), label)
            x += xStep
        }
        if (zeroLine && lo < 0 && hi > 0) drawLine(Theme.text.copy(alpha = 0.5f), Offset(left, py(0.0)), Offset(size.width, py(0.0)), 1.5f)

        for (s in series) {
            if (s.xs.size < 2) continue
            val path = Path()
            for (i in s.xs.indices) {
                val p = Offset(px(s.xs[i]), py(s.ys[i]))
                if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
            }
            if (s.fill) {
                val area = Path().apply {
                    addPath(path)
                    lineTo(px(s.xs.last()), py(max(lo, 0.0)))
                    lineTo(px(s.xs.first()), py(max(lo, 0.0)))
                    close()
                }
                drawPath(area, Brush.verticalGradient(listOf(s.color.copy(alpha = 0.35f), s.color.copy(alpha = 0.02f)), 0f, h))
            }
            drawPath(
                path, s.color,
                style = Stroke(
                    s.width * density, cap = StrokeCap.Round, join = StrokeJoin.Round,
                    pathEffect = if (s.dashed) PathEffect.dashPathEffect(floatArrayOf(8f, 6f)) else null,
                ),
            )
        }
        for (mk in marks) {
            val c = Offset(px(mk.x), py(mk.y))
            drawCircle(mk.color, mk.radius * density, c)
            mk.label?.let {
                label.textAlign = android.graphics.Paint.Align.LEFT
                label.isFakeBoldText = true
                drawContext.canvas.nativeCanvas.drawText(it, c.x + 4.dpx(this), c.y - 6.dpx(this), label)
                label.isFakeBoldText = false
            }
        }
        if (cursor != null && cursor in x0..x1) {
            drawLine(Theme.text.copy(alpha = 0.8f), Offset(px(cursor), 0f), Offset(px(cursor), h), 1.5f)
        }
    }
}

private fun Int.dpx(scope: DrawScope): Float = this * scope.density

private fun xAt(px: Float, width: Float, left: Float, x0: Double, x1: Double): Double {
    val f = ((px - left) / max(width - left, 1f)).coerceIn(0f, 1f)
    return x0 + (x1 - x0) * f
}

/** Thins a long trace to about n points for drawing. */
fun <T> thin(list: List<T>, n: Int = 400): List<T> {
    if (list.size <= n) return list
    val step = list.size.toDouble() / n
    return (0 until n).map { list[min(list.size - 1, (it * step).toInt())] } + list.last()
}

/** The colour of a speed between the slowest and fastest of a lap: red, yellow, green. */
fun speedColor(v: Double, lo: Double, hi: Double): Color {
    val f = if (hi > lo) ((v - lo) / (hi - lo)).coerceIn(0.0, 1.0).toFloat() else 0.5f
    return if (f < 0.5f) lerpColor(Theme.bad, Theme.yellow, f * 2) else lerpColor(Theme.yellow, Theme.good, (f - 0.5f) * 2)
}

/** Green where you gain, red where you lose, against a reference. */
fun gainColor(rate: Double): Color {
    val f = (abs(rate) * 8).coerceIn(0.0, 1.0).toFloat()
    return lerpColor(Theme.sub, if (rate < 0) Theme.good else Theme.bad, f)
}

private fun lerpColor(a: Color, b: Color, f: Float) = Color(
    a.red + (b.red - a.red) * f, a.green + (b.green - a.green) * f, a.blue + (b.blue - a.blue) * f, 1f,
)
