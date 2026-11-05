import SwiftUI

/// The online leaderboard of a track: the best lap of every driver who publishes theirs, with the
/// GPS it was timed with written next to it, and the car it was driven with, a tap away. Yours
/// highlighted.
struct LeaderboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var board: Leaderboard?
    @State private var error: String?
    @State private var filter: BoardFilter = .all
    @State private var sending = false
    @State private var note: String?
    @State private var opened: GarageLink?
    @State private var signingIn = false
    @AppStorage("hiddenGarages") private var hiddenGarages = ""

    enum BoardFilter: Hashable { case all, device, phone }

    private struct Ranked: Identifiable {
        let place: Int
        let entry: Leaderboard.Entry
        var id: String { entry.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("GPS", selection: $filter) {
                        Text("Tutti").tag(BoardFilter.all)
                        Text("GPS esterno").tag(BoardFilter.device)
                        Text("Telefono").tag(BoardFilter.phone)
                    }
                    .pickerStyle(.segmented)

                    if let error {
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(error, systemImage: "wifi.exclamationmark").font(.subheadline).foregroundStyle(Theme.yellow)
                                Button { Task { await load() } } label: { Text("Riprova") }
                                    .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
                            }
                        }
                    } else if let board {
                        rows(ranked(board.laps))
                        if filter == .all && board.laps.contains(where: { $0.source == SourceKind.phone.rawValue })
                            && board.laps.contains(where: { $0.source == SourceKind.device.rawValue }) {
                            Text("Il GPS esterno a 10 Hz misura al centesimo, quello dell'iPhone a 1 Hz è meno preciso: per questo ogni tempo dice con quale è stato fatto.")
                                .font(.caption)
                                .foregroundStyle(Theme.sub)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        ProgressView().tint(Theme.accent).padding(40)
                    }

                    SectionLabel(L("I tuoi giri"))
                    publish
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(track.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fine")) { dismiss() }
                }
            }
            .sheet(item: $opened) { PublicGarageView(link: $0).environment(model) }
            .sheet(isPresented: $signingIn) { AccountSheet().environment(model) }
        }
        .presentationBackground(Theme.bg)
        .task { await load() }
        .onChange(of: model.account.name) { _, _ in Task { await load() } }
    }

    /// The laps shown with their place: per GPS as the server ranks them, or all together by time.
    private func ranked(_ laps: [Leaderboard.Entry]) -> [Ranked] {
        switch filter {
        case .all:
            return laps.sorted { $0.time < $1.time }.enumerated().map { Ranked(place: $0.offset + 1, entry: $0.element) }
        case .device, .phone:
            let source = filter == .device ? SourceKind.device.rawValue : SourceKind.phone.rawValue
            return laps.filter { $0.source == source }.map { Ranked(place: $0.rank, entry: $0) }
        }
    }

    @ViewBuilder
    private func rows(_ laps: [Ranked]) -> some View {
        if laps.isEmpty {
            Panel(padding: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "trophy").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.yellow)
                    Text("Ancora nessun tempo qui").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                    Text("Il primo giro pubblicato su questa pista apre la classifica.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.sub)
                }
            }
        } else {
            let first = laps.first?.entry.time ?? 0
            VStack(spacing: 8) {
                ForEach(laps) { row in
                    let link = row.entry.carLink.flatMap { HiddenGarages.contains($0.code, in: hiddenGarages) ? nil : $0 }
                    BoardRow(entry: row.entry, place: row.place, gap: row.place == 1 ? nil : row.entry.time - first,
                             linked: link != nil) {
                        opened = link
                    }
                }
            }
        }
    }

    private var publish: some View {
        let p = model.profile
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                if let name = model.account.name {
                    Toggle(isOn: Binding(get: { p.publishLaps }, set: { p.setPublish($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pubblica i miei best").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("Il giro migliore di ogni sessione va nella classifica della sua pista, come \(name). Mai i giri della Demo.")
                                .font(.caption)
                                .foregroundStyle(Theme.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.yellow)
                    carLine
                    if let record = model.sessions.record(on: track), SourceKind(sessionSource: record.session.source) != .demo {
                        Button { Task { await send(record) } } label: {
                            if sending { ProgressView() } else {
                                Label(L("Invia il mio record: \(Fmt.lap(record.lap.time))"), systemImage: "paperplane.fill")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
                        .disabled(sending)
                    }
                } else {
                    Text("Per entrare in classifica serve un account: il tuo nome utente è quello che vedono tutti, accanto al tempo e all'auto.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { signingIn = true } label: { Label("Accedi o crea un account", systemImage: "person.fill") }
                        .buttonStyle(PrimaryButtonStyle(color: Theme.yellow))
                }
                if let note {
                    Text(note).font(.caption.weight(.semibold)).foregroundStyle(Theme.good)
                }
            }
        }
    }

    /// Which car your laps link to, and why they might not.
    @ViewBuilder
    private var carLine: some View {
        if let car = model.activeCar {
            HStack(spacing: 10) {
                CarPhotoView(photo: car.info.photo)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(car.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(model.garage.isShown ? L("I tuoi tempi portano a quest'auto del garage")
                         : L("Rendi pubblico il garage perché i tempi portino all'auto"))
                        .font(.caption)
                        .foregroundStyle(model.garage.isShown ? Theme.sub : Theme.yellow)
                }
            }
        } else {
            Label(L("Scegli in Live l'auto che usi: i tuoi tempi porteranno a lei."), systemImage: "car.fill")
                .font(.caption)
                .foregroundStyle(Theme.sub)
        }
    }

    private func load() async {
        error = nil
        do {
            let length = model.sessions.record(on: track)?.lap.distance ?? track.layout?.length ?? track.length
            board = try await Server.board(for: track, length: length, token: model.account.token)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send(_ record: SessionLap) async {
        guard let token = model.account.token else { return }
        sending = true
        defer { sending = false }
        let kind = SourceKind(sessionSource: record.session.source)
        do {
            let r = try await Server.submit(record.lap, source: kind, track: track, car: record.session.carID, token: token)
            note = L("Sei \(r.rank)° su \(r.of) con \(kind == .device ? L("GPS esterno") : L("Telefono")).")
            await load()
        } catch Server.Failure.signedOut {
            model.account.signedOutElsewhere()
        } catch {
            note = nil
            self.error = error.localizedDescription
        }
    }
}

private struct BoardRow: View {
    let entry: Leaderboard.Entry
    let place: Int
    let gap: Double?
    let linked: Bool
    let onOpen: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let medal: Color? = place == 1 ? Theme.yellow : place == 2 ? Color(rgb: 200, 200, 210) : place == 3 ? Color(rgb: 205, 127, 50) : nil
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Text(verbatim: "\(place)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(medal == nil ? Theme.text : Color.black)
                    .frame(width: 32, height: 32)
                    .background(medal ?? Theme.button, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.mine ? L("\(entry.name) (tu)") : entry.name)
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        GPSBadge(source: entry.kind)
                    }
                    carText
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.lap(entry.time))
                        .font(Theme.timeFont(20))
                        .monospacedDigit()
                        .foregroundStyle(place == 1 ? Theme.purple : Theme.text)
                    Text(gap.map { Fmt.delta($0) } ?? Fmt.dayShort.string(from: entry.day))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.sub)
                }
            }
            .padding(12)
            .background(entry.mine ? Theme.accent.opacity(0.08) : Theme.panel, in: shape)
            .overlay(shape.strokeBorder(entry.mine ? Theme.accent.opacity(0.8) : Theme.line.opacity(0.8), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .disabled(!linked)
    }

    @ViewBuilder
    private var carText: some View {
        if entry.vehicle.isEmpty {
            Text(Fmt.dayShort.string(from: entry.day)).font(.caption).foregroundStyle(Theme.sub)
        } else if linked {
            HStack(spacing: 4) {
                Image(systemName: "car.fill").font(.system(size: 10, weight: .bold))
                Text(entry.vehicle).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.accent)
        } else {
            Text(entry.vehicle).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
        }
    }
}

/// Which GPS timed a lap, written out: the precision is not the same.
struct GPSBadge: View {
    let source: SourceKind?

    var body: some View {
        switch source {
        case .device: Badge(text: L("GPS esterno"), color: Theme.good)
        case .phone: Badge(text: L("Telefono"), color: Theme.yellow)
        default: EmptyView()
        }
    }
}
