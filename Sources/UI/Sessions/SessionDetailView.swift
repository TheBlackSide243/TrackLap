import SwiftUI
import Charts
import MapKit

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let sessionID: UUID

    @State private var session: Session?
    @State private var selectedLapID: UUID?
    @State private var referenceID: UUID?
    @State private var others: [SessionLap] = []
    @State private var othersLoaded = false
    @State private var analysis: Analysis?
    @State private var cursor: Double?
    @State private var mapMode: MapMode = .speed
    @State private var gpxURL: URL?
    @State private var csvURL: URL?

    var body: some View {
        ScrollView {
            if let session, let analysis, !session.laps.isEmpty {
                content(session, analysis)
            } else {
                ProgressView().padding(60)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(session?.trackName ?? L("Sessione"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if gpxURL != nil || csvURL != nil {
                    Menu {
                        if let gpxURL {
                            ShareLink(item: gpxURL) { Label("Esporta GPX", systemImage: "map") }
                        }
                        if let csvURL {
                            ShareLink(item: csvURL) { Label("Esporta CSV", systemImage: "tablecells") }
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: model.engine.laps.count) { _, _ in
            if sessionID == model.currentSessionID { load() }
        }
        .onChange(of: selectedLapID) { _, _ in
            cursor = nil
            analyze()
        }
        .onChange(of: referenceID) { _, _ in analyze() }
    }

    private func load() {
        guard let s = model.sessions.load(sessionID) else { return }
        session = s
        if selectedLapID == nil || !s.laps.contains(where: { $0.id == selectedLapID }) {
            selectedLapID = s.best?.id
        }
        if !othersLoaded {
            others = model.sessions.bestLaps(on: s.trackID, excluding: s.id)
            othersLoaded = true
        }
        analyze()
        gpxURL = try? GPX.write(s)
        csvURL = try? CSV.write(s)
    }

    /// The heavy part, worked out once per choice of laps instead of on every move of the cursor.
    private func analyze() {
        guard let s = session, let lap = s.laps.first(where: { $0.id == selectedLapID }) ?? s.best else { return }
        analysis = Analysis(lap: lap, ref: reference(for: lap, in: s))
    }

    /// What was picked, else the best of this session, else the fastest lap of another session.
    private func reference(for lap: Lap, in s: Session) -> Lap? {
        let all = s.laps + others.map(\.lap)
        if let id = referenceID, id != lap.id, let r = all.first(where: { $0.id == id }) { return r }
        if let best = s.best, best.id != lap.id { return best }
        return others.first?.lap
    }

    private var isTrackRecord: Bool {
        guard let best = session?.best?.time, !others.isEmpty else { return false }
        return others.allSatisfy { best <= $0.lap.time }
    }

    private func content(_ s: Session, _ a: Analysis) -> some View {
        let best = s.best
        let selected = a.lap
        let bestSectors = s.bestSectors
        return VStack(spacing: 14) {
            header(s)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                StatTile(title: L("Best"), value: Fmt.lap(best?.time), color: Theme.purple)
                StatTile(title: L("Ideale"), value: Fmt.lap(s.idealTime))
                StatTile(title: L("Media"), value: Fmt.lap(s.averageTime))
                StatTile(title: L("Giri"), value: "\(s.laps.count)")
                StatTile(title: L("V max"), value: Fmt.speed(s.laps.map(\.maxSpeed).max() ?? 0), unit: Fmt.speedUnit)
                StatTile(title: L("Lunghezza"), value: Fmt.distance(best?.distance))
            }

            SectionLabel(L("Tempi sul giro"))
            Panel {
                LapTimesChart(laps: s.laps, bestID: best?.id, selectedID: selected.id)
            }

            SectionLabel(L("Analisi"))
            compareBar(s, a)

            Panel(padding: 6) {
                VStack(spacing: 8) {
                    if a.cmp != nil {
                        Picker("Mappa", selection: $mapMode) {
                            ForEach(MapMode.allCases) { Text(verbatim: $0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding([.horizontal, .top], 6)
                    }
                    AnalysisMap(analysis: a, mode: a.cmp == nil ? .speed : mapMode, cursor: cursor)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Slider(value: Binding(get: { cursor ?? 0 }, set: { cursor = $0 }), in: 0...max(1, selected.distance))
                        .tint(Theme.accent)
                        .padding(.horizontal, 8)
                    Text(a.cmp != nil && mapMode == .delta
                         ? L("Verde dove guadagni sul riferimento, rosso dove perdi. Tratteggiato: la linea del riferimento.")
                         : L("I numeri sono la velocità minima in ogni curva."))
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .bottom], 8)
                }
            }

            CursorReadout(analysis: a, cursor: cursor)

            Panel {
                SpeedChart(analysis: a, cursor: $cursor)
            }

            if let cmp = a.cmp {
                Panel {
                    DeltaChart(analysis: a, cmp: cmp, cursor: $cursor)
                }
                if !selected.sectors.isEmpty && selected.sectors.count == cmp.ref.sectors.count {
                    SectionLabel(L("Settori"))
                    Panel {
                        SectorCompare(lap: selected, ref: cmp.ref)
                    }
                }
            }

            SectionLabel(L("Accelerazioni"))
            Panel {
                GGDiagram(g: a.g, ref: a.refG)
            }

            SectionLabel(L("Giri"))
            VStack(spacing: 8) {
                ForEach(s.laps) { lap in
                    LapRow(lap: lap, bestTime: best?.time ?? lap.time, bestSectors: bestSectors,
                           isBest: lap.id == best?.id, selected: lap.id == selected.id,
                           isReference: lap.id == a.cmp?.ref.id)
                        .onTapGesture {
                            withAnimation(.snappy) { selectedLapID = lap.id }
                        }
                        .contextMenu {
                            Button { referenceID = lap.id } label: {
                                Label("Usa come riferimento", systemImage: "scope")
                            }
                        }
                }
            }
        }
        .padding(16)
    }

    private func header(_ s: Session) -> some View {
        HStack(spacing: 12) {
            AppGlyph(symbol: "flag.checkered")
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.day.string(from: s.date)).font(.headline).foregroundStyle(Theme.text)
                Text(s.source).font(.caption).foregroundStyle(Theme.sub)
            }
            Spacer()
            if isTrackRecord { Badge(text: L("Record pista"), color: Theme.yellow) }
        }
    }

    /// This lap against the reference, which can be any other lap here or the best of another session.
    private func compareBar(_ s: Session, _ a: Analysis) -> some View {
        HStack(spacing: 8) {
            Pill(color: Theme.accent) {
                Text(lapTitle(a.lap))
            }
            Text(verbatim: "vs").font(.caption.weight(.heavy)).foregroundStyle(Theme.sub)
            if let ref = a.cmp?.ref {
                Menu {
                    Section(L("Questa sessione")) {
                        ForEach(s.laps.filter { $0.id != a.lap.id }) { lap in
                            Button(lapTitle(lap)) { referenceID = lap.id }
                        }
                    }
                    if !others.isEmpty {
                        Section(L("Altre sessioni su questa pista")) {
                            ForEach(others) { o in
                                Button(otherTitle(o)) { referenceID = o.lap.id }
                            }
                        }
                    }
                } label: {
                    Pill(color: Theme.purple) {
                        HStack(spacing: 6) {
                            Text(title(of: ref))
                            Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                        }
                    }
                }
            } else {
                Text("Nessun altro giro da confrontare").font(.caption).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
        }
    }

    private func lapTitle(_ lap: Lap) -> String {
        L("Giro \(lap.number)") + " · " + Fmt.lap(lap.time)
    }

    private func otherTitle(_ o: SessionLap) -> String {
        Fmt.dayShort.string(from: o.session.date) + " · " + Fmt.lap(o.lap.time)
    }

    private func title(of ref: Lap) -> String {
        if let o = others.first(where: { $0.lap.id == ref.id }) { return otherTitle(o) }
        return lapTitle(ref)
    }
}

/// Everything the analysis draws for one lap and its reference.
private struct Analysis {
    let lap: Lap
    let cmp: LapComparison?
    let g: [GPoint]
    let refG: [GPoint]
    let apexes: [TracePoint]
    let speedSegments: [ColorSegment]
    let deltaSegments: [ColorSegment]

    init(lap: Lap, ref: Lap?) {
        self.lap = lap
        let cmp = ref.map { LapComparison(lap: lap, ref: $0) }
        self.cmp = cmp
        g = GForce.along(lap.trace)
        refG = ref.map { GForce.along($0.trace) } ?? []
        apexes = Corners.apexes(lap.trace)
        speedSegments = ColorSegment.speed(lap.trace)
        deltaSegments = cmp.map(ColorSegment.delta) ?? []
    }

    func gForce(at d: Double) -> GPoint {
        g.isEmpty ? GPoint() : g[lap.trace.index(atDistance: d)]
    }
}

private enum MapMode: String, CaseIterable, Identifiable {
    case speed, delta

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed: L("Velocità")
        case .delta: L("Guadagno")
        }
    }
}

private struct Pill<Content: View>: View {
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            content
        }
        .font(.subheadline.weight(.bold))
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.6), lineWidth: 1))
    }
}

