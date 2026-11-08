import Foundation

/// The conditions a setup is for.
enum SetupWeather: String, Codable, CaseIterable, Identifiable {
    case dry, mixed, wet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dry: L("Asciutto")
        case .mixed: L("Misto")
        case .wet: L("Bagnato")
        }
    }

    var symbol: String {
        switch self {
        case .dry: "sun.max.fill"
        case .mixed: "cloud.sun.fill"
        case .wet: "cloud.rain.fill"
        }
    }
}

/// The numbers of a setup, every one optional: what is set on the car, nothing more. Pressures are
/// kept in bar, lengths in millimetres, springs in N/mm.
struct SetupValues: Codable, Hashable {
    var tyres = ""
    var pressureFrontCold: Double? = nil
    var pressureRearCold: Double? = nil
    var pressureFrontHot: Double? = nil
    var pressureRearHot: Double? = nil
    var camberFront: Double? = nil
    var camberRear: Double? = nil
    var toeFront: Double? = nil
    var toeRear: Double? = nil
    var heightFront: Double? = nil
    var heightRear: Double? = nil
    var bumpFront: Double? = nil
    var bumpRear: Double? = nil
    var reboundFront: Double? = nil
    var reboundRear: Double? = nil
    var springFront: Double? = nil
    var springRear: Double? = nil
    var barFront = ""
    var barRear = ""
    var wing = ""
    var brakeBias: Double? = nil
    /// Two wheels (0.10.0): spring preload and sag in millimetres, and the gearing as written
    /// ("15/43"). Optional, so setups saved before still read.
    var preloadFront: Double? = nil
    var preloadRear: Double? = nil
    var sagFront: Double? = nil
    var sagRear: Double? = nil
    var gearing: String? = nil
    /// Anything else, as a name and a value.
    var extra: [SetupItem] = []
    var notes = ""

    var isEmpty: Bool { self == SetupValues() }

    var gearingText: String {
        get { gearing ?? "" }
        set { gearing = newValue.isEmpty ? nil : newValue }
    }
}

struct SetupItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var label: String
    var value: String
}

/// The values a setup had until it was changed: kept, never overwritten.
struct SetupRevision: Codable, Hashable, Identifiable {
    var id = UUID()
    /// When these values were replaced by the next ones.
    var date: Date
    var version: Int
    var values: SetupValues
}

/// A setup of one car for some conditions, "Mugello in the wet": each its own, side by side with
/// the others. Changing one keeps the values it had as a revision, so the setup that worked in the
/// rain last spring is still there to try and improve.
struct CarSetup: Codable, Hashable, Identifiable {
    var id = UUID()
    var carID: UUID
    var name = ""
    var weather: SetupWeather = .dry
    /// The track it was made for, when there is one.
    var track = ""
    var created = Date()
    var updated = Date()
    var values = SetupValues()
    /// The earlier versions, newest first.
    var history: [SetupRevision] = []

    var version: Int { history.count + 1 }

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? weather.title : n
    }

    var snapshot: SessionSetup {
        SessionSetup(id: id, name: displayName, weather: weather, version: version, values: values)
    }
}

/// The setup a session was driven with, as it was that day.
struct SessionSetup: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var weather: SetupWeather
    var version: Int
    var values: SetupValues
}

