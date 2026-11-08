import Foundation

/// What you drive: a car, a motorcycle or a scooter. On two wheels the timer shows the lean angle
/// and the setup has the fields of a bike.
enum VehicleKind: String, Codable, CaseIterable, Identifiable {
    case car, motorcycle, scooter

    var id: String { rawValue }
    var onTwoWheels: Bool { self != .car }

    var title: String {
        switch self {
        case .car: L("Auto")
        case .motorcycle: L("Moto")
        case .scooter: L("Scooter")
        }
    }

    var symbol: String {
        switch self {
        case .car: "car.fill"
        case .motorcycle: "motorcycle"
        case .scooter: "scooter"
        }
    }

    var unnamed: String {
        switch self {
        case .car: L("Auto senza nome")
        case .motorcycle: L("Moto senza nome")
        case .scooter: L("Scooter senza nome")
        }
    }

    /// What you drive when no vehicle of the garage is chosen (and always in TrackLap Lite).
    static var preferred: VehicleKind {
        VehicleKind(rawValue: UserDefaults.standard.string(forKey: "vehicleKind") ?? "") ?? .car
    }
}

/// A car in your garage: what it is, its numbers and what was done to it, with one photo. The same
/// shape the server keeps (server/src/index.js, cleanGarage), so the garage goes up as it is.
struct Car: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var year: Int? = nil
    /// Metric horsepower (CV) whatever the units shown, like the server.
    var power: Int? = nil
    /// Kilograms.
    var weight: Int? = nil
    var mods: [String] = []
    var notes = ""
    /// Car, motorcycle or scooter (0.10.0); nil in garages from before, which were all cars.
    var kind: VehicleKind? = nil
    /// Its photo: a JPEG in the garage folder, under the same id on the server. A new photo always
    /// gets a new id, so a photo never changes at its address and caches can keep it for good.
    var photo: String? = nil
    var added = Date()

    static let maxName = 40
    static let maxMod = 80
    static let maxMods = 40
    static let maxNotes = 600
    static let maxCars = 20

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? vehicle.unnamed : n
    }

    var vehicle: VehicleKind { kind ?? .car }

    var info: CarInfo {
        CarInfo(id: id.uuidString, name: displayName, year: year, power: power, weight: weight,
                mods: mods, notes: notes, photo: photo.map { .local($0) } ?? .empty, kind: vehicle)
    }

    /// What goes to the server: the same fields, the modifications without empty lines.
    var published: Car {
        var c = self
        c.name = String(displayName.prefix(Self.maxName))
        c.mods = mods.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        c.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        c.kind = vehicle
        return c
    }
}

/// A car as the screens show it, yours or from someone's public garage.
struct CarInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var year: Int?
    var power: Int?
    var weight: Int?
    var mods: [String]
    var notes: String
    var photo: CarPhoto
    var kind: VehicleKind = .car

    /// Kilograms (or pounds) for each horsepower: the number drivers compare cars by.
    var ratio: Double? {
        guard let power, let weight, power > 0 else { return nil }
        return Double(weight) / Double(power)
    }

    /// "2019 · 320 CV", for a card.
    var subtitle: String {
        [year.map(String.init), power.map { Fmt.power($0) + " " + Fmt.powerUnit }].compactMap { $0 }.joined(separator: " · ")
    }
}

enum CarPhoto: Hashable {
    case empty
    /// A photo id in your garage folder.
    case local(String)
    case remote(URL)
}

/// Someone's garage as the server sends it.
struct PublicGarage: Decodable {
    struct Entry: Decodable {
        var id: String
        var name: String
        var year: Int?
        var power: Int?
        var weight: Int?
        var mods: [String]
        var notes: String?
        var photo: String?
        var kind: String?
    }

    var code: String
    var name: String
    var cars: [Entry]
    var mine: Bool?
    var hidden: Bool?
    /// "all", or "friends" for a garage shown to friends only.
    var audience: String?
    /// Your own garage only: the photos the server is still waiting for.
    var missing: [String]?

    func info(_ e: Entry) -> CarInfo {
        CarInfo(id: e.id, name: e.name, year: e.year, power: e.power, weight: e.weight, mods: e.mods,
                notes: e.notes ?? "", photo: e.photo.map { .remote(Server.photoURL(code: code, photo: $0)) } ?? .empty,
                kind: VehicleKind(rawValue: e.kind ?? "") ?? .car)
    }

    var infos: [CarInfo] { cars.map(info) }
}

extension Fmt {
    /// Horsepower in the unit of the settings: CV in metric, hp otherwise.
    static func power(_ cv: Int) -> String {
        Units.current == .metric ? "\(cv)" : "\(Int((Double(cv) * 0.98632).rounded()))"
    }

    static var powerUnit: String { Units.current == .metric ? L("CV") : "hp" }

    static func weight(_ kg: Int) -> String {
        Units.current == .metric ? "\(kg)" : "\(Int((Double(kg) * 2.20462).rounded()))"
    }

    static var weightUnit: String { Units.current == .metric ? "kg" : "lb" }

    /// kg/CV, or lb/hp.
    static func ratio(_ kgPerCV: Double) -> String {
        let r = Units.current == .metric ? kgPerCV : kgPerCV * 2.20462 / 0.98632
        return String(format: "%.2f", r)
    }

    static var ratioUnit: String { Units.current == .metric ? L("kg/CV") : "lb/hp" }

    /// What was typed in the editor, in the unit shown, back to CV and kg.
    static func cv(fromShown v: Int) -> Int { Units.current == .metric ? v : Int((Double(v) / 0.98632).rounded()) }
    static func kg(fromShown v: Int) -> Int { Units.current == .metric ? v : Int((Double(v) / 2.20462).rounded()) }
}