private struct LapTimesChart: View {
    let laps: [Lap]
    let bestID: UUID?
    let selectedID: UUID

    var body: some View {
        let times = laps.map(\.time)
        let lo = max(0, (times.min() ?? 0) - 1)
        let hi = (times.max() ?? 1) + 0.5
        Chart(laps) { lap in
            BarMark(x: .value("Giro", "\(lap.number)"),
                    yStart: .value("Base", lo),
                    yEnd: .value("Tempo", lap.time),
                    width: .ratio(0.7))
                .foregroundStyle(color(lap))
                .cornerRadius(5)
        }
        .chartYScale(domain: lo...hi)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(Fmt.lapShort(v)).foregroundStyle(Theme.sub)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().foregroundStyle(Theme.sub)
            }
        }
        .frame(height: 190)
    }

    private func color(_ lap: Lap) -> Color {
        if lap.id == bestID { return Theme.purple }
        return lap.id == selectedID ? Theme.accent : Theme.accent.opacity(0.35)
    }
}

/// The values at the cursor, for this lap and the reference.
private struct CursorReadout: View {
    let analysis: Analysis
    let cursor: Double?

    var body: some View {
        Panel(padding: 12) {
            if let cursor, let p = analysis.lap.trace.point(atDistance: cursor) {
                let g = analysis.gForce(at: cursor)
                HStack(spacing: 0) {
                    cell(L("Distanza"), Fmt.distance(cursor), Theme.text)
                    cell(L("Tempo"), Fmt.lap(p.t), Theme.text)
                    cell(Fmt.speedUnit, Fmt.speed(p.v), Theme.accent)
                    if let cmp = analysis.cmp, let q = cmp.refPoint(at: cursor) {
                        let d = cmp.delta(at: cursor)
                        cell(L("Rif."), Fmt.speed(q.v), Theme.purple)
                        cell("Delta", Fmt.delta(d), d <= 0 ? Theme.good : Theme.bad)
                    }
                    cell("G", String(format: "%.1f", g.total), Theme.yellow)
                }
            } else {
                Label("Trascina sui grafici o sulla barra per muoverti nel giro", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
            }
        }
    }

    private func cell(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Theme.sub)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SpeedChart: View {
    let analysis: Analysis
    @Binding var cursor: Double?

    var body: some View {
        let lap = analysis.lap
        let mine = thin(lap.trace)
        // The reference is stretched onto this lap's distance, as in the delta.
        let ref: [TracePoint] = analysis.cmp.map { c in
            thin(c.ref.trace).map { p -> TracePoint in
                var q = p
                q.d = p.d / c.scale
                return q
            }
        } ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("Velocità").font(.caption.weight(.heavy)).foregroundStyle(Theme.text)
                legend(L("Giro \(lap.number)"), Theme.accent)
                if !ref.isEmpty { legend(L("Riferimento"), Theme.purple) }
            }
            Chart {
                ForEach(Array(ref.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("Distanza", item.element.d),
                             y: .value(Fmt.speedUnit, item.element.v * Fmt.speedFactor),
                             series: .value("Giro", "Riferimento"))
                        .foregroundStyle(Theme.purple.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(Array(mine.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("Distanza", item.element.d),
                             y: .value(Fmt.speedUnit, item.element.v * Fmt.speedFactor),
                             series: .value("Giro", "Selezionato"))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
                if let cursor {
                    RuleMark(x: .value("Cursore", cursor))
                        .foregroundStyle(Theme.text.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: 0...max(1, lap.distance))
            .chartXSelection(value: $cursor)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Fmt.distance(v)).foregroundStyle(Theme.sub) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                    AxisValueLabel().foregroundStyle(Theme.sub)
                }
            }
            .frame(height: 200)
        }
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(color).frame(width: 14, height: 4)
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
        }
    }
}

private struct DeltaChart: View {
    let analysis: Analysis
    let cmp: LapComparison
    @Binding var cursor: Double?

