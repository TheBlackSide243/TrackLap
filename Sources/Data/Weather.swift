import Foundation

/// The weather at a track right now, from Open-Meteo: free, no key, and only the track's
/// coordinates are sent. Live uses it to offer the setup for the conditions.
enum TrackWeather {
    struct Now: Equatable {
        var wet: Bool
        var temperature: Double?
    }

    private static var cache: (coord: Coord, at: Date, now: Now)?

    static func now(at c: Coord) async -> Now? {
        if let cache, Geo.distance(cache.coord, c) < 2000, Date().timeIntervalSince(cache.at) < 15 * 60 { return cache.now }
        var u = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        u.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", c.lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", c.lon)),
            URLQueryItem(name: "current", value: "temperature_2m,precipitation,weather_code"),
        ]
        struct Answer: Decodable {
            struct Current: Decodable {
                var temperature_2m: Double?
                var precipitation: Double?
                var weather_code: Int?
            }
            var current: Current
        }
        var req = URLRequest(url: u.url!, timeoutInterval: 10)
        req.setValue(Net.userAgent, forHTTPHeaderField: "User-Agent")
        guard let answer = try? await URLSession.shared.data(for: req),
              (answer.1 as? HTTPURLResponse)?.statusCode == 200,
              let a = try? JSONDecoder().decode(Answer.self, from: answer.0) else { return nil }
        // Drizzle, rain, freezing rain, showers and thunderstorms.
        let code = a.current.weather_code ?? 0
        let wet = (a.current.precipitation ?? 0) > 0.1 || (51...67).contains(code) || (80...82).contains(code) || (95...99).contains(code)
        let now = Now(wet: wet, temperature: a.current.temperature_2m)
        cache = (c, Date(), now)
        return now
    }
}
