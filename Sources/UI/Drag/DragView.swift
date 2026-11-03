import SwiftUI
import Charts

/// Acceleration and braking, like a performance meter: stop, go, and the measures fill in as they
/// are done; then the records and every run.
struct DragView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var banner: DragEvent?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 14) {
                        DragHeader()
                        if model.isRunning {
                            BusyCard()
                        } else {
                            SpeedCard()
                            SourceNote()
                            if let run = model.drag.run {
                                RunCard(run: run, live: model.drag.inProgress) {
                                    if !model.drag.inProgress { path = [run.id] }
                                }
                            }
                            RecordsCard()
                            HistoryList()
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
                if let banner {
                    DragBanner(event: banner)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { DragRunView(runID: $0) }
            .onAppear {
                if Showcase.screen == .dragRun, path.isEmpty, let latest = model.drags.summaries.first { path = [latest.id] }
            }
        }
        .onChange(of: model.drag.lastEvent) { _, e in show(e) }
    }

    private func show(_ event: DragEvent?) {
        guard let event else { return }
        if event.isRecord {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { banner = event }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.3)) {
                if banner == event { banner = nil }
            }
        }
    }
}

private struct DragHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(icon: "speedometer", title: "Drag", subtitle: subtitle) {
                Menu {
                    Toggle(isOn: Binding(get: { model.dragRollout }, set: { model.setDragRollout($0) })) {
                        Label("Rollout di 1 ft", systemImage: "ruler")
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, height: 40)
                        .background(Theme.panel, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
                }
            }
            HStack(spacing: 8) {
                GPSPill()
                StatusPill(icon: model.source.icon, text: model.source.short, color: Theme.accent)
                if model.dragRollout { StatusPill(icon: "ruler", text: "Rollout", color: Theme.yellow) }
                Spacer(minLength: 0)
            }
        }
    }

    private var subtitle: String {
        model.profile.displayVehicle.isEmpty ? L("Accelerazione e frenata") : model.profile.displayVehicle
    }
}

/// Drag runs wait while a lap session is timing.
private struct BusyCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Panel(padding: 24, glow: Theme.yellow) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "stopwatch.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.yellow)
                Text("Sessione in corso").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                Text("Mentre cronometri i giri le corse drag sono in pausa: ferma la sessione in Live per misurare.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
                Button { model.tab = .live } label: { Label("Vai a Live", systemImage: "stopwatch.fill") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

/// The speed, big, with what the timer is waiting for.
private struct SpeedCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let drag = model.drag
        let color = self.color(drag.phase)
        Panel(padding: 20, glow: color) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(color)
                    Spacer()
                    if drag.inProgress {
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                            Text(Fmt.dragTime(drag.startWall.map { ctx.date.timeIntervalSince($0) }) + " s")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Fmt.speed(drag.speed))
                        .font(Theme.timeFont(96))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText(value: drag.speed))
                        .animation(.snappy(duration: 0.15), value: Int(drag.speed * Fmt.speedFactor))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(Fmt.speedUnit).font(.title3.weight(.bold)).foregroundStyle(Theme.sub)
                    Spacer(minLength: 0)
                }
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    StatTile(title: L("Accelerazione"), value: String(format: "%.2f", drag.accel / 9.80665), unit: "g",
                             color: drag.accel > 0.5 ? Theme.good : drag.accel < -0.5 ? Theme.bad : Theme.text)
                    StatTile(title: L("Distanza"), value: drag.inProgress ? Fmt.distance(drag.distance) : "—")
                }
            }
        }
    }

    private var title: String {
        switch model.drag.phase {
        case .moving: L("FERMATI PER PARTIRE")
        case .ready: L("PRONTO")
        case .running: model.drag.run?.standing == false ? L("RIPRESA") : L("IN CORSA")
        }
    }

    private var hint: String {
        switch model.drag.phase {
        case .moving: L("Da fermo il tempo parte da solo appena ti muovi. Riprese e frenate si misurano anche in movimento.")
        case .ready: L("Via quando vuoi: il tempo parte appena l'auto si muove.")
        case .running: L("Fermati o togli gas per chiudere la corsa.")
        }
    }

    private func color(_ p: DragEngine.Phase) -> Color {
        switch p {
        case .moving: Theme.yellow
        case .ready: Theme.good
        case .running: Theme.accent
        }
    }
}

/// What the source is good for: the Demo has a button, the iPhone gives rough times.
private struct SourceNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.source {
        case .demo:
            VStack(spacing: 8) {
                Button { model.startDemoDrag() } label: {
                    Label(model.demoDrag.isRunning ? L("Corsa demo in corso…") : L("Corsa demo"), systemImage: "play.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.demoDrag.isRunning)
                Text("Un'auto simulata parte da ferma, fa un chilometro e frena.")
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
            }
        case .phone:
            Note(icon: "exclamationmark.triangle.fill", color: Theme.yellow,
                 text: L("Il GPS dell'iPhone dà circa un fix al secondo: i tempi sono indicativi, mezzo secondo in più o in meno. Per misure vere serve l'ESP32 a 10 Hz o più."))
        case .device:
            if model.ble.state != .connected {
                Note(icon: "antenna.radiowaves.left.and.right", color: Theme.sub, text: L("Collega l'ESP32 nella scheda Dispositivo."))
            }
        }
    }
}