    var body: some View {
        let lap = analysis.lap
        let points = thin(lap.trace).map { p in (d: p.d, delta: cmp.delta(at: p.d)) }
        let final = lap.time - cmp.ref.time
        let color = final <= 0 ? Theme.good : Theme.bad
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Delta sul riferimento").font(.caption.weight(.heavy)).foregroundStyle(Theme.text)
                Spacer()
                Text(Fmt.delta(final))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            Chart {
                RuleMark(y: .value("Zero", 0.0)).foregroundStyle(Theme.sub.opacity(0.6))
                ForEach(Array(points.enumerated()), id: \.offset) { item in
                    AreaMark(x: .value("Distanza", item.element.d),
                             yStart: .value("Zero", 0.0),
                             yEnd: .value("Delta", item.element.delta))
                        .foregroundStyle(color.opacity(0.18))
                    LineMark(x: .value("Distanza", item.element.d), y: .value("Delta", item.element.delta))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let cursor {
                    RuleMark(x: .value("Cursore", cursor))
                        .foregroundStyle(Theme.text.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXScale(domain: 0...max(1, lap.distance))
            .chartXSelection(value: $cursor)
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Fmt.distance(v)).foregroundStyle(Theme.sub) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                    AxisValueLabel {
                        if let v = value.as(Double.self) { Text(Fmt.delta(v)).foregroundStyle(Theme.sub) }
                    }
                }
            }
            .frame(height: 170)
        }
    }
}

/// The lap on the satellite map, coloured by speed or by where time is gained against the
/// reference, with the corner speeds and the cursor of both laps.
private struct AnalysisMap: View {
    let analysis: Analysis
    let mode: MapMode
    let cursor: Double?

