import SwiftUI

/// Live: the standings of the live group, or the way into one, and the online leaderboard of the track.
struct MultiplayerCard: View {
    @Environment(AppModel.self) private var model
    @State private var sheet: GroupSheet.Mode?
    @State private var leaderboard: Track?

    var body: some View {
        VStack(spacing: 10) {
            if model.group.isOn {
                GroupBoard { sheet = .info }
            } else {
                entry
            }
            if let track = model.selectedTrack, track.isReady {
                Button { leaderboard = track } label: {
                    Label("Classifica online", systemImage: "trophy.fill")
                }
                .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
            }
        }
        .sheet(item: $sheet) { GroupSheet(mode: $0) }
        .sheet(item: $leaderboard) { LeaderboardView(track: $0) }
    }

    private var entry: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AppGlyph(symbol: "person.3.fill", color: Theme.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gruppo live").font(.headline).foregroundStyle(Theme.text)
                        Text("Tempi, distacchi e posizioni degli amici in pista, in diretta.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let problem = model.group.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.yellow)
                }
                HStack(spacing: 10) {
                    Button { sheet = .create } label: { Label("Crea", systemImage: "plus") }
                        .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
                    Button { sheet = .join } label: { Label("Entra", systemImage: "person.badge.plus") }
                        .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
                }
            }
        }
    }
}

/// The group on your track: best lap, last lap and gap to the leader of everyone, your place, and the
/// cars just ahead and behind on the track with how many seconds apart you are.
private struct GroupBoard: View {
    @Environment(AppModel.self) private var model
    let onInfo: () -> Void

    var body: some View {
        let group = model.group
        Panel(glow: Theme.yellow) {
            // Once a second: rows light up after a lap, the gaps on track move on.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.3.fill").font(.caption.weight(.bold)).foregroundStyle(Theme.yellow)
                        Text(L("GRUPPO"))
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.yellow)
                        Text(verbatim: group.code ?? "")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Theme.text)
                        StatusDot(status: group.status)
                        Spacer(minLength: 0)
                        Button(action: onInfo) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Theme.yellow)
                                .frame(width: 36, height: 36)
                                .background(Theme.button, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    let rows = group.standings
                    let leader = rows.first?.best
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        StandingRow(position: row.best == nil ? nil : i + 1, row: row, leader: leader, now: ctx.date)
                    }
                    if rows.count == 1 {
                        Text("Nessun altro qui per ora: invita gli amici con il QR.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                    }
                    if !group.elsewhere.isEmpty {
                        Text(L("Su un'altra pista: \(group.elsewhere.map(\.name).joined(separator: ", "))"))
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                    }
                    gaps
                }
            }
        }
    }

    @ViewBuilder
    private var gaps: some View {
        let length = model.engine.referenceLap?.distance ?? model.selectedTrack?.length ?? 0
        let g = model.group.trackGaps(lapLength: length)
        if g.ahead != nil || g.behind != nil {
            HStack(spacing: 8) {
                if let a = g.ahead {
                    chip("arrow.up", L("\(a.name) davanti di \(String(format: "%.1f", a.seconds)) s"), GroupColors.color(a.color))
                }
                if let b = g.behind {
                    chip("arrow.down", L("\(b.name) dietro di \(String(format: "%.1f", b.seconds)) s"), GroupColors.color(b.color))
                }
            }
        }
    }

    private func chip(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.caption2.weight(.heavy))
            Text(text).font(.caption.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
    }
}

private struct StatusDot: View {
    let status: GroupSession.Status

    var body: some View {
        let color: Color = status == .live ? Theme.good : status == .connecting ? Theme.yellow : Theme.bad
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .shadow(color: color.opacity(0.8), radius: 4)
            .accessibilityLabel(status == .live ? L("Collegato") : L("Collegamento…"))
    }
}

private struct StandingRow: View {
    let position: Int?
    let row: Standing
    let leader: Double?
    let now: Date

