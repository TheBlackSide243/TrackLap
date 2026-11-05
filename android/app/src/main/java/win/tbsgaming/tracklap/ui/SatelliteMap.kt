package win.tbsgaming.tracklap.ui

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Point
import android.view.MotionEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import org.osmdroid.config.Configuration
import org.osmdroid.tileprovider.tilesource.OnlineTileSourceBase
import org.osmdroid.util.BoundingBox
import org.osmdroid.util.GeoPoint
import org.osmdroid.util.MapTileIndex
import org.osmdroid.views.MapView
import org.osmdroid.views.overlay.Overlay
import win.tbsgaming.tracklap.BuildConfig
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.GateLine
import win.tbsgaming.tracklap.model.LocalFrame
import java.io.File
import kotlin.math.max

/** Esri World Imagery: satellite tiles without a key, credited on every map. */
private object EsriImagery : OnlineTileSourceBase(
    "EsriWorldImagery", 0, 19, 256, ".jpg",
    arrayOf("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/"),
    "Esri, Maxar, Earthstar Geographics",
) {
    override fun getTileURLString(index: Long): String =
        baseUrl + MapTileIndex.getZoom(index) + "/" + MapTileIndex.getY(index) + "/" + MapTileIndex.getX(index)
}

object MapSetup {
    private var done = false
    fun init(context: Context) {
        if (done) return
        done = true
        val c = Configuration.getInstance()
        c.userAgentValue = "TrackLap/${BuildConfig.VERSION_NAME} (Android)"
        c.osmdroidBasePath = File(context.cacheDir, "osmdroid")
        c.osmdroidTileCache = File(context.cacheDir, "osmdroid/tiles")
    }
}

/** A line on the map: a polyline in one colour, or one colour per point. */
data class MapLine(val points: List<Coord>, val color: Color, val width: Float, val colors: List<Color>? = null, val halo: Boolean = false)

/** A dot on the map: the car, a corner, a friend. */
data class MapDot(val at: Coord, val color: Color, val radius: Float = 7f, val ring: Boolean = true, val label: String? = null)

/** Draws the lines and the dots straight on the map canvas, cheap enough to change ten times a second. */
private class DrawOverlay : Overlay() {
    var lines: List<MapLine> = emptyList()
    var dots: List<MapDot> = emptyList()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; isFakeBoldText = true }
    private val p = Point()
    private val q = Point()

    override fun draw(canvas: Canvas, map: MapView, shadow: Boolean) {
        if (shadow) return
        val proj = map.projection
        val density = map.context.resources.displayMetrics.density
        for (l in lines) {
            if (l.points.size < 2) continue
            paint.style = Paint.Style.STROKE
            if (l.halo) {
                paint.strokeWidth = (l.width + 4) * density
                paint.color = android.graphics.Color.argb(140, 0, 0, 0)
                drawPolyline(canvas, proj, l.points)
            }
            paint.strokeWidth = l.width * density
            val colors = l.colors
            if (colors == null) {
                paint.color = l.color.toArgb()
                drawPolyline(canvas, proj, l.points)
            } else {
                for (i in 1 until l.points.size) {
                    proj.toPixels(GeoPoint(l.points[i - 1].lat, l.points[i - 1].lon), p)
                    proj.toPixels(GeoPoint(l.points[i].lat, l.points[i].lon), q)
                    paint.color = colors.getOrElse(i) { l.color }.toArgb()
                    canvas.drawLine(p.x.toFloat(), p.y.toFloat(), q.x.toFloat(), q.y.toFloat(), paint)
                }
            }
        }
        for (d in dots) {
            proj.toPixels(GeoPoint(d.at.lat, d.at.lon), p)
            val r = d.radius * density
            paint.style = Paint.Style.FILL
            if (d.ring) {
                paint.color = d.color.copy(alpha = 0.35f).toArgb()
                canvas.drawCircle(p.x.toFloat(), p.y.toFloat(), r * 1.9f, paint)
                paint.color = android.graphics.Color.WHITE
                canvas.drawCircle(p.x.toFloat(), p.y.toFloat(), r, paint)
                paint.color = d.color.toArgb()
                canvas.drawCircle(p.x.toFloat(), p.y.toFloat(), r * 0.7f, paint)
            } else {
                paint.color = d.color.toArgb()
                canvas.drawCircle(p.x.toFloat(), p.y.toFloat(), r, paint)
            }
            d.label?.let {
                text.textSize = 10 * density
                text.color = android.graphics.Color.WHITE
                text.setShadowLayer(3f, 0f, 0f, android.graphics.Color.BLACK)
                canvas.drawText(it, p.x.toFloat(), p.y - r - 4 * density, text)
            }
        }
    }

    private fun drawPolyline(canvas: Canvas, proj: org.osmdroid.views.Projection, pts: List<Coord>) {
        val path = android.graphics.Path()
        for ((i, c) in pts.withIndex()) {
            proj.toPixels(GeoPoint(c.lat, c.lon), p)
            if (i == 0) path.moveTo(p.x.toFloat(), p.y.toFloat()) else path.lineTo(p.x.toFloat(), p.y.toFloat())
        }
        canvas.drawPath(path, paint)
    }
}