    var body: some View {
        let lap = analysis.lap
        let coords = lap.trace.map { Coord($0.lat, $0.lon) }
        Map(initialPosition: .region(TrackGeometry.region(for: coords, minMeters: 300))) {
            if mode == .delta, let cmp = analysis.cmp {
                MapPolyline(coordinates: cmp.ref.trace.map(\.cl))
                    .stroke(Theme.purple.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 6]))
                ForEach(analysis.deltaSegments) { seg in
                    MapPolyline(coordinates: seg.coords)
                        .stroke(seg.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            } else {
                ForEach(analysis.speedSegments) { seg in
                    MapPolyline(coordinates: seg.coords)
                        .stroke(seg.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(Array(analysis.apexes.enumerated()), id: \.offset) { item in
                    Annotation("", coordinate: item.element.cl) {
                        Text(Fmt.speed(item.element.v))
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.text.opacity(0.92), in: Capsule())
                    }
                    .annotationTitles(.hidden)
                }
            }
            if let cursor, let p = lap.trace.point(atDistance: cursor) {
                if let q = analysis.cmp?.refPoint(at: cursor) {
                    Annotation("", coordinate: q.cl) { CursorDot(color: Theme.purple) }
                        .annotationTitles(.hidden)
                }
                Annotation("", coordinate: p.cl) { CursorDot(color: Theme.accent) }
                    .annotationTitles(.hidden)
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .id(lap.id)
    }
}

private struct CursorDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: color.opacity(0.8), radius: 6)
    }
}

private extension TracePoint {
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

private struct ColorSegment: Identifiable {
    let id: Int
    let coords: [CLLocationCoordinate2D]
    let color: Color

    /// Red where slow, green where fast.
    static func speed(_ trace: [TracePoint]) -> [ColorSegment] {
        guard trace.count > 1 else { return [] }
        let lo = trace.map(\.v).min() ?? 0
        let hi = max(trace.map(\.v).max() ?? 1, lo + 1)
        let top = 7
        let levels = trace.dropLast().map { min(top, Int(($0.v - lo) / (hi - lo) * Double(top + 1))) }
        return join(trace.map(\.cl), levels: levels) { speedColor(Double($0) / Double(top)) }
    }

