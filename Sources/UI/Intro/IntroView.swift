import SwiftUI

/// The welcome on the first launch, and again from Device → Information: the circuit of the icon
/// drawing itself, a lap with its live delta, what the app does, and the choice of GPS source.
struct IntroView: View {
    @Environment(AppModel.self) private var model
    let onDone: () -> Void
    @State private var page: Int

    private let last = 3

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        // The screenshot mode can open a given page.
        let start = Showcase.screen == .intro ? UserDefaults.standard.integer(forKey: "introPage") : 0
        _page = State(initialValue: min(max(start, 0), 3))
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.22), .clear],
                           center: UnitPoint(x: page.isMultiple(of: 2) ? 0.85 : 0.15, y: 0.05),
                           startRadius: 0, endRadius: 460)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.6), value: page)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Salta", action: onDone)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.sub)
                        .opacity(page < last ? 1 : 0)
                }
                .padding(.horizontal, 24)
                .frame(height: 44)

                TabView(selection: $page) {
                    WelcomePage(active: page == 0).tag(0)
                    LivePage(active: page == 1).tag(1)
                    FeaturesPage(active: page == 2).tag(2)
                    SourcePage(active: page == 3).tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0...last, id: \.self) { i in
                        Capsule()
                            .fill(i == page ? Theme.accent : Theme.line)
                            .frame(width: i == page ? 22 : 8, height: 8)
                    }
                }
                .animation(.spring(duration: 0.35), value: page)
                .padding(.bottom, 18)

                Button {
                    if page < last {
                        withAnimation(.easeInOut) { page += 1 }
                    } else {
                        onDone()
                    }
                } label: {
                    Text(page < last ? L("Avanti") : L("Inizia"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: page)
    }
}

// MARK: - Pages

/// A picture and a title with its text, sliding in when the page comes up. The title goes first
/// where the picture is a list to read after it.
private struct IntroPage<Picture: View>: View {
    let active: Bool
    let title: String
    let text: [String]
    var titleFirst = false
    @ViewBuilder var picture: Picture

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            if titleFirst {
                words
                picture
            } else {
                picture
                words
            }
            Spacer(minLength: 0)
        }
    }

    private var words: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
            ForEach(text, id: \.self) { t in
                Text(t)
                    .font(.body)
                    .foregroundStyle(Theme.sub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 28)
        .opacity(active ? 1 : 0)
        .offset(y: active ? 0 : 16)
        .animation(.easeOut(duration: 0.5).delay(active ? 0.15 : 0), value: active)
    }
}

private struct WelcomePage: View {
    let active: Bool

    var body: some View {
        IntroPage(active: active, title: "TrackLap", text: [
            L("Il cronometro da pista che sta in tasca."),
            L("Giri, intermedi e delta dal GPS, per i track day."),
        ]) {
            IntroCircuit(active: active)
                .frame(maxWidth: 300)
                .padding(.horizontal, 30)
        }
    }
}

private struct LivePage: View {
    let active: Bool

    var body: some View {
        IntroPage(active: active, title: L("Delta in diretta"), text: [
            L("Il passaggio sulla linea è calcolato tra due fix GPS: a 10 Hz i tempi sono precisi a pochi centesimi."),
            L("Verde quando guadagni sul giro migliore, rosso quando perdi, viola per i settori più veloci."),
        ]) {
            IntroLiveDemo()
                .padding(.horizontal, 24)
                .scaleEffect(active ? 1 : 0.94)
                .animation(.spring(duration: 0.5), value: active)
        }
    }
}

private struct FeaturesPage: View {
    let active: Bool

    private let rows: [(icon: String, color: Color, title: String, text: String)] = [
        ("map.fill", Theme.accent, L("Oltre 60 circuiti"), L("E la ricerca di qualsiasi pista nel mondo, con il tracciato già pronto.")),
        ("chart.xyaxis.line", Theme.purple, L("Analisi dei giri"), L("Confronta due giri curva per curva: velocità, delta e g.")),
        ("speaker.wave.2.fill", Theme.good, L("Tempi a voce"), L("A fine giro tempo e distacco, senza guardare il telefono.")),
        ("cpu", Theme.yellow, L("Il cruscotto sull'ESP32"), L("Con lo schermo della Waveshare i tempi li vedi anche senza iPhone.")),
    ]