private struct Note: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.subheadline.weight(.bold)).foregroundStyle(color)
            Text(text).font(.caption).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(color.opacity(0.08), in: shape)
        .overlay(shape.strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}

/// The run in progress or the last one: every measure, filled in as it is done, and its chart.
private struct RunCard: View {
    @Environment(AppModel.self) private var model
    let run: DragRun
    let live: Bool
    let onOpen: () -> Void

    var body: some View {
        Panel(glow: live ? Theme.accent : nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(run.standing ? L("DA FERMO") : L("IN MOVIMENTO"))
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Theme.accent)
                    if live { Badge(text: L("In corso"), color: Theme.bad) }
                    if run.rollout { Badge(text: "Rollout", color: Theme.yellow) }
                    Spacer()
                    if !live {
                        Button(action: onOpen) {
                            HStack(spacing: 4) {
                                Text(Fmt.day.string(from: run.date))
                                Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.sub)
                        }
                    }
                }
                ResultGrid(results: run.results, standing: run.standing, records: model.drags.records(), pending: live)
                if !live && run.trace.count > 2 {
                    DragChart(run: run).frame(height: 170)
                }
            }
        }
    }
}

/// Every measure of a run, two per row; the ones not done are dashes.
struct ResultGrid: View {
    let results: [DragResult]
    let standing: Bool
    let records: [String: DragRecord]
    var pending = false

    var body: some View {
        let measures = DragMeasure.all().filter { standing || !$0.standing }
        let done = Set(results.map(\.name))
        // Measures of other units (a run from before a change of units) come after.
        let others = results.filter { r in !measures.contains { $0.name == r.name } }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(measures) { m in
                ResultTile(name: m.name, result: results.first { $0.name == m.name }, record: records[m.name],
                           waiting: pending && !done.contains(m.name))
            }
            ForEach(others) { r in ResultTile(name: r.name, result: r, record: records[r.name]) }
        }
    }
}

struct ResultTile: View {
    let name: String
    let result: DragResult?
    let record: DragRecord?
    var waiting = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let best = result.map { r in (r.kind == .braking ? r.distance : r.time) <= (record?.value ?? .infinity) + 1e-9 } ?? false
        let color = result == nil ? Theme.sub : best ? Theme.purple : Theme.text
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(verbatim: name).font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.sub)
                if best { Image(systemName: "crown.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.purple) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if result != nil { Text(unit).font(.caption.weight(.semibold)).foregroundStyle(Theme.sub) }
            }
            Text(detail)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.sub)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((best ? Theme.purple : Theme.input).opacity(best ? 0.14 : 0.6), in: shape)
        .overlay(shape.strokeBorder(best ? Theme.purple.opacity(0.6) : Theme.line.opacity(0.6), lineWidth: 1))
        .opacity(waiting ? 0.55 : 1)
        .animation(.easeOut(duration: 0.25), value: result)
    }

    private var value: String {
        guard let r = result else { return "—" }
        return r.kind == .braking ? Fmt.shortDistance(r.distance) : Fmt.dragTime(r.time)
    }

    private var unit: String { result?.kind == .braking ? Fmt.shortDistanceUnit : "s" }

    private var detail: String {
        guard let r = result else { return " " }
        switch r.kind {
        case .distance: return L("a \(Fmt.speed(r.speed)) \(Fmt.speedUnit)")
        case .speed: return L("in \(Fmt.distance(r.distance))")
        case .braking: return L("in \(Fmt.dragTime(r.time)) s")
        }
    }
}

/// Speed against time, with a dot where each measure ended.
struct DragChart: View {
    let run: DragRun

    var body: some View {
        let points = thin(run.trace)
        let headline = Set(DragMeasure.all().filter(\.headline).map(\.name))
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { item in
                AreaMark(x: .value("s", item.element.t), y: .value(Fmt.speedUnit, item.element.v * Fmt.speedFactor))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("s", item.element.t), y: .value(Fmt.speedUnit, item.element.v * Fmt.speedFactor))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            ForEach(run.results) { r in
                PointMark(x: .value("s", r.at), y: .value(Fmt.speedUnit, r.speed * Fmt.speedFactor))
                    .symbolSize(headline.contains(r.name) ? 70 : 30)
                    .foregroundStyle(headline.contains(r.name) ? Theme.purple : Theme.text)
                    .annotation(position: r.kind == .braking ? .topTrailing : .topLeading, spacing: 2) {
                        if headline.contains(r.name) {
                            Text(verbatim: r.name).font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.sub)
                        }
                    }
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
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                AxisValueLabel().foregroundStyle(Theme.sub)
            }
        }
    }

    /// A point every tenth of a second at most: plenty for the eye.
    private func thin(_ trace: [DragPoint]) -> [DragPoint] {
        guard trace.count > 400 else { return trace }
        let step = Int((Double(trace.count) / 400).rounded(.up))
        return trace.enumerated().filter { $0.offset % step == 0 || $0.offset == trace.count - 1 }.map(\.element)
    }
}