    /// Every 8 m: green where the delta shrinks (time gained), red where it grows (time lost).
    static func delta(_ cmp: LapComparison) -> [ColorSegment] {
        let step = 8.0
        let n = Int(cmp.lap.distance / step)
        guard n > 3 else { return [] }
        let ds = (0...n).map { Double($0) * step }
        let pts = ds.compactMap { cmp.lap.trace.point(atDistance: $0)?.cl }
        guard pts.count == ds.count else { return [] }
        let deltas = ds.map { cmp.delta(at: $0) }
        let raw = (0..<n).map { deltas[$0 + 1] - deltas[$0] }
        let rates = raw.indices.map { i -> Double in
            let w = raw[max(0, i - 2)...min(raw.count - 1, i + 2)]
            return w.reduce(0, +) / Double(w.count)
        }
        // 0.02 s lost or gained every 8 m is a lot: full colour.
        let levels = rates.map { Int((max(-1, min(1, $0 / 0.02)) * 3).rounded()) }
        return join(pts, levels: levels) { deltaColor(Double($0) / 3) }
    }

    /// Consecutive steps on the same level joined into one polyline.
    private static func join(_ pts: [CLLocationCoordinate2D], levels: [Int], color: (Int) -> Color) -> [ColorSegment] {
        guard pts.count > 1, levels.count == pts.count - 1 else { return [] }
        var out: [ColorSegment] = []
        var current = [pts[0]]
        var level = levels[0]
        for i in levels.indices {
            if levels[i] != level {
                out.append(ColorSegment(id: out.count, coords: current, color: color(level)))
                current = [pts[i]]
                level = levels[i]
            }
            current.append(pts[i + 1])
        }
        out.append(ColorSegment(id: out.count, coords: current, color: color(level)))
        return out
    }

    /// 0 = red (slow), 0.5 = yellow, 1 = green (fast).
    private static func speedColor(_ f: Double) -> Color {
        let r: Double
        let g: Double
        if f < 0.5 {
            r = 240
            g = 96 + (204 - 96) * (f / 0.5)
        } else {
            r = 250 - (250 - 74) * ((f - 0.5) / 0.5)
            g = 204 + (214 - 204) * ((f - 0.5) / 0.5)
        }
        return Color(rgb: r, g, f < 0.5 ? 80 : 80 + 44 * ((f - 0.5) / 0.5))
    }

    /// −1 = green (gaining), 0 = grey, 1 = red (losing).
    private static func deltaColor(_ f: Double) -> Color {
        let n = (r: 200.0, g: 200.0, b: 210.0)
        let to = f < 0 ? (r: 74.0, g: 214.0, b: 124.0) : (r: 240.0, g: 96.0, b: 80.0)
        let k = abs(f)
        return Color(rgb: n.r + (to.r - n.r) * k, n.g + (to.g - n.g) * k, n.b + (to.b - n.b) * k)
    }
}

/// Sector times of this lap next to the reference.
private struct SectorCompare: View {
    let lap: Lap
    let ref: Lap

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(lap.sectors.enumerated()), id: \.offset) { item in
                row("S\(item.offset + 1)", item.element, ref.sectors[item.offset])
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            row(L("Giro"), lap.time, ref.time)
        }
    }

    private func row(_ name: String, _ a: Double, _ b: Double) -> some View {
        let d = a - b
        return HStack(spacing: 12) {
            Text(verbatim: name)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Theme.sub)
                .frame(width: 40, alignment: .leading)
            Text(Fmt.sector(a)).foregroundStyle(Theme.accent)
            Spacer(minLength: 0)
            Text(Fmt.sector(b)).foregroundStyle(Theme.purple.opacity(0.9))
            Text(Fmt.delta(d))
                .foregroundStyle(d <= 0 ? Theme.good : Theme.bad)
                .frame(width: 66, alignment: .trailing)
        }
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .monospacedDigit()
    }
}

/// The friction circle: every point of the lap by lateral and longitudinal g.
private struct GGDiagram: View {
    let g: [GPoint]
    let ref: [GPoint]

