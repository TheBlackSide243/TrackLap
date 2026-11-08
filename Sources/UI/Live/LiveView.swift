import SwiftUI
import UIKit
import MapKit

struct LiveView: View {
    @Environment(AppModel.self) private var model
    @State private var banner: LapEvent?

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        if geo.size.width > geo.size.height { wide } else { tall }
                    }
                    .scrollIndicators(.hidden)
                    .task {
                        // Screenshot mode: down to the live group.
                        guard Showcase.screen == .group else { return }
                        try? await Task.sleep(for: .seconds(3))
                        proxy.scrollTo("multiplayer", anchor: .bottom)
                    }
                }
            }
            if let banner {
                LapBanner(event: banner)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .onChange(of: model.engine.lastEvent) { _, event in show(event) }
    }

    private var ready: Bool { model.selectedTrack?.isReady == true }

    private var tall: some View {
        VStack(spacing: 14) {
            LiveHeader()
            WeatherHint()
            if ready {
                LapTimerCard()
                DeltaCard()
                SectorRow()
                LiveStatsRow()
                MiniMapCard().frame(height: 210)
                SessionButton()
                if Edition.online { MultiplayerCard().id("multiplayer") }
            } else {
                NoTrackCard()
            }
        }
        .padding(16)
    }

    /// Landscape, for a phone mounted on the dashboard.
    private var wide: some View {
        VStack(spacing: 14) {
            LiveHeader()
            WeatherHint()
            if ready {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 14) {
                        LapTimerCard()
                        DeltaCard()
                        SectorRow()
                    }
                    VStack(spacing: 14) {
                        LiveStatsRow()
                        MiniMapCard().frame(height: 150)
                        SessionButton()
                        if Edition.online { MultiplayerCard() }
                    }
                }
            } else {
                NoTrackCard()
            }
        }
        .padding(16)
    }

    private func show(_ event: LapEvent?) {
        guard let event else { return }
        if event.isBest {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { banner = event }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeInOut(duration: 0.3)) {
                if banner == event { banner = nil }
            }
        }
    }
}

private struct LiveHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(icon: "flag.checkered", title: "TrackLap", subtitle: trackTitle) {
                if model.isRunning { RecordingBadge() }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    pills
                    if Edition.online {
                        ActiveCarChip()
                        ActiveSetupChip()
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        pills
                        Spacer(minLength: 0)
                    }
                    if Edition.online {
                        HStack(spacing: 8) {
                            ActiveCarChip()
                            ActiveSetupChip()
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    /// The track, and the layout it is on when it has several: it follows the one you drive.
    private var trackTitle: String {
        guard let t = model.selectedTrack else { return L("Nessuna pista") }
        guard let layouts = t.layouts, layouts.count > 1, let i = layouts.firstIndex(where: { $0.key == t.activeLayout }) else { return t.name }
        let l = layouts[i]
        return t.name + " · " + (l.name.isEmpty ? (i == 0 ? L("Giro completo") : L("Variante \(i)")) : l.name)
    }

    @ViewBuilder
    private var pills: some View {
        GPSPill()
        StatusPill(icon: model.source.icon, text: model.source.short, color: Theme.accent)
        if let p = model.group.place {
            StatusPill(icon: "person.3.fill", text: "P\(p.position)/\(p.count)", color: Theme.yellow)
        }
    }
}

private struct RecordingBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "record.circle.fill").symbolEffect(.pulse)
            Text("REC").font(.caption.weight(.heavy))
        }
        .foregroundStyle(Theme.bad)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.bad.opacity(0.14), in: Capsule())
    }
}

struct GPSPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let age = model.lastFixWall.map { ctx.date.timeIntervalSince($0) } ?? .infinity
            let ok = age < 2.5
            let sats = model.source == .device && model.ble.sats > 0 ? " · \(model.ble.sats) sat" : ""
            StatusPill(icon: "location.fill",
                       text: ok ? "GPS \(Fmt.hz(model.gpsRate))\(sats)" : L("GPS assente"),
                       color: ok ? (model.gpsRate >= 5 ? Theme.good : Theme.yellow) : Theme.bad)
        }
    }
}