/// The best of each measure ever.
private struct RecordsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let records = model.drags.records()
        let measures = DragMeasure.all().filter { records[$0.name] != nil }
        if !measures.isEmpty {
            VStack(spacing: 8) {
                SectionLabel(L("I tuoi record"))
                Panel(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(measures.enumerated()), id: \.element.id) { i, m in
                            if let r = records[m.name] {
                                if i > 0 { Divider().overlay(Theme.line) }
                                RecordRow(measure: m, record: r)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct RecordRow: View {
    let measure: DragMeasure
    let record: DragRecord

    var body: some View {
        let r = record.result
        HStack(spacing: 10) {
            Text(verbatim: measure.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.text)
                .frame(width: 104, alignment: .leading)
            Text(Fmt.dayShort.string(from: record.run.date))
                .font(.caption)
                .foregroundStyle(Theme.sub)
            if record.run.source != SourceKind.device.rawValue {
                Badge(text: SourceKind(rawValue: record.run.source)?.short ?? record.run.source, color: Theme.sub)
            }
            Spacer(minLength: 0)
            Text(r.kind == .braking ? "\(Fmt.shortDistance(r.distance)) \(Fmt.shortDistanceUnit)" : "\(Fmt.dragTime(r.time)) s")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.purple)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Every run, newest first.
private struct HistoryList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let runs = model.drags.summaries
        VStack(spacing: 10) {
            SectionLabel(runs.count == 1 ? L("1 corsa") : L("\(runs.count) corse"))
            if runs.isEmpty {
                Panel(padding: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "flag.checkered").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.accent)
                        Text("Ancora nessuna corsa").font(.headline).foregroundStyle(Theme.text)
                        Text("Fermati in un posto sicuro e chiuso al traffico, poi parti: ogni corsa finisce qui con tutti i tempi e il grafico.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.sub)
                    }
                }
            }
            ForEach(runs) { s in
                NavigationLink(value: s.id) { DragRunRow(summary: s) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { model.deleteDragRun(s.id) } label: {
                            Label("Elimina corsa", systemImage: "trash")
                        }
                    }
            }
        }
    }
}

private struct DragRunRow: View {
    let summary: DragSummary

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.vehicle.isEmpty ? (summary.standing ? L("Da fermo") : L("In movimento")) : summary.vehicle)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(Fmt.day.string(from: summary.date)).font(.caption).foregroundStyle(Theme.sub)
                HStack(spacing: 6) {
                    Badge(text: summary.results.count == 1 ? L("1 misura") : L("\(summary.results.count) misure"), color: Theme.accent)
                    Badge(text: SourceKind(rawValue: summary.source)?.short ?? summary.source, color: Theme.sub)
                    if !summary.standing { Badge(text: L("Ripresa"), color: Theme.yellow) }
                }
            }
            Spacer(minLength: 0)
            if let h = summary.headline {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: h.name).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.sub)
                    Text(h.kind == .braking ? Fmt.shortDistance(h.distance) : Fmt.dragTime(h.time))
                        .font(Theme.timeFont(24))
                        .monospacedDigit()
                        .foregroundStyle(Theme.purple)
                }
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.line)
        }
        .padding(16)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(Theme.line.opacity(0.8), lineWidth: 1))
    }
}

/// A measure just done, at the top of the screen for a few seconds.
private struct DragBanner: View {
    let event: DragEvent

    var body: some View {
        let r = event.result
        let color = event.isRecord ? Theme.yellow : event.isBest ? Theme.purple : Theme.accent
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        HStack(spacing: 14) {
            Image(systemName: event.isRecord ? "trophy.fill" : r.kind == .braking ? "exclamationmark.octagon.fill" : "flag.checkered")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(event.isRecord ? L("\(r.name) · NUOVO RECORD") : r.name)
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(color)
                Text(r.kind == .braking ? "\(Fmt.shortDistance(r.distance)) \(Fmt.shortDistanceUnit)" : "\(Fmt.dragTime(r.time)) s")
                    .font(Theme.timeFont(32))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            Text(r.kind == .distance ? "\(Fmt.speed(r.speed)) \(Fmt.speedUnit)"
                 : r.kind == .braking ? "\(Fmt.dragTime(r.time)) s" : Fmt.distance(r.distance))
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.sub)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(color.opacity(0.8), lineWidth: 1.5))
        .shadow(color: color.opacity(0.4), radius: 24)
    }
}