    var body: some View {
        IntroPage(active: active, title: L("Tutto quello che serve"), text: [], titleFirst: true) {
            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 14) {
                        AppGlyph(symbol: r.icon, size: 46, color: r.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.headline).foregroundStyle(Theme.text)
                            Text(r.text).font(.subheadline).foregroundStyle(Theme.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .opacity(active ? 1 : 0)
                    .offset(x: active ? 0 : 30)
                    .animation(.spring(duration: 0.5).delay(active ? 0.1 + Double(i) * 0.08 : 0), value: active)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct SourcePage: View {
    @Environment(AppModel.self) private var model
    let active: Bool

    var body: some View {
        IntroPage(active: active, title: L("Da dove arriva il GPS?"), text: [L("Puoi cambiarlo quando vuoi in Dispositivo.")],
                  titleFirst: true) {
            VStack(spacing: 10) {
                ForEach(SourceKind.allCases) { k in
                    SourceCard(kind: k, selected: k == model.source) { model.setSource(k) }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Pictures

/// The circuit of the app icon, drawn in when the page appears, with a car lapping it.
private struct IntroCircuit: View {
    let active: Bool
    @State private var drawn: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let path = IconCircuit().path(in: rect)
            let w = geo.size.width / 790
            ZStack {
                path.stroke(Color(rgb: 42, 42, 49), style: StrokeStyle(lineWidth: 118 * w, lineJoin: .round))
                IconCircuit()
                    .trim(from: 0, to: drawn)
                    .stroke(LinearGradient(colors: [Color(rgb: 103, 232, 249), Color(rgb: 14, 165, 198)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 46 * w, lineCap: .round, lineJoin: .round))
                    .shadow(color: Theme.accent.opacity(0.55), radius: 14)
                Chequered()
                    .frame(width: 40 * w, height: 140 * w)
                    .position(x: (390 - 110) * w, y: (770 - 190) * w)
                TimelineView(.animation) { ctx in
                    let f = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) / 5
                    let p = path.trimmedPath(from: 0, to: max(0.002, f)).currentPoint ?? .zero
                    ZStack {
                        Circle().fill(Theme.accent.opacity(0.3)).frame(width: 52 * w, height: 52 * w)
                        Circle().fill(.white).frame(width: 28 * w, height: 28 * w)
                    }
                    .position(p)
                    .opacity(drawn >= 1 ? 1 : 0)
                }
            }
        }
        .aspectRatio(790 / 660, contentMode: .fit)
        .onChange(of: active, initial: true) { _, on in
            guard on, drawn == 0 else { return }
            withAnimation(.easeInOut(duration: 1.8)) { drawn = 1 }
        }
    }
}

/// The track of icon.svg, in its 1024 grid cropped to x 110–900 and y 190–850 (the track with its kerb).
private struct IconCircuit: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 790
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + (x - 110) * s, y: rect.minY + (y - 190) * s) }
        var path = Path()
        path.move(to: p(470, 770))
        path.addLine(to: p(300, 770))
        path.addCurve(to: p(250, 545), control1: p(170, 770), control2: p(150, 610))
        path.addLine(to: p(420, 432))
        path.addCurve(to: p(545, 266), control1: p(482, 392), control2: p(470, 300))
        path.addCurve(to: p(846, 384), control1: p(650, 220), control2: p(830, 250))
        path.addCurve(to: p(700, 565), control1: p(862, 505), control2: p(760, 525))
        path.addCurve(to: p(640, 752), control1: p(640, 605), control2: p(705, 705))
        path.addCurve(to: p(470, 770), control1: p(600, 782), control2: p(520, 770))
        path.closeSubpath()
        return path
    }
}

/// The finish line: a strip of black and white squares.
private struct Chequered: View {
    var body: some View {
        Canvas { ctx, size in
            let cols = 2, rows = 7
            let cw = size.width / CGFloat(cols), ch = size.height / CGFloat(rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    let rect = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw, height: ch)
                    ctx.fill(Path(rect), with: .color((r + c).isMultiple(of: 2) ? Theme.text : Theme.bg))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

/// A lap running with its delta changing colour, like on the Live screen.
private struct IntroLiveDemo: View {
    private let deltas: [(value: Double, color: Color)] = [(-0.21, Theme.purple), (-0.08, Theme.good), (0.35, Theme.bad)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let lap = 52 + t.truncatingRemainder(dividingBy: 30)
            let d = deltas[Int(t / 2.4) % deltas.count]
            VStack(spacing: 12) {
                Panel(glow: Theme.accent) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("GIRO \(4)"))
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.accent)
                        Text(Fmt.lap(lap))
                            .font(Theme.timeFont(56))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }
                }
                Panel(glow: d.color) {
                    HStack {
                        Text("DELTA")
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.sub)
                        Spacer()
                        Text(Fmt.delta(d.value))
                            .font(Theme.timeFont(38))
                            .monospacedDigit()
                            .foregroundStyle(d.color)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: d.value)
                    }
                }
            }
        }
    }
}
