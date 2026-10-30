import SwiftUI

/// The shared dark theme of the user's apps, with TrackLap's cyan accent.
enum Theme {
    static let bg = Color(rgb: 15, 15, 17)
    static let panel = Color(rgb: 28, 28, 32)
    static let line = Color(rgb: 52, 52, 60)
    static let input = Color(rgb: 38, 38, 44)
    static let text = Color(rgb: 242, 242, 246)
    static let sub = Color(rgb: 150, 150, 162)
    static let button = Color(rgb: 44, 44, 52)
    static let good = Color(rgb: 74, 214, 124)
    static let bad = Color(rgb: 240, 96, 80)
    static let accent = Color(rgb: 34, 211, 238)
    static let purple = Color(rgb: 176, 102, 255)
    static let yellow = Color(rgb: 250, 204, 21)

    static func color(for state: SectorState) -> Color {
        switch state {
        case .best: purple
        case .faster: good
        case .slower: yellow
        }
    }

    static func timeFont(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
}

extension Color {
    init(rgb r: Double, _ g: Double, _ b: Double) {
        self.init(red: r / 255, green: g / 255, blue: b / 255)
    }
}

enum Fmt {
    static func lap(_ t: Double?) -> String {
        guard let t, t.isFinite, t >= 0 else { return "–:––.––" }
        let cs = Int((t * 100).rounded())
        return String(format: "%d:%02d.%02d", cs / 6000, (cs / 100) % 60, cs % 100)
    }

    /// Axis labels: tenths are enough.
    static func lapShort(_ t: Double) -> String {
        let ds = Int((t * 10).rounded())
        return String(format: "%d:%02d.%d", ds / 600, (ds / 10) % 60, ds % 10)
    }

    static func sector(_ t: Double) -> String {
        t < 60 ? String(format: "%.2f", t) : lap(t)
    }

    static func delta(_ d: Double?) -> String {
        guard let d, d.isFinite else { return "—" }
        return (d < 0 ? "−" : "+") + String(format: "%.2f", abs(d))
    }

    /// Metres per second to the unit of the settings.
    static var speedFactor: Double { Units.current == .metric ? 3.6 : 2.236936 }
    static var speedUnit: String { Units.current == .metric ? "km/h" : "mph" }

    static func speed(_ v: Double) -> String { "\(Int((v * speedFactor).rounded()))" }

    static func hz(_ r: Double) -> String {
        r >= 2 ? "\(Int(r.rounded())) Hz" : String(format: "%.1f Hz", r)
    }

    static func distance(_ m: Double?) -> String {
        guard let m else { return "—" }
        if Units.current == .imperial {
            return m >= 161 ? String(format: "%.2f mi", m / 1609.344) : "\(Int(m * 3.28084)) ft"
        }
        return m >= 1000 ? String(format: "%.2f km", m / 1000) : "\(Int(m)) m"
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM yyyy HH:mm")
        return f
    }()
}
