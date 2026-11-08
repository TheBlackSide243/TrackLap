package win.tbsgaming.tracklap.model

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Moped
import androidx.compose.material.icons.filled.TwoWheeler
import androidx.compose.ui.graphics.vector.ImageVector
import kotlinx.serialization.Serializable
import win.tbsgaming.tracklap.ui.L

/** What you drive: a car, a motorcycle or a scooter. On two wheels the timer shows the lean angle and the setup has a bike's fields. */
@Serializable
enum class VehicleKind {
    car, motorcycle, scooter;

    val onTwoWheels: Boolean get() = this != car

    val title: String
        get() = when (this) {
            car -> L("Auto")
            motorcycle -> L("Moto")
            scooter -> L("Scooter")
        }

    val icon: ImageVector
        get() = when (this) {
            car -> Icons.Filled.DirectionsCar
            motorcycle -> Icons.Filled.TwoWheeler
            scooter -> Icons.Filled.Moped
        }

    val unnamed: String
        get() = when (this) {
            car -> L("Auto senza nome")
            motorcycle -> L("Moto senza nome")
            scooter -> L("Scooter senza nome")
        }

    companion object {
        fun of(s: String?): VehicleKind? = entries.firstOrNull { it.name == s }
    }
}