private struct LapTimerCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        Panel(padding: 20, glow: model.isRunning ? Theme.accent : nil) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(Theme.accent)
                    Spacer()
                    if let p = engine.predicted {
                        Text("PREVISTO  \(Fmt.lap(p))")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.sub)
                    }
                }
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(model.isRunning && engine.isTiming))) { ctx in
                    Text(Fmt.lap(elapsed(at: ctx.date)))
                        .font(Theme.timeFont(80))
                        .monospacedDigit()
                        .foregroundStyle(model.isRunning ? Theme.text : Theme.sub)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var label: String {
        guard model.isRunning else { return L("PRONTO") }
        return model.engine.lapNumber == 0 ? L("GIRO DI LANCIO") : L("GIRO \(model.engine.lapNumber)")
    }

    private func elapsed(at date: Date) -> Double {
        guard model.isRunning, let start = model.engine.lapStartWall else { return 0 }
        return max(0, date.timeIntervalSince(start))
    }
}

private struct DeltaCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.engine.delta
        let color = d.map { $0 <= 0 ? Theme.good : Theme.bad } ?? Theme.sub
        Panel(glow: d == nil ? nil : color) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DELTA")
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.sub)
                        Text(caption(d))
                            .font(.caption)
                            .foregroundStyle(Theme.sub.opacity(0.8))
                    }
                    Spacer()
                    Text(Fmt.delta(d))
                        .font(Theme.timeFont(46))
                        .monospacedDigit()
                        .foregroundStyle(color)
                        .contentTransition(.numericText(value: d ?? 0))
                        .animation(.snappy(duration: 0.2), value: d)
                }
                DeltaBar(delta: d, scale: model.deltaScale)
                ChallengeMenu()
            }
        }
    }

    private func caption(_ d: Double?) -> String {
        let engine = model.engine
        if let name = engine.ghostName, let ghost = engine.ghost {
            return L("sul giro di \(name) (\(Fmt.lap(ghost.time)))")
        }
        if engine.comparesWithRecord {
            return L("sul record della pista (\(Fmt.lap(engine.referenceLap?.time)))")
        }
        return d == nil ? L("Completa un giro per il confronto") : L("sul tuo giro migliore")
    }
}

/// The friend's lap to chase, picked from the laps friends sent for this track.
private struct ChallengeMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let laps = Edition.online ? model.friends.laps(on: model.selectedTrackID) : []
        if !laps.isEmpty {
            Menu {
                Button { model.setChallenge(nil) } label: {
                    if model.challenge == nil { Label("Nessuna sfida", systemImage: "checkmark") } else { Text("Nessuna sfida") }
                }
                ForEach(laps) { f in
                    Button { model.setChallenge(f) } label: {
                        if model.challenge?.id == f.id { Label(f.title, systemImage: "checkmark") } else { Text(f.title) }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flag.2.crossed.fill")
                    Text(model.challenge.map { L("Sfida: \($0.driver)") } ?? L("Sfida un amico"))
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(model.challenge == nil ? Theme.sub : Theme.yellow)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background((model.challenge == nil ? Theme.input : Theme.yellow.opacity(0.14)), in: Capsule())
            }
        }
    }
}

/// Zero in the middle: green grows to the left when faster, red to the right when slower.
struct DeltaBar: View {
    let delta: Double?
    let scale: Double

    var body: some View {
        GeometryReader { g in
            let half = g.size.width / 2
            let v = max(-1, min(1, (delta ?? 0) / scale))
            let w = CGFloat(abs(v)) * half
            let color = v <= 0 ? Theme.good : Theme.bad
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.input)
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: v <= 0 ? .trailing : .leading, endPoint: v <= 0 ? .leading : .trailing))
                    .frame(width: w)
                    .offset(x: v <= 0 ? half - w : half)
                    .shadow(color: color.opacity(0.6), radius: 6)
                Rectangle().fill(Theme.text.opacity(0.7)).frame(width: 2).offset(x: half - 1)
            }
            .animation(.snappy(duration: 0.2), value: v)
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }
}

private struct SectorRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sectors = model.engine.sectors
        if !sectors.isEmpty {
            HStack(spacing: 10) {
                ForEach(sectors) { SectorChip(sector: $0) }
            }
        }
    }
}

private struct SectorChip: View {
    let sector: LiveSector

