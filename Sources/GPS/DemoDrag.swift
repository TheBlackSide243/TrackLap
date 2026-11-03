import Foundation
import Observation

/// A simulated drag run at 10 Hz on a straight road: a few seconds standing, full throttle with
/// gear changes for a kilometre, then a hard stop. A hot hatch: 0–100 in under 5 s, the quarter
/// mile in under 13 s.
@Observable
final class DemoDrag {
    private(set) var isRunning = false
    @ObservationIgnored var onSample: ((Sample) -> Void)? = nil

    @ObservationIgnored private var timer: Timer? = nil
    @ObservationIgnored private var car = Car(origin: Coord(0, 0))
    @ObservationIgnored private var t: Double = 0

    /// Up the road from `origin`: in real time, one fix every tenth of a second.
    func start(at origin: Coord, power: Double = 1) {
        stop()
        car = Car(origin: origin, power: power)
        t = Date().timeIntervalSince1970
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    /// A whole run worked out at once with GPS times from `t0`: the screenshot mode fills its runs with it.
    static func simulate(at origin: Coord, power: Double, from t0: Double) -> [Sample] {
        var car = Car(origin: origin, power: power)
        var out: [Sample] = []
        var t = t0
        while !car.done {
            t += 0.1
            out.append(car.advance(dt: 0.1, at: t, wall: Date(timeIntervalSince1970: t)))
        }
        return out
    }

    /// A clock of its own, a tenth of a second a fix like a GPS: when the main thread is busy the run
    /// slows down instead of getting a gap, which the timer would take for a lost signal.
    private func tick() {
        t += 0.1
        onSample?(car.advance(dt: 0.1, at: t, wall: Date()))
        if car.done { stop() }
    }

    private struct Car {
        let frame: LocalFrame
        let heading = 32.0
        let power: Double
        var s = 0.0
        var v = 0.0
        var clock = 0.0
        var shiftUntil = 0.0
        var gear = 1
        var braking = false
        var stoppedAt: Double? = nil

        /// km/h where it changes up.
        static let shifts = [58.0, 98, 140, 182, 220]

        init(origin: Coord, power: Double = 1) {
            frame = LocalFrame(origin: origin)
            self.power = power
        }

        /// Standing for 3 s, the run, then 3 s stopped.
        var done: Bool { stoppedAt.map { clock - $0 > 3 } ?? false }

        mutating func advance(dt: Double, at time: Double, wall: Date) -> Sample {
            clock += dt
            if clock > 3 && stoppedAt == nil {
                let a: Double
                if braking {
                    a = -10.2
                } else if clock < shiftUntil {
                    a = 0.4
                } else {
                    // Grip first, then power, less the air.
                    a = min(6.4, 165 * power / max(v, 1)) - 0.0005 * v * v - 0.12
                }
                v = max(0, v + a * dt)
                if !braking, gear <= Self.shifts.count, v * 3.6 >= Self.shifts[gear - 1] {
                    gear += 1
                    shiftUntil = clock + 0.2
                }
                if !braking && s >= 1020 { braking = true }
                if braking && v == 0 { stoppedAt = clock }
                s += v * dt
            }
            let dir = Vec(sin(heading * .pi / 180), cos(heading * .pi / 180))
            let jitter = Vec(Double.random(in: -0.25...0.25), Double.random(in: -0.25...0.25))
            let noise = v > 0 ? Double.random(in: -0.06...0.06) : 0
            // A gentle climb of 0.4%.
            let alt = 120 + s * 0.004 + Double.random(in: -0.15...0.15)
            return Sample(t: time, coord: frame.coord(dir * s + jitter), speed: max(0, v + noise), heading: heading,
                          wall: wall, utc: time, alt: alt)
        }
    }
}