    var body: some View {
        let color = GroupColors.color(row.color)
        let flash = row.lapAt.map { now.timeIntervalSince($0) < 4 } ?? false
        HStack(spacing: 10) {
            Text(position.map { "\($0)" } ?? "–")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(position == 1 ? Color.black : Theme.text)
                .frame(width: 26, height: 26)
                .background(position == 1 ? Theme.yellow : Theme.button, in: Circle())
            Circle().fill(color).frame(width: 9, height: 9).opacity(row.online ? 1 : 0.3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(row.isMe ? L("\(row.name) (tu)") : row.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(row.online ? Theme.text : Theme.sub)
                        .lineLimit(1)
                    if row.moving {
                        Image(systemName: "location.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.good)
                    }
                }
                Text(detail).font(.caption2).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.lap(row.best))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(position == 1 ? Theme.purple : Theme.text)
                Text(gap)
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(position == 1 || position == nil ? Theme.sub : Theme.bad)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(flash ? color.opacity(0.2) : row.isMe ? Theme.accent.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeOut(duration: 0.4), value: flash)
    }

    private var detail: String {
        var parts: [String] = []
        if !row.vehicle.isEmpty { parts.append(row.vehicle) }
        if let last = row.last { parts.append(L("ultimo \(Fmt.lap(last))")) }
        if !row.online { parts.append(L("non in linea")) }
        return parts.isEmpty ? L("ancora nessun giro") : parts.joined(separator: " · ")
    }

    private var gap: String {
        guard let best = row.best else { return "" }
        if position == 1 || leader == nil { return row.laps == 1 ? L("1 giro") : L("\(row.laps) giri") }
        return Fmt.delta(best - (leader ?? best))
    }
}

/// Making a group, joining one, and the code with its QR for the others.
struct GroupSheet: View {
    enum Mode: String, Identifiable {
        case create, join, info

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    init(mode: Mode) {
        _mode = State(initialValue: mode)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if mode == .info { info } else { setup }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationBackground(Theme.bg)
        .onDisappear { model.group.profileChanged() }
    }

    @ViewBuilder
    private var setup: some View {
        Text(mode == .create ? L("Nuovo gruppo") : L("Entra in un gruppo"))
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.text)
        Text(mode == .create
             ? L("Gli amici entrano con il codice o inquadrando il QR: ognuno vede tempi, distacchi e posizione degli altri sulla mappa.")
             : L("Scrivi il codice di cinque caratteri di chi ha creato il gruppo, oppure inquadra il suo QR con la Fotocamera."))
            .font(.subheadline)
            .foregroundStyle(Theme.sub)
            .fixedSize(horizontal: false, vertical: true)
        ProfileFields()
        if mode == .join {
            TextField(L("Codice"), text: Binding(get: { code }, set: { code = GroupSession.clean($0) }))
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.text)
                .padding(14)
                .background(Theme.input, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.yellow)
        }
        if !model.profile.hasName {
            Text("Scrivi il tuo nome: è quello che vedranno gli amici.").font(.caption).foregroundStyle(Theme.yellow)
        }
        Button(action: go) {
            if busy { ProgressView().tint(.black) } else {
                Label(mode == .create ? L("Crea il gruppo") : L("Entra"), systemImage: mode == .create ? "plus" : "arrow.right")
            }
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.yellow))
        .disabled(busy || !model.profile.hasName || (mode == .join && code.count != 5))
        Text("In pista serve la connessione dati. I tempi li calcola sempre il tuo telefono: la rete serve solo a mandarli agli altri.")
            .font(.caption)
            .foregroundStyle(Theme.sub)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func go() {
        error = nil
        if mode == .join {
            model.group.join(code, on: model.selectedTrack)
            mode = .info
            return
        }
        busy = true
        Task {
            do {
                try await model.group.create(on: model.selectedTrack)
                mode = .info
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }

    @ViewBuilder
    private var info: some View {
        let group = model.group
        if let code = group.code {
            HStack {
                Text("Gruppo live").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
                Spacer()
                StatusDot(status: group.status)
                Text(group.status == .live ? L("Collegato") : L("Collegamento…"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.sub)
            }
            Text(verbatim: code)
                .font(.system(size: 46, weight: .heavy, design: .monospaced))
                .tracking(6)
                .foregroundStyle(Theme.yellow)
                .frame(maxWidth: .infinity)
                .textSelection(.enabled)
            QRCodeView(text: GroupSession.inviteURL(code).absoluteString)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)
            Text("Gli amici inquadrano il QR con la Fotocamera dell'iPhone, oppure aprono TrackLap e scrivono il codice.")
                .font(.caption)
                .foregroundStyle(Theme.sub)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            ShareLink(item: GroupSession.inviteURL(code), message: Text(L("Entra nel mio gruppo TrackLap, codice \(code)"))) {
                Label("Invita", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle(color: Theme.yellow))
            Button(role: .destructive) {
                group.leave()
                dismiss()
            } label: {
                Label("Esci dal gruppo", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
        } else {
            Text("Gruppo live").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            Label(group.problem ?? L("Non sei in nessun gruppo."), systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Theme.yellow)
            Button { mode = .join } label: { Text("Riprova") }
                .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
        }
    }
}