    var body: some View {
        let lateral = g.map { abs($0.lateral) }.max() ?? 0
        let braking = -(g.map(\.longitudinal).min() ?? 0)
        let accel = g.map(\.longitudinal).max() ?? 0
        let peak = max(1.0, (g + ref).map(\.total).max() ?? 1)
        let range = (peak * 1.1 * 2).rounded(.up) / 2
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                StatTile(title: L("Laterale"), value: String(format: "%.2f", lateral), unit: "g")
                StatTile(title: L("Frenata"), value: String(format: "%.2f", max(0, braking)), unit: "g")
                StatTile(title: L("Spinta"), value: String(format: "%.2f", max(0, accel)), unit: "g")
            }
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let k = min(size.width, size.height) / 2 / CGFloat(range)
                var ring = 0.5
                while ring <= range + 0.001 {
                    let r = CGFloat(ring) * k
                    let whole = ring.truncatingRemainder(dividingBy: 1) == 0
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(Theme.line), lineWidth: whole ? 1.2 : 0.6)
                    ctx.draw(Text(String(format: "%.1f g", ring)).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.sub),
                             at: CGPoint(x: c.x + r * 0.71 + 2, y: c.y - r * 0.71 - 2), anchor: .bottomLeading)
                    ring += 0.5
                }
                let edge = CGFloat(range) * k
                var axes = Path()
                axes.move(to: CGPoint(x: c.x - edge, y: c.y))
                axes.addLine(to: CGPoint(x: c.x + edge, y: c.y))
                axes.move(to: CGPoint(x: c.x, y: c.y - edge))
                axes.addLine(to: CGPoint(x: c.x, y: c.y + edge))
                ctx.stroke(axes, with: .color(Theme.line), lineWidth: 1)

                var refDots = Path()
                for p in ref where p.total > 0 {
                    refDots.addEllipse(in: CGRect(x: c.x + CGFloat(p.lateral) * k - 1.5, y: c.y - CGFloat(p.longitudinal) * k - 1.5, width: 3, height: 3))
                }
                ctx.fill(refDots, with: .color(Theme.purple.opacity(0.3)))
                var dots = Path()
                for p in g where p.total > 0 {
                    dots.addEllipse(in: CGRect(x: c.x + CGFloat(p.lateral) * k - 1.75, y: c.y - CGFloat(p.longitudinal) * k - 1.75, width: 3.5, height: 3.5))
                }
                ctx.fill(dots, with: .color(Theme.accent.opacity(0.6)))
            }
            .frame(height: 260)
            .overlay(alignment: .top) { axisLabel(L("Accelerazione")) }
            .overlay(alignment: .bottom) { axisLabel(L("Frenata")) }
            .overlay(alignment: .leading) { axisLabel(L("Sinistra")) }
            .overlay(alignment: .trailing) { axisLabel(L("Destra")) }
            Text("Calcolate dal GPS: con l'ESP32 a 10 Hz sono affidabili, con il GPS dell'iPhone solo indicative.")
                .font(.caption)
                .foregroundStyle(Theme.sub)
        }
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Theme.sub)
            .padding(4)
            .background(Theme.panel.opacity(0.8), in: Capsule())
    }
}

private struct LapRow: View {
    let lap: Lap
    let bestTime: Double
    let bestSectors: [Double]
    let isBest: Bool
    let selected: Bool
    var isReference = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 12) {
            Text("\(lap.number)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? Color.black : Theme.sub)
                .frame(width: 30, height: 30)
                .background(selected ? Theme.accent : (isReference ? Theme.purple.opacity(0.35) : Theme.button), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.lap(lap.time))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isBest ? Theme.purple : Theme.text)
                Text(isBest ? L("BEST") : Fmt.delta(lap.time - bestTime))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(isBest ? Theme.purple : Theme.bad)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(Array(lap.sectors.enumerated()), id: \.offset) { item in
                    let isBestSector = item.offset < bestSectors.count && item.element <= bestSectors[item.offset] + 0.0005
                    VStack(spacing: 1) {
                        Text("S\(item.offset + 1)").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.sub)
                        Text(Fmt.sector(item.element))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isBestSector ? Theme.purple : Theme.text)
                    }
                }
            }
        }
        .padding(12)
        .background(selected ? Theme.accent.opacity(0.08) : Theme.panel, in: shape)
        .overlay(shape.strokeBorder(selected ? Theme.accent.opacity(0.8) : (isReference ? Theme.purple.opacity(0.6) : Theme.line.opacity(0.8)), lineWidth: 1))
        .contentShape(shape)
    }
}

/// Every third point is plenty for a chart.
private func thin(_ trace: [TracePoint]) -> [TracePoint] {
    trace.enumerated().compactMap { $0.offset % 3 == 0 ? $0.element : nil }
}
