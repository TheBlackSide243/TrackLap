import SwiftUI

struct AppGlyph: View {
    let symbol: String
    var size: CGFloat = 40
    var color: Color = Theme.accent

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        shape
            .fill(Theme.panel)
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(color))
            .frame(width: size, height: size)
    }
}

/// Icon, title in capitals in the accent colour, grey subtitle: the header of every screen.
struct ScreenHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            AppGlyph(symbol: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Theme.accent)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(Theme.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 4)
    }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    var glow: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Theme.panel
                    if let glow {
                        RadialGradient(colors: [glow.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 280)
                    }
                }
                .clipShape(shape)
            }
            .overlay(shape.strokeBorder((glow ?? Theme.line).opacity(glow == nil ? 0.8 : 0.35), lineWidth: 1))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var unit: String? = nil
    var color: Color = Theme.text

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Theme.sub)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit).font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(Theme.line.opacity(0.8), lineWidth: 1))
    }
}

struct StatusPill: View {
    let icon: String
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: 4)
            Image(systemName: icon).font(.caption2.weight(.bold)).foregroundStyle(Theme.sub)
            Text(text).font(.caption.weight(.semibold)).monospacedDigit()
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }
}

struct Badge: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, color: color)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: color.opacity(isEnabled ? 0.35 : 0), radius: 14, y: 4)
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration, color: color)
    }

    private struct Styled: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            configuration.label
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.button.opacity(configuration.isPressed ? 0.7 : 1), in: shape)
                .overlay(shape.strokeBorder(configuration.isPressed ? color : Theme.line, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

struct ProgressOverlay: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}

/// Fits a track in a rectangle, north up.
struct Projector {
    private let frame: LocalFrame
    private let scale: Double
    private let minX: Double
    private let maxY: Double
    private let ox: Double
    private let oy: Double

    init?(points: [Coord], size: CGSize, inset: CGFloat) {
        guard let first = points.first, size.width > 2 * inset, size.height > 2 * inset else { return nil }
        let f = LocalFrame(origin: first)
        let xy = points.map { f.xy($0) }
        let xs = xy.map(\.x)
        let ys = xy.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        let w = max(maxX - minX, 1)
        let h = max(maxY - minY, 1)
        let s = min((Double(size.width) - 2 * Double(inset)) / w, (Double(size.height) - 2 * Double(inset)) / h)
        frame = f
        scale = s
        self.minX = minX
        self.maxY = maxY
        ox = (Double(size.width) - w * s) / 2
        oy = (Double(size.height) - h * s) / 2
    }

    func point(_ c: Coord) -> CGPoint {
        let p = frame.xy(c)
        return CGPoint(x: ox + (p.x - minX) * scale, y: oy + (maxY - p.y) * scale)
    }
}

/// The track outline drawn as a glowing line, with the start line, the intermediates and the car.
struct TrackShape: View {
    let track: Track
    var position: Coord? = nil
    var lineWidth: CGFloat = 3

    var body: some View {
        Canvas { ctx, size in
            guard let proj = Projector(points: track.allPoints, size: size, inset: lineWidth * 2 + 6) else { return }
            var path = Path()
            for way in track.outline where way.count > 1 {
                path.move(to: proj.point(way[0]))
                for c in way.dropFirst() { path.addLine(to: proj.point(c)) }
            }
            let round = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            ctx.stroke(path, with: .color(Theme.line), style: StrokeStyle(lineWidth: lineWidth + 5, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .linearGradient(Gradient(colors: [Theme.accent, Theme.accent.opacity(0.5)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
                       style: round)
            for g in track.sectors {
                var p = Path()
                p.move(to: proj.point(g.a))
                p.addLine(to: proj.point(g.b))
                ctx.stroke(p, with: .color(Theme.yellow), style: StrokeStyle(lineWidth: max(2, lineWidth * 0.8), lineCap: .round))
            }
            if let s = track.start {
                var p = Path()
                p.move(to: proj.point(s.a))
                p.addLine(to: proj.point(s.b))
                ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: lineWidth + 2, lineCap: .round))
            }
            if let position {
                let c = proj.point(position)
                let r = lineWidth + 4
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2, y: c.y - r * 2, width: r * 4, height: r * 4)), with: .color(Theme.accent.opacity(0.25)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.55, width: r * 1.1, height: r * 1.1)), with: .color(Theme.accent))
            }
        }
    }
}