/// One value of a setup: what it is called, its unit and where it is kept. The list decides the
/// order of the editor and of the setup page.
struct SetupField: Identifiable {
    enum Group: String, CaseIterable, Identifiable {
        case tyres, geometry, dampers, drivetrain, aero

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tyres: L("Gomme")
            case .geometry: L("Geometria")
            case .dampers: L("Ammortizzatori e molle")
            case .drivetrain: L("Trasmissione")
            case .aero: L("Aero e freni")
            }
        }

        var symbol: String {
            switch self {
            case .tyres: "circle.circle"
            case .geometry: "angle"
            case .dampers: "arrow.up.and.down.circle"
            case .drivetrain: "gearshape.2"
            case .aero: "wind"
            }
        }
    }

    /// Which vehicles have it: camber and wings are for cars, preload and sag for bikes.
    enum Wheels { case any, four, two }

    let id: String
    let group: Group
    let title: String
    var number: WritableKeyPath<SetupValues, Double?>? = nil
    var text: WritableKeyPath<SetupValues, String>? = nil
    /// A pressure, shown in bar or psi.
    var pressure = false
    var unit = ""
    var decimals = 0
    var wheels: Wheels = .any

    func fits(_ kind: VehicleKind) -> Bool {
        switch wheels {
        case .any: true
        case .four: !kind.onTwoWheels
        case .two: kind.onTwoWheels
        }
    }

    /// The fields of the editor for a vehicle.
    static func fields(for kind: VehicleKind) -> [SetupField] { all.filter { $0.fits(kind) } }

    static let all: [SetupField] = [
        .init(id: "tyres", group: .tyres, title: L("Gomme"), text: \.tyres),
        .init(id: "pfc", group: .tyres, title: L("Pressione ant. a freddo"), number: \.pressureFrontCold, pressure: true),
        .init(id: "prc", group: .tyres, title: L("Pressione post. a freddo"), number: \.pressureRearCold, pressure: true),
        .init(id: "pfh", group: .tyres, title: L("Pressione ant. a caldo"), number: \.pressureFrontHot, pressure: true),
        .init(id: "prh", group: .tyres, title: L("Pressione post. a caldo"), number: \.pressureRearHot, pressure: true),
        .init(id: "cf", group: .geometry, title: L("Campanatura ant."), number: \.camberFront, unit: "°", decimals: 1, wheels: .four),
        .init(id: "cr", group: .geometry, title: L("Campanatura post."), number: \.camberRear, unit: "°", decimals: 1, wheels: .four),
        .init(id: "tf", group: .geometry, title: L("Convergenza ant."), number: \.toeFront, unit: "mm", decimals: 1, wheels: .four),
        .init(id: "tr", group: .geometry, title: L("Convergenza post."), number: \.toeRear, unit: "mm", decimals: 1, wheels: .four),
        .init(id: "hf", group: .geometry, title: L("Altezza ant."), number: \.heightFront, unit: "mm"),
        .init(id: "hr", group: .geometry, title: L("Altezza post."), number: \.heightRear, unit: "mm"),
        .init(id: "bf", group: .dampers, title: L("Compressione ant."), number: \.bumpFront, unit: L("click")),
        .init(id: "br", group: .dampers, title: L("Compressione post."), number: \.bumpRear, unit: L("click")),
        .init(id: "rf", group: .dampers, title: L("Estensione ant."), number: \.reboundFront, unit: L("click")),
        .init(id: "rr", group: .dampers, title: L("Estensione post."), number: \.reboundRear, unit: L("click")),
        .init(id: "sf", group: .dampers, title: L("Molle ant."), number: \.springFront, unit: "N/mm"),
        .init(id: "sr", group: .dampers, title: L("Molle post."), number: \.springRear, unit: "N/mm"),
        .init(id: "plf", group: .dampers, title: L("Precarico ant."), number: \.preloadFront, unit: "mm", decimals: 1, wheels: .two),
        .init(id: "plr", group: .dampers, title: L("Precarico post."), number: \.preloadRear, unit: "mm", decimals: 1, wheels: .two),
        .init(id: "sagf", group: .dampers, title: L("Sag ant."), number: \.sagFront, unit: "mm", wheels: .two),
        .init(id: "sagr", group: .dampers, title: L("Sag post."), number: \.sagRear, unit: "mm", wheels: .two),
        .init(id: "arbf", group: .dampers, title: L("Barra ant."), text: \.barFront, wheels: .four),
        .init(id: "arbr", group: .dampers, title: L("Barra post."), text: \.barRear, wheels: .four),
        .init(id: "gear", group: .drivetrain, title: L("Rapporto (pignone/corona)"), text: \.gearingText, wheels: .two),
        .init(id: "wing", group: .aero, title: L("Ala"), text: \.wing, wheels: .four),
        .init(id: "bias", group: .aero, title: L("Ripartizione di frenata (ant.)"), number: \.brakeBias, unit: "%", decimals: 1, wheels: .four),
    ]

    var shownUnit: String { pressure ? (Units.current == .metric ? "bar" : "psi") : unit }
    var shownDecimals: Int { pressure ? (Units.current == .metric ? 2 : 1) : decimals }

    /// The value as it reads, with its unit; nil when it is not set.
    func display(_ v: SetupValues) -> String? {
        if let text {
            let s = v[keyPath: text].trimmingCharacters(in: .whitespaces)
            return s.isEmpty ? nil : s
        }
        guard let number, let x = v[keyPath: number] else { return nil }
        return Self.format(shown(x), decimals: shownDecimals) + (shownUnit.isEmpty ? "" : " " + shownUnit)
    }

    /// Kept value to the unit shown, and back.
    func shown(_ x: Double) -> Double { pressure && Units.current != .metric ? x * 14.5038 : x }
    func kept(_ x: Double) -> Double { pressure && Units.current != .metric ? x / 14.5038 : x }

    static func format(_ x: Double, decimals: Int) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = decimals
        f.minimumIntegerDigits = 1
        return f.string(from: NSNumber(value: x)) ?? String(x)
    }
}

extension SetupValues {
    /// What changed from older values, as "Front cold pressure 2.0 bar → 1.8 bar".
    func changes(from old: SetupValues) -> [String] {
        var out: [String] = []
        for f in SetupField.all {
            let a = f.display(old), b = f.display(self)
            if a != b { out.append("\(f.title): \(a ?? "—") → \(b ?? "—")") }
        }
        let oldExtra = Dictionary(old.extra.map { ($0.label, $0.value) }, uniquingKeysWith: { a, _ in a })
        let newExtra = Dictionary(extra.map { ($0.label, $0.value) }, uniquingKeysWith: { a, _ in a })
        for label in Set(oldExtra.keys).union(newExtra.keys).sorted() where oldExtra[label] != newExtra[label] {
            out.append("\(label): \(oldExtra[label] ?? "—") → \(newExtra[label] ?? "—")")
        }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines) != old.notes.trimmingCharacters(in: .whitespacesAndNewlines) {
            out.append(L("Note cambiate"))
        }
        return out
    }
}
