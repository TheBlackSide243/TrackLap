import SwiftUI
import Charts
import MapKit

struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    let sessionID: UUID

    @State private var session: Session?
    @State private var selectedLapID: UUID?
    @State private var gpxURL: URL?

    var body: some View {
        ScrollView {
            if let session, !session.laps.isEmpty {
                content(session)
            } else {
                ProgressView().padding(60)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(session?.trackName ?? "Sessione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let gpxURL {
                    ShareLink(item: gpxURL) { Image(systemName: "square.and.arrow.up") }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: model.engine.laps.count) { _, _ in
            if sessionID == model.currentSessionID { load() }
        }
    }

    private func load() {
        guard let s = model.sessions.load(sessionID) else { return }
        session = s
        if selectedLapID == nil || !s.laps.contains(where: { $0.id == selectedLapID }) {
            selectedLapID = s.best?.id
        }
        gpxURL = try? GPX.write(s)
    }

    private func content(_ s: Session) -> some View {
        let best = s.best
        let selected = s.laps.first { $0.id == selectedLapID } ?? best ?? s.laps[0]
        let bestSectors = s.bestSectors
        return VStack(spacing: 14) {
            header(s)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                StatTile(title: "Best", value: Fmt.lap(best?.time), color: Theme.purple)
                StatTile(title: "Ideale", value: Fmt.lap(s.idealTime))
                StatTile(title: "Media", value: Fmt.lap(s.averageTime))
                StatTile(title: "Giri", value: "\(s.laps.count)")
                StatTile(title: "V max", value: Fmt.kmh(s.laps.map(\.maxSpeed).max() ?? 0), unit: "km/h")
                StatTile(title: "Giro", value: Fmt.distance(best?.distance))
            }

            SectionLabel("Tempi sul giro")
            Panel {
                LapTimesChart(laps: s.laps, bestID: best?.id, selectedID: selected.id)
            }

            SectionLabel("Giro \(selected.number) sulla mappa")
            Panel(padding: 6) {
                LapMap(lap: selected)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            SectionLabel("Velocità")
            Panel {
                SpeedChart(lap: selected, best: best)
            }

            if let best, best.id != selected.id {
                SectionLabel("Delta del giro \(selected.number) sul best")
                Panel {
                    DeltaChart(lap: selected, best: best)
                }
            }

            SectionLabel("Giri")
            VStack(spacing: 8) {
                ForEach(s.laps) { lap in
                    LapRow(lap: lap, bestTime: best?.time ?? lap.time, bestSectors: bestSectors,
                           isBest: lap.id == best?.id, selected: lap.id == selected.id)
                        .onTapGesture {
                            withAnimation(.snappy) { selectedLapID = lap.id }
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
        }
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

private struct SpeedChart: View {
    let lap: Lap
    let best: Lap?

    var body: some View {
        let mine = thin(lap.trace)
        let ref = best.flatMap { $0.id == lap.id ? nil : thin($0.trace) } ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                legend("Giro \(lap.number)", Theme.accent)
                if !ref.isEmpty { legend("Best", Theme.purple) }
            }
            Chart {
                ForEach(Array(ref.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("Distanza", item.element.d),
                             y: .value("km/h", item.element.v * 3.6),
                             series: .value("Giro", "Best"))
                        .foregroundStyle(Theme.purple.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
                ForEach(Array(mine.enumerated()), id: \.offset) { item in
                    LineMark(x: .value("Distanza", item.element.d),
                             y: .value("km/h", item.element.v * 3.6),
                             series: .value("Giro", "Selezionato"))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                }
            }
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
    let lap: Lap
    let best: Lap

    var body: some View {
        let points = thin(lap.trace).map { p in (d: p.d, delta: p.t - best.trace.time(atDistance: p.d)) }
        let final = lap.time - best.time
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Alla fine del giro").font(.caption).foregroundStyle(Theme.sub)
                Spacer()
                Text(Fmt.delta(final))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(final <= 0 ? Theme.good : Theme.bad)
            }
            Chart {
                RuleMark(y: .value("Zero", 0.0)).foregroundStyle(Theme.sub.opacity(0.6))
                ForEach(Array(points.enumerated()), id: \.offset) { item in
                    AreaMark(x: .value("Distanza", item.element.d),
                             yStart: .value("Zero", 0.0),
                             yEnd: .value("Delta", item.element.delta))
                        .foregroundStyle((final <= 0 ? Theme.good : Theme.bad).opacity(0.18))
                    LineMark(x: .value("Distanza", item.element.d), y: .value("Delta", item.element.delta))
                        .foregroundStyle(final <= 0 ? Theme.good : Theme.bad)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
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

/// The lap on the satellite map, coloured by speed: red where slow, green where fast.
private struct LapMap: View {
    let lap: Lap

    var body: some View {
        let coords = lap.trace.map { Coord($0.lat, $0.lon) }
        Map(initialPosition: .region(TrackGeometry.region(for: coords, minMeters: 300))) {
            ForEach(SpeedSegment.make(lap.trace)) { seg in
                MapPolyline(coordinates: seg.coords)
                    .stroke(seg.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .id(lap.id)
    }
}

private struct SpeedSegment: Identifiable {
    let id: Int
    let coords: [CLLocationCoordinate2D]
    let color: Color

    static func make(_ trace: [TracePoint]) -> [SpeedSegment] {
        guard trace.count > 1 else { return [] }
        let lo = trace.map(\.v).min() ?? 0
        let hi = max((trace.map(\.v).max() ?? 1), lo + 1)
        let levels = 8
        func level(_ v: Double) -> Int { min(levels - 1, Int((v - lo) / (hi - lo) * Double(levels))) }
        var out: [SpeedSegment] = []
        var current = [CLLocationCoordinate2D(latitude: trace[0].lat, longitude: trace[0].lon)]
        var lvl = level(trace[0].v)
        for p in trace.dropFirst() {
            let c = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lon)
            current.append(c)
            let l = level(p.v)
            if l != lvl {
                out.append(SpeedSegment(id: out.count, coords: current, color: color(Double(lvl) / Double(levels - 1))))
                current = [c]
                lvl = l
            }
        }
        if current.count > 1 {
            out.append(SpeedSegment(id: out.count, coords: current, color: color(Double(lvl) / Double(levels - 1))))
        }
        return out
    }

    /// 0 = red (slow), 0.5 = yellow, 1 = green (fast).
    private static func color(_ f: Double) -> Color {
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
}

private struct LapRow: View {
    let lap: Lap
    let bestTime: Double
    let bestSectors: [Double]
    let isBest: Bool
    let selected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 12) {
            Text("\(lap.number)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(selected ? Color.black : Theme.sub)
                .frame(width: 30, height: 30)
                .background(selected ? Theme.accent : Theme.button, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.lap(lap.time))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isBest ? Theme.purple : Theme.text)
                Text(isBest ? "BEST" : Fmt.delta(lap.time - bestTime))
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
        .overlay(shape.strokeBorder(selected ? Theme.accent.opacity(0.8) : Theme.line.opacity(0.8), lineWidth: 1))
        .contentShape(shape)
    }
}

/// Every third point is plenty for a chart.
private func thin(_ trace: [TracePoint]) -> [TracePoint] {
    trace.enumerated().compactMap { $0.offset % 3 == 0 ? $0.element : nil }
}
