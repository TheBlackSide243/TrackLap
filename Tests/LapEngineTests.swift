import XCTest
@testable import TrackLap

/// The timer on a made-up circuit: a circle of 100 m radius driven at a steady 20 m/s with a fix
/// every tenth of a second, the start line across it at the north and an intermediate at the south.
/// A lap is 628.3 m and takes 31.416 s; the lateral g is v²/r = 0.408 g, a lean of 22.2°.
final class LapEngineTests: XCTestCase {
    private let radius = 100.0
    private let speed = 20.0
    private let frame = LocalFrame(origin: Coord(45.0, 9.0))

    private var lapTime: Double { 2 * .pi * radius / speed }

    private var track: Track {
        Track(name: "Circle", center: frame.origin,
              start: GateLine(a: frame.coord(Vec(0, radius - 20)), b: frame.coord(Vec(0, radius + 20))),
              sectors: [GateLine(a: frame.coord(Vec(0, -radius + 20)), b: frame.coord(Vec(0, -radius - 20)))])
    }

    /// The fixes of `laps` laps and a bit, starting 10° before the line. Clockwise turns right all
    /// the way round; `board` is what an accelerometer on the vehicle would say.
    private func drive(laps: Double, clockwise: Bool = true, board: GPoint? = nil) -> [Sample] {
        let omega = speed / radius
        let from = -10.0 * .pi / 180
        let duration = (laps * 2 * .pi - from) / omega
        return (0...Int(duration * 10)).map { k in
            let t = Double(k) / 10
            // The angle from north, growing the way the car goes round.
            let a = from + omega * t
            let x = radius * sin(a) * (clockwise ? 1 : -1)
            let degrees = a * 180 / .pi
            let heading = clockwise ? degrees + 90 : 270 - degrees
            return Sample(t: 1000 + t, coord: frame.coord(Vec(x, radius * cos(a))), speed: speed,
                          heading: (heading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360), g: board)
        }
    }

    private func run(_ samples: [Sample]) -> LapEngine {
        let engine = LapEngine()
        engine.load(track: track)
        for s in samples { engine.ingest(s) }
        return engine
    }

    func testLapsAreTimedToTheHundredth() {
        let engine = run(drive(laps: 3.2))
        XCTAssertEqual(engine.laps.count, 3)
        XCTAssertEqual(engine.lapNumber, 4)
        for lap in engine.laps {
            XCTAssertEqual(lap.time, lapTime, accuracy: 0.02)
            XCTAssertEqual(lap.distance, 2 * .pi * radius, accuracy: 2)
            XCTAssertEqual(lap.maxSpeed, speed, accuracy: 0.001)
        }
        // Every lap as long as the one before: the delta stays at nothing.
        XCTAssertEqual(engine.delta ?? 9, 0, accuracy: 0.05)
    }

    func testSectorsAddUpToTheLap() {
        let engine = run(drive(laps: 2.2))
        XCTAssertEqual(engine.laps.count, 2)
        for lap in engine.laps {
            XCTAssertEqual(lap.sectors.count, 2)
            XCTAssertEqual(lap.sectors.reduce(0, +), lap.time, accuracy: 0.001)
            XCTAssertEqual(lap.sectors[0], lapTime / 2, accuracy: 0.02)
        }
    }

    func testNoLapWithoutGoingRound() {
        // Back and forth over the line within a few metres: the first crossing starts lap 1, the
        // others are too soon and too short to end it.
        let engine = LapEngine()
        engine.load(track: track)
        for k in 0..<400 {
            let x = sin(Double(k) / 10) * 5
            engine.ingest(Sample(t: Double(k) / 10, coord: frame.coord(Vec(x, radius)), speed: 5, heading: 90))
        }
        XCTAssertTrue(engine.laps.isEmpty)
    }

    func testLeanComesFromTheTurn() {
        let right = run(drive(laps: 1.5))
        XCTAssertEqual(right.leanAngle, 22.2, accuracy: 1.5)
        XCTAssertEqual(right.maxLeanRight, 22.2, accuracy: 1.5)
        XCTAssertLessThan(right.maxLeanLeft, 1)

        let left = run(drive(laps: 1.5, clockwise: false))
        XCTAssertEqual(left.leanAngle, -22.2, accuracy: 1.5)
        XCTAssertEqual(left.maxLeanLeft, 22.2, accuracy: 1.5)
        XCTAssertLessThan(left.maxLeanRight, 1)
    }

    func testLeanIgnoresAnAccelerometerThatLeansWithTheBike() {
        // On a bike in a corner the board feels next to no lateral g.
        let engine = run(drive(laps: 1.5, board: GPoint(lateral: 0.02, longitudinal: 0)))
        XCTAssertEqual(engine.lateralG, 0.02, accuracy: 0.01)
        XCTAssertEqual(engine.leanAngle, 22.2, accuracy: 1.5)

        let trace = engine.laps[0].trace
        let mid = trace.count / 2
        XCTAssertEqual(GForce.along(trace)[mid].lateral, 0.02, accuracy: 0.01)
        XCTAssertEqual(GForce.along(trace, twoWheels: true)[mid].lateral, 0.408, accuracy: 0.05)
        XCTAssertEqual(GForce.along(trace, twoWheels: true)[mid].longitudinal, 0, accuracy: 0.01)
        let lean = GForce.maxLean(trace)
        XCTAssertEqual(lean.right, 22.2, accuracy: 2)
        XCTAssertLessThan(lean.left, 2)
    }

    func testLeanOfALateralG() {
        XCTAssertEqual(LapEngine.lean(1), 45, accuracy: 0.001)
        XCTAssertEqual(LapEngine.lean(-1), -45, accuracy: 0.001)
        XCTAssertEqual(LapEngine.lean(0), 0)
    }
}