    var body: some View {
        let live = sector.time != nil
        let state = live ? sector.state : sector.previousState
        let value = sector.time ?? sector.previous
        let color = state.map(Theme.color(for:)) ?? Theme.sub
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(spacing: 4) {
            Text("S\(sector.id + 1)")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(live ? color : Theme.sub)
            Text(value.map(Fmt.sector) ?? "—")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(live ? Theme.text : Theme.sub.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(live ? 0.2 : 0.06), in: shape)
        .overlay(shape.strokeBorder(color.opacity(live ? 0.9 : 0.25), lineWidth: 1.5))
        .animation(.easeOut(duration: 0.25), value: sector.time)
    }
}

private struct LiveStatsRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        HStack(spacing: 10) {
            StatTile(title: L("Ultimo"), value: Fmt.lap(engine.lastLap?.time))
            StatTile(title: L("Best"), value: Fmt.lap(engine.bestLap?.time),
                     color: engine.bestLap == nil ? Theme.text : Theme.purple)
            StatTile(title: L("Velocità"), value: Fmt.speed(engine.speed), unit: Fmt.speedUnit)
            if model.drivenKind.onTwoWheels {
                StatTile(title: L("Piega"), value: "\(Int(LapEngine.lean(engine.lateralG).rounded()))°")
            }
        }
    }
}

private struct MiniMapCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let track = model.selectedTrack {
            Panel(padding: 8) {
                ZStack(alignment: .topLeading) {
                    TrackSatelliteMap(track: track, position: model.engine.position, friends: friends)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    HStack(spacing: 6) {
                        Badge(text: L("Giri: \(model.engine.laps.count)"))
                        if let l = track.length { Badge(text: Fmt.distance(l), color: Theme.sub) }
                    }
                    .padding(8)
                }
            }
        }
    }

    /// The cars of the live group on this track, as their latest position put them.
    private var friends: [FriendDot] {
        model.group.members.compactMap { m in
            guard m.online, let p = m.position, Date().timeIntervalSince(p.received) < 10,
                  model.group.mine.track?.isSame(as: m.track) ?? false else { return nil }
            return FriendDot(id: m.id, coord: p.coord, color: GroupColors.color(m.color), initial: String(m.name.prefix(1)).uppercased())
        }
    }
}

private struct FriendDot: Identifiable {
    let id: String
    let coord: Coord
    let color: Color
    let initial: String
}

/// The circuit on satellite imagery, framed on the whole track and not draggable: the outline, the
/// start line in white, the sector lines in yellow, the car and the cars of the group.
private struct TrackSatelliteMap: View {
    let track: Track
    let position: Coord?
    var friends: [FriendDot] = []

