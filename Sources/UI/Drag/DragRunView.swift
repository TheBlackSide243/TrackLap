import SwiftUI
import Charts

/// One drag run: every measure, speed and acceleration against time, and a picture to send.
struct DragRunView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let runID: UUID

    @State private var run: DragRun?
    @State private var picture: Image?
    @State private var confirmDelete = false
    @State private var showingCar: UUID?

    var body: some View {
        ScrollView {
            if let run {
                content(run)
            } else {
                ProgressView().padding(60)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(run?.standing == false ? L("Ripresa") : L("Corsa drag"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let picture {
                        ShareLink(item: picture, preview: SharePreview(L("Corsa drag"), image: picture)) {
                            Label("Condividi l'immagine", systemImage: "photo")
                        }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina corsa", systemImage: "trash") }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .confirmationDialog(L("Eliminare questa corsa?"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina corsa", role: .destructive) {
                model.deleteDragRun(runID)
                dismiss()
            }
        }
        .navigationDestination(item: $showingCar) { CarDetailView(carID: $0) }
        .onAppear(perform: load)
    }

    private func load() {
        guard run == nil, let r = model.drags.load(runID) else { return }
        run = r
        let renderer = ImageRenderer(content: DragShareCard(run: r).environment(\.colorScheme, .dark))
        renderer.scale = 3
        if let ui = renderer.uiImage { picture = Image(uiImage: ui) }
    }

    private func content(_ r: DragRun) -> some View {
        let s = r.summary
        return VStack(spacing: 14) {
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(r.vehicle.isEmpty ? (r.standing ? L("Da fermo") : L("In movimento")) : r.vehicle)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(Theme.text)
                    Text(Fmt.day.string(from: r.date)).font(.subheadline).foregroundStyle(Theme.sub)
                    HStack(spacing: 6) {
                        Badge(text: r.standing ? L("Da fermo") : L("Ripresa"), color: Theme.accent)
                        Badge(text: SourceKind(rawValue: r.source)?.short ?? r.source, color: Theme.sub)
                        if r.rollout { Badge(text: "Rollout 1 ft", color: Theme.yellow) }
                    }
                    if let car = model.garage.car(r.carID) {
                        Button { showingCar = car.id } label: {
                            HStack(spacing: 10) {
                                CarPhotoView(photo: car.info.photo)
                                    .frame(width: 44, height: 33)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(car.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                    Text(car.info.subtitle.isEmpty ? L("Dal tuo garage") : car.info.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(Theme.sub)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.sub)
                            }
                            .padding(8)
                            .background(Theme.input, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                        .padding(.top, 4)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                StatTile(title: L("V max"), value: Fmt.speed(r.maxSpeed), unit: Fmt.speedUnit)
                StatTile(title: L("Picco"), value: String(format: "%.2f", r.peakG), unit: "g", color: Theme.good)
                StatTile(title: L("Distanza"), value: Fmt.distance(r.trace.last?.d))
                StatTile(title: L("Pendenza"), value: s.slope.map(Fmt.slope) ?? "—",
                         color: (s.slope ?? 0) < -1 ? Theme.yellow : Theme.text)
                StatTile(title: L("Frequenza"), value: Fmt.hz(r.rate), color: r.rate >= 9 ? Theme.good : Theme.yellow)
                StatTile(title: L("Misure"), value: "\(r.results.count)")
            }

            if let slope = s.slope, slope < -1 {
                Text("In discesa: i tempi non sono confrontabili con quelli in piano.")
                    .font(.caption)
                    .foregroundStyle(Theme.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Panel { ResultGrid(results: r.results, standing: r.standing, records: model.drags.records(car: r.carID)) }

            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Velocità").font(.caption.weight(.heavy)).foregroundStyle(Theme.text)
                    DragChart(run: r).frame(height: 220)
                }
            }

            let g = DragAccelChart.points(r.trace)
            if g.count > 2 {
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Accelerazione").font(.caption.weight(.heavy)).foregroundStyle(Theme.text)
                        DragAccelChart(points: g).frame(height: 160)
                    }
                }
            }
        }
        .padding(16)
    }
}

/// Longitudinal g against time, from the change of speed over the fixes around each one.
struct DragAccelChart: View {
    let points: [(t: Double, g: Double)]

    var body: some View {
        Chart {
            RuleMark(y: .value("Zero", 0.0)).foregroundStyle(Theme.sub.opacity(0.6))
            ForEach(Array(points.enumerated()), id: \.offset) { item in
                AreaMark(x: .value("s", item.element.t), y: .value("g", item.element.g))
                    .foregroundStyle(Theme.good.opacity(0.18))
                LineMark(x: .value("s", item.element.t), y: .value("g", item.element.g))
                    .foregroundStyle(Theme.good)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(verbatim: "\(Int(v)) s").foregroundStyle(Theme.sub) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(verbatim: String(format: "%.1f g", v)).foregroundStyle(Theme.sub) }
                }
            }
        }
    }

    /// Over two fixes each side, so the GPS noise does not show; at most about 300 points.
    static func points(_ trace: [DragPoint]) -> [(t: Double, g: Double)] {
        guard trace.count > 5 else { return [] }
        let step = max(1, trace.count / 300)
        return stride(from: 2, to: trace.count - 2, by: step).compactMap { i in
            let a = trace[i - 2], b = trace[i + 2]
            guard b.t > a.t else { return nil }
            return (trace[i].t, (b.v - a.v) / (b.t - a.t) / 9.80665)
        }
    }
}

/// The run as a picture to send: the main measures big, the chart, the others below.
struct DragShareCard: View {
    let run: DragRun

    var body: some View {
        let main = DragMeasure.all().filter(\.headline).compactMap { run.result($0.name) }
        let rest = run.results.filter { r in !main.contains { $0.name == r.name } }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "speedometer").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.accent)
                Text(verbatim: "TRACKLAP DRAG")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(Fmt.day.string(from: run.date)).font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
            }
            if !run.vehicle.isEmpty {
                Text(verbatim: run.vehicle).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(Theme.text)
            }
            HStack(spacing: 10) {
                ForEach(main) { r in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: r.name).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.sub)
                        Text(r.kind == .braking ? Fmt.shortDistance(r.distance) : Fmt.dragTime(r.time))
                            .font(Theme.timeFont(30))
                            .monospacedDigit()
                            .foregroundStyle(Theme.purple)
                        Text(r.kind == .braking ? Fmt.shortDistanceUnit
                             : r.kind == .distance ? "s · \(Fmt.speed(r.speed)) \(Fmt.speedUnit)" : "s")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.sub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            if run.trace.count > 2 { DragChart(run: run).frame(height: 150) }
            if !rest.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 6) {
                    ForEach(rest) { r in
                        HStack {
                            Text(verbatim: r.name).font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                            Spacer()
                            Text(r.kind == .braking ? "\(Fmt.shortDistance(r.distance)) \(Fmt.shortDistanceUnit)" : "\(Fmt.dragTime(r.time)) s")
                                .font(.caption.weight(.heavy))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text(verbatim: "\(SourceKind(rawValue: run.source)?.title ?? run.source) · \(Fmt.hz(run.rate))")
                if run.rollout { Text(verbatim: "· rollout 1 ft") }
                if let slope = run.summary.slope { Text(verbatim: "· \(Fmt.slope(slope))") }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.sub)
        }
        .padding(22)
        .frame(width: 400)
        .background(Theme.bg)
    }
}