/** Taps on the map (not drags or pinches), in coordinates. */
private class TapOverlay : Overlay() {
    var onTap: ((Coord) -> Unit)? = null
    override fun onSingleTapConfirmed(e: MotionEvent, map: MapView): Boolean {
        val tap = onTap ?: return false
        val g = map.projection.fromPixels(e.x.toInt(), e.y.toInt())
        tap(Coord(g.latitude, g.longitude))
        return true
    }
}

private class MapHolder(val map: MapView, val draw: DrawOverlay, val tap: TapOverlay) {
    var framedKey: Any? = null
}

/** The lines of a track: the outline, the sector lines in yellow, the start line in white. */
fun trackLines(outline: List<List<Coord>>, start: GateLine?, sectors: List<GateLine>, outlineColor: Color = Theme.accent): List<MapLine> {
    val out = outline.map { MapLine(it, outlineColor, 3f, halo = true) }.toMutableList()
    for (g in sectors) out.add(MapLine(listOf(g.a, g.b), Theme.yellow, 4f, halo = true))
    start?.let { out.add(MapLine(listOf(it.a, it.b), Color.White, 5f, halo = true)) }
    return out
}

/**
 * The circuit on satellite imagery. `frame` is what it fits the view to, once per `frameKey`;
 * `interactive` lets it pan and zoom; `onTap` gets the taps.
 */
@Composable
fun SatelliteMap(
    modifier: Modifier = Modifier,
    frame: List<Coord>,
    frameKey: Any?,
    lines: List<MapLine> = emptyList(),
    dots: List<MapDot> = emptyList(),
    interactive: Boolean = false,
    minMeters: Double = 300.0,
    onTap: ((Coord) -> Unit)? = null,
) {
    val context = LocalContext.current
    val holder = remember {
        MapSetup.init(context)
        val map = MapView(context).apply {
            setTileSource(EsriImagery)
            setMultiTouchControls(true)
            zoomController.setVisibility(org.osmdroid.views.CustomZoomButtonsController.Visibility.NEVER)
            isTilesScaledToDpi = true
            minZoomLevel = 3.0
            maxZoomLevel = 20.0
            setBackgroundColor(Theme.panel.toArgb())
        }
        val draw = DrawOverlay()
        val tap = TapOverlay()
        map.overlays.add(draw)
        map.overlays.add(tap)
        MapHolder(map, draw, tap)
    }
    DisposableEffect(Unit) {
        holder.map.onResume()
        onDispose {
            holder.map.onPause()
            holder.map.onDetach()
        }
    }
    Box(modifier.background(Theme.panel)) {
        AndroidView(
            factory = { holder.map },
            modifier = Modifier.fillMaxSize(),
            update = { map ->
                holder.draw.lines = lines
                holder.draw.dots = dots
                holder.tap.onTap = onTap
                // A map that only shows the track takes no gestures: the page scrolls over it.
                if (interactive) map.setOnTouchListener(null) else map.setOnTouchListener { _, _ -> true }
                if (holder.framedKey != frameKey && frame.isNotEmpty()) {
                    holder.framedKey = frameKey
                    val box = box(frame, minMeters)
                    if (map.width > 0) map.zoomToBoundingBox(box, false, 24)
                    else map.addOnFirstLayoutListener { _, _, _, _, _ -> map.zoomToBoundingBox(box, false, 24) }
                }
                map.invalidate()
            },
        )
        Text(
            "© Esri · Maxar · OpenStreetMap", fontSize = 8.sp, color = Color.White.copy(alpha = 0.75f),
            modifier = Modifier.align(Alignment.BottomEnd).padding(4.dp).background(Color.Black.copy(alpha = 0.35f)).padding(horizontal = 4.dp, vertical = 1.dp),
        )
    }
}

private fun box(points: List<Coord>, minMeters: Double): BoundingBox {
    val minLat = points.minOf { it.lat }
    val maxLat = points.maxOf { it.lat }
    val minLon = points.minOf { it.lon }
    val maxLon = points.maxOf { it.lon }
    val center = Coord((minLat + maxLat) / 2, (minLon + maxLon) / 2)
    val f = LocalFrame(center)
    val h = max((maxLat - minLat) * f.mPerDegLat * 1.15, minMeters) / f.mPerDegLat / 2
    val w = max((maxLon - minLon) * f.mPerDegLon * 1.15, minMeters) / f.mPerDegLon / 2
    return BoundingBox(center.lat + h, center.lon + w, center.lat - h, center.lon - w)
}
