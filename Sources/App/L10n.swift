import Foundation

/// Translated text where a String is needed rather than a SwiftUI text key. The Italian text is
/// the key; translations live in Resources/<language>.lproj/Localizable.strings (tools/l10n.mjs).
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key)
}

/// Speed and distance units: km/h and metres, or mph and miles. The default follows the region.
enum Units: String, CaseIterable, Identifiable {
    case metric, imperial

    var id: String { rawValue }

    static let key = "units"

    static var current: Units {
        if let raw = UserDefaults.standard.string(forKey: key), let u = Units(rawValue: raw) { return u }
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk ? .imperial : .metric
    }

    var title: String { self == .metric ? "km/h · km" : "mph · mi" }
}
