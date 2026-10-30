import SwiftUI

/// The online leaderboard of a track: the best lap of every driver who publishes theirs, with the
/// ESP32 (10 Hz) and the iPhone (1 Hz) apart; yours highlighted.
struct LeaderboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let track: Track
    @State private var board: Leaderboard?
    @State private var error: String?
    @State private var kind: SourceKind = .device
    @State private var sending = false
    @State private var note: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("GPS", selection: $kind) {
                        Text(verbatim: "ESP32 · 10 Hz").tag(SourceKind.device)
                        Text(verbatim: "iPhone · 1 Hz").tag(SourceKind.phone)
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
                        rows(board.laps.filter { $0.source == kind.rawValue })
                    } else {
                        ProgressView().tint(Theme.accent).padding(40)
                    }

                    SectionLabel(L("I tuoi giri"))
                    publish
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(track.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fine")) { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.bg)
        .task { await load() }
    }

    @ViewBuilder
    private func rows(_ laps: [Leaderboard.Entry]) -> some View {
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
            let first = laps.first?.time ?? 0
            VStack(spacing: 8) {
                ForEach(laps) { e in
                    BoardRow(entry: e, gap: e.rank == 1 ? nil : e.time - first)
                }
            }
        }
    }

    private var publish: some View {
        let p = model.profile
        return Panel {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(get: { p.publishLaps }, set: { p.setPublish($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pubblica i miei best").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("Il giro migliore di ogni sessione va nella classifica della sua pista, con il tuo nome. Mai i giri della Demo.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Theme.yellow)
                if p.publishLaps || !p.hasName { ProfileFields() }
                if let record = model.sessions.record(on: track.id), SourceKind(sessionSource: record.session.source) != .demo {
                    Button { Task { await send(record) } } label: {
                        if sending { ProgressView() } else {
                            Label(L("Invia il mio record: \(Fmt.lap(record.lap.time))"), systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
                    .disabled(sending || !p.hasName)
                }
                if let note {
                    Text(note).font(.caption.weight(.semibold)).foregroundStyle(Theme.good)
                }
            }
        }
    }

    private func load() async {
        error = nil
        do {
            let length = model.sessions.record(on: track.id)?.lap.distance ?? track.length
            board = try await Server.board(for: track, length: length, driver: model.profile.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send(_ record: SessionLap) async {
        sending = true
        defer { sending = false }
        let kind = SourceKind(sessionSource: record.session.source)
        do {
            let r = try await Server.submit(record.lap, source: kind, track: track, profile: model.profile)
            note = L("Sei \(r.rank)° su \(r.of) con \(kind.short).")
            self.kind = kind
            await load()
        } catch {
            note = nil
            self.error = error.localizedDescription
        }
    }
}

private struct BoardRow: View {
    let entry: Leaderboard.Entry
    let gap: Double?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let medal: Color? = entry.rank == 1 ? Theme.yellow : entry.rank == 2 ? Color(rgb: 200, 200, 210) : entry.rank == 3 ? Color(rgb: 205, 127, 50) : nil
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(medal == nil ? Theme.text : Color.black)
                .frame(width: 32, height: 32)
                .background(medal ?? Theme.button, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.mine ? L("\(entry.name) (tu)") : entry.name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text([entry.vehicle, Fmt.dayShort.string(from: entry.day)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.lap(entry.time))
                    .font(Theme.timeFont(20))
                    .monospacedDigit()
                    .foregroundStyle(entry.rank == 1 ? Theme.purple : Theme.text)
                if let gap {
                    Text(Fmt.delta(gap)).font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.sub)
                }
            }
        }
        .padding(12)
        .background(entry.mine ? Theme.accent.opacity(0.08) : Theme.panel, in: shape)
        .overlay(shape.strokeBorder(entry.mine ? Theme.accent.opacity(0.8) : Theme.line.opacity(0.8), lineWidth: 1))
    }
}
