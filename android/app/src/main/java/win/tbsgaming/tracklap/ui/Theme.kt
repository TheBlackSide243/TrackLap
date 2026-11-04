package win.tbsgaming.tracklap.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import win.tbsgaming.tracklap.timing.SectorState

/** The shared dark theme of the user's apps, with TrackLap's cyan accent. */
object Theme {
    val bg = Color(0xFF0F0F11)
    val panel = Color(0xFF1C1C20)
    val line = Color(0xFF34343C)
    val input = Color(0xFF26262C)
    val text = Color(0xFFF2F2F6)
    val sub = Color(0xFF9696A2)
    val button = Color(0xFF2C2C34)
    val good = Color(0xFF4AD67C)
    val bad = Color(0xFFF06050)
    val accent = Color(0xFF22D3EE)
    val purple = Color(0xFFB066FF)
    val yellow = Color(0xFFFACC15)
    val blue = Color(0xFF60A5FA)

    fun color(state: SectorState): Color = when (state) {
        SectorState.best -> purple
        SectorState.faster -> good
        SectorState.slower -> yellow
    }

    /** Big figures: heavy, with digits of one width so they do not jump. */
    fun timeStyle(size: TextUnit, color: Color = text) = TextStyle(
        fontSize = size, fontWeight = FontWeight.Black, color = color, fontFeatureSettings = "tnum", letterSpacing = (-0.5).sp,
    )

    fun numStyle(size: TextUnit, weight: FontWeight = FontWeight.Bold, color: Color = text) =
        TextStyle(fontSize = size, fontWeight = weight, color = color, fontFeatureSettings = "tnum")
}
