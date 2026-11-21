import SwiftUI

/// The lean angle on two wheels: now, and the furthest to each side in this session.
struct LeanCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        let lean = engine.leanAngle
        let color = LeanDial.color(for: lean)
        Panel {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("Piega").uppercased())
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Theme.sub)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(Int(abs(lean).rounded()))°")
                            .font(Theme.timeFont(46))
                            .monospacedDigit()
                            .foregroundStyle(abs(lean) < 3 ? Theme.sub : color)
                            .contentTransition(.numericText(value: abs(lean)))
                        if abs(lean) >= 3 {
                            Image(systemName: lean < 0 ? "arrow.left" : "arrow.right")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundStyle(color)
                        }
                    }
                    HStack(spacing: 12) {
                        furthest("arrow.left", engine.maxLeanLeft)
                        furthest("arrow.right", engine.maxLeanRight)
                    }
                }
                Spacer(minLength: 0)
                LeanDial(lean: lean, maxLeft: engine.maxLeanLeft, maxRight: engine.maxLeanRight)
                    .frame(width: 150, height: 96)
            }
            .animation(.snappy(duration: 0.25), value: lean)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("Piega"))
        .accessibilityValue(Text(verbatim: "\(Int(abs(lean).rounded()))°"))
    }

    /// The furthest lean to one side, in the purple of the bests.
    private func furthest(_ arrow: String, _ degrees: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: arrow).font(.system(size: 10, weight: .heavy))
            Text(verbatim: degrees >= 1 ? "\(Int(degrees.rounded()))°" : "—")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(degrees >= 1 ? Theme.purple : Theme.sub)
    }
}

/// A bike seen from behind on an arc of 60° to each side: the line leans as it does, the arc fills
/// from upright, and the two marks stay at the furthest lean to each side.
struct LeanDial: View, Animatable {
    /// Degrees from upright, + leaning right.
    var lean: Double
    var maxLeft: Double = 0
    var maxRight: Double = 0

    static let range = 60.0

    var animatableData: Double {
        get { lean }
        set { lean = newValue }
    }

    /// Cyan, then yellow from 45° and red from 55°: where the tyres are near their edge.
    static func color(for lean: Double) -> Color {
        switch abs(lean) {
        case ..<45: Theme.accent
        case ..<55: Theme.yellow
        default: Theme.bad
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let pivot = CGPoint(x: size.width / 2, y: size.height - 10)
            let r = min((size.width / 2 - 8) / CGFloat(sin(Self.range * .pi / 180)), size.height - 22)
            let shown = max(-Self.range, min(Self.range, lean))
            let color = Self.color(for: lean)

            func point(_ degrees: Double, _ radius: CGFloat) -> CGPoint {
                let a = degrees * .pi / 180
                return CGPoint(x: pivot.x + radius * CGFloat(sin(a)), y: pivot.y - radius * CGFloat(cos(a)))
            }
            func arc(_ from: Double, _ to: Double) -> Path {
                var p = Path()
                p.addArc(center: pivot, radius: r, startAngle: .degrees(from - 90), endAngle: .degrees(to - 90), clockwise: false)
                return p
            }

            // The ground.
            var ground = Path()
            ground.move(to: CGPoint(x: pivot.x - r * 0.55, y: pivot.y + 5))
            ground.addLine(to: CGPoint(x: pivot.x + r * 0.55, y: pivot.y + 5))
            ctx.stroke(ground, with: .color(Theme.line), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            ctx.stroke(arc(-Self.range, Self.range), with: .color(Theme.input), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            for tick in stride(from: -Self.range, through: Self.range, by: 15) {
                var t = Path()
                t.move(to: point(tick, r - 9))
                t.addLine(to: point(tick, r - (tick == 0 ? 17 : 13)))
                ctx.stroke(t, with: .color(tick == 0 ? Theme.sub : Theme.line), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            if abs(shown) > 0.5 {
                var glow = ctx
                glow.addFilter(.shadow(color: color.opacity(0.7), radius: 6))
                glow.stroke(arc(min(0, shown), max(0, shown)), with: .color(color), style: StrokeStyle(lineWidth: 8, lineCap: .round))
            }

            for mark in [-min(maxLeft, Self.range), min(maxRight, Self.range)] where abs(mark) >= 1 {
                var m = Path()
                m.move(to: point(mark, r - 7))
                m.addLine(to: point(mark, r + 7))
                ctx.stroke(m, with: .color(Theme.purple), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            // The bike: from where the tyre touches the ground up to just inside the arc.
            var bike = Path()
            bike.move(to: pivot)
            bike.addLine(to: point(shown, r - 22))
            ctx.stroke(bike, with: .color(Theme.text), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: pivot.x - 5, y: pivot.y - 5, width: 10, height: 10)), with: .color(Theme.text))
            let head = point(shown, r - 22)
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 4, y: head.y - 4, width: 8, height: 8)), with: .color(color))
        }
    }
}