    var body: some View {
        Map(initialPosition: .region(TrackGeometry.region(for: track.allPoints, minMeters: 300)), interactionModes: []) {
            ForEach(Array(track.outline.enumerated()), id: \.offset) { item in
                MapPolyline(coordinates: item.element.map(\.cl))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(track.sectors.enumerated()), id: \.offset) { item in
                MapPolyline(coordinates: [item.element.a.cl, item.element.b.cl])
                    .stroke(Theme.yellow, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let s = track.start {
                MapPolyline(coordinates: [s.a.cl, s.b.cl])
                    .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            ForEach(friends) { f in
                Annotation("", coordinate: f.coord.cl) {
                    Text(verbatim: f.initial)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.black)
                        .frame(width: 17, height: 17)
                        .background(f.color, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                }
                .annotationTitles(.hidden)
            }
            if let position {
                Annotation("", coordinate: position.cl) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: Theme.accent.opacity(0.8), radius: 6)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.imagery(elevation: .flat))
        .id(track.id)
    }
}

private struct SessionButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Button {
                if model.isRunning { model.stop() } else { model.start() }
            } label: {
                Label(model.isRunning ? L("Ferma sessione") : L("Avvia sessione"),
                      systemImage: model.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(PrimaryButtonStyle(color: model.isRunning ? Theme.bad : Theme.accent))
            .sensoryFeedback(.impact, trigger: model.isRunning)

            Text(hint)
                .font(.caption)
                .foregroundStyle(Theme.sub)
                .multilineTextAlignment(.center)
        }
    }

    private var hint: String {
        switch model.source {
        case .demo: return L("Demo: un'auto simulata gira sulla pista selezionata.")
        case .phone: return L("GPS dell'iPhone, circa 1 Hz: per tempi precisi usa l'ESP32.")
        case .device:
            return model.ble.state == .connected ? L("Il giro parte al primo passaggio sulla linea del via.")
                : L("Collega l'ESP32 nella scheda Dispositivo.")
        }
    }
}

private struct NoTrackCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Panel(padding: 24, glow: Theme.accent) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(model.selectedTrack == nil ? L("Scegli una pista") : L("Segna la linea del via"))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Theme.text)
                Text("Cerca il circuito su OpenStreetMap, poi tocca la pista sulla mappa satellitare per mettere il via e gli intermedi.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
                Button {
                    model.tab = .tracks
                } label: {
                    Label("Vai alle piste", systemImage: "map.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

private struct LapBanner: View {
    let event: LapEvent

    var body: some View {
        let color = event.isRecord ? Theme.yellow : event.isBest ? Theme.purple : ((event.gap ?? 0) <= 0 ? Theme.good : Theme.yellow)
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        HStack(spacing: 14) {
            Image(systemName: event.isRecord ? "trophy.fill" : event.isBest ? "crown.fill" : "flag.checkered")
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(event.isRecord ? L("GIRO \(event.number) · RECORD PISTA")
                     : event.isBest ? L("GIRO \(event.number) · NUOVO BEST") : L("GIRO \(event.number)"))
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(color)
                Text(Fmt.lap(event.time))
                    .font(Theme.timeFont(32))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let gap = event.gap {
                    Text(Fmt.delta(gap))
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(gap <= 0 ? Theme.good : Theme.bad)
                }
                if let rival = event.rival, let gap = event.rivalGap {
                    Text(L("vs \(rival) \(Fmt.delta(gap))"))
                        .font(.caption.weight(.heavy))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(gap <= 0 ? Theme.good : Theme.bad)
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.strokeBorder(color.opacity(0.8), lineWidth: 1.5))
        .shadow(color: color.opacity(0.4), radius: 24)
    }
}

/// Rain at the track and a setup for the wet in your garage (or sun and one for the dry): Live
/// offers to switch before the session starts.
private struct WeatherHint: View {
    @Environment(AppModel.self) private var model
    @State private var now: TrackWeather.Now?
    @State private var dismissed: String?

    var body: some View {
        Group {
            if let pick = suggestion, !model.isRunning, dismissed != pick.0.id.uuidString + pick.1.rawValue {
                let setup = pick.0
                let wanted = pick.1
                Panel(padding: 14, glow: wanted == .wet ? Color(rgb: 96, 165, 250) : Theme.yellow) {
                    HStack(spacing: 12) {
                        WeatherGlyph(weather: wanted, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(wanted)).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                            Text(L("Usare l'assetto \(setup.displayName)?")).font(.caption).foregroundStyle(Theme.sub).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Button(L("Usa")) {
                            withAnimation { model.setActiveSetup(setup.id) }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.accent, in: Capsule())
                        Button { withAnimation { dismissed = setup.id.uuidString + wanted.rawValue } } label: {
                            Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                        }
                        .accessibilityLabel(L("Chiudi"))
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: model.selectedTrackID) {
            guard let t = model.selectedTrack, !t.isDemo else { return }
            now = await TrackWeather.now(at: t.start?.mid ?? t.center)
        }
    }

    /// A setup of the car in use for the weather now, when the one in use is for other conditions.
    private var suggestion: (CarSetup, SetupWeather)? {
        guard let now, let car = model.activeCar else { return nil }
        let wanted: SetupWeather = now.wet ? .wet : .dry
        if model.activeSetup?.weather == wanted { return nil }
        let list = model.garage.setups(of: car.id).filter { $0.weather == wanted }
        let track = model.selectedTrack?.name ?? ""
        guard let s = list.first(where: { !$0.track.isEmpty && track.localizedCaseInsensitiveContains($0.track) }) ?? list.first else { return nil }
        return (s, wanted)
    }

    private func title(_ w: SetupWeather) -> String {
        let place = model.selectedTrack?.name ?? ""
        let temp = now?.temperature.map { " · \(Int($0.rounded()))°" } ?? ""
        return (w == .wet ? L("Piove a \(place)") : L("Asciutto a \(place)")) + temp
    }
}
