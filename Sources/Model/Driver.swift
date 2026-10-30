import Foundation
import Observation

/// Who you are to your friends: the name and the vehicle on the laps you share, in a live group and
/// in the online leaderboards. The id stays secret: only the leaderboard sees it, to know which
/// entries are yours.
@Observable
final class DriverProfile {
    private(set) var name: String
    private(set) var vehicle: String
    /// Send the best lap of every session to the online leaderboard of its track.
    private(set) var publishLaps: Bool
    let id: UUID

    static let maxLength = 24

    init() {
        let d = UserDefaults.standard
        name = d.string(forKey: "driverName") ?? ""
        vehicle = d.string(forKey: "driverVehicle") ?? ""
        publishLaps = d.bool(forKey: "publishLaps")
        if let s = d.string(forKey: "driverID"), let id = UUID(uuidString: s) {
            self.id = id
        } else {
            id = UUID()
            d.set(id.uuidString, forKey: "driverID")
        }
    }

    var hasName: Bool { !Self.trimmed(name).isEmpty }
    /// What the others see: the name without stray spaces, or "Driver".
    var displayName: String { hasName ? Self.trimmed(name) : L("Pilota") }
    var displayVehicle: String { Self.trimmed(vehicle) }

    /// Kept as typed (a text field binds to it), spaces trimmed only where it is shown.
    func set(name: String) {
        self.name = String(name.prefix(Self.maxLength))
        UserDefaults.standard.set(self.name, forKey: "driverName")
    }

    func set(vehicle: String) {
        self.vehicle = String(vehicle.prefix(Self.maxLength))
        UserDefaults.standard.set(self.vehicle, forKey: "driverVehicle")
    }

    func setPublish(_ on: Bool) {
        publishLaps = on
        UserDefaults.standard.set(on, forKey: "publishLaps")
    }

    private static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}
