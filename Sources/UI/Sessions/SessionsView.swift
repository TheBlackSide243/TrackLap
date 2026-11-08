import SwiftUI

struct SessionsView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var showFriends = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "chart.bar.xaxis", title: L("Sessioni"), subtitle: subtitle)
                    if Edition.online {
                        FriendsRow(count: model.friends.laps.count) { showFriends = true }
                        SharingPanel()
                    }
                    if model.sessions.summaries.isEmpty {
                        Panel(padding: 24) {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "stopwatch").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.accent)
                                Text("Ancora nessuna sessione").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                                Text("Avvia una sessione dalla scheda Live: ogni giro viene salvato qui, con tempi, settori, velocità e tracciato.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.sub)
                            }
                        }
                    }
                    ForEach(model.sessions.summaries) { s in
                        NavigationLink(value: s.id) {
                            SessionCard(summary: s, live: s.id == model.currentSessionID)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { model.sessions.delete(s.id) } label: {
                                Label("Elimina sessione", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { SessionDetailView(sessionID: $0) }
            .navigationDestination(isPresented: $showFriends) { FriendLapsView() }
            .onAppear {
                if Showcase.screen == .friends { showFriends = true }
                if Showcase.screen == .session || Showcase.screen == .analysis || Showcase.screen == .share, path.isEmpty,
                   let latest = model.sessions.summaries.first {
                    path = [latest.id]
                }
            }
        }
    }

    private var subtitle: String {
        let n = model.sessions.summaries.count
        return n == 1 ? L("1 sessione") : L("\(n) sessioni")
    }
}

/// The way to the laps friends sent.
private struct FriendsRow: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Button(action: onTap) {
            HStack(spacing: 14) {
                AppGlyph(symbol: "person.2.fill", size: 44, color: Theme.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Giri degli amici").font(.headline).foregroundStyle(Theme.text)
                    Text(count == 0 ? L("Apri con TrackLap i file .tracklap che ti mandano")
                         : count == 1 ? L("1 giro da sfidare") : L("\(count) giri da sfidare"))
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.line)
            }
            .padding(14)
            .background(Theme.panel, in: shape)
            .overlay(shape.strokeBorder(Theme.line.opacity(0.8), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Who sees your sessions in your garage: nobody, your friends or everyone, like the garage.
private struct SharingPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let shared = model.sharedSessions
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.wave.2.fill").foregroundStyle(Theme.accent)
                    Text("Condivisione").font(.headline).foregroundStyle(Theme.text)
                    Spacer(minLength: 0)
                    if case .syncing = shared.sync { ProgressView().controlSize(.small) }
                }
                if model.account.isSignedIn {
                    Picker(L("Chi vede le sessioni"), selection: Binding(get: { shared.audience }, set: { shared.setAudience($0) })) {
                        ForEach(SessionAudience.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(shared.audience.summary)
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .failed(let message) = shared.sync {
                        Text(message).font(.caption.weight(.semibold)).foregroundStyle(Theme.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Accedi al tuo account in Dispositivo per mostrare le sessioni a tutti o solo agli amici.")
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct SessionCard: View {
    let summary: SessionSummary
    let live: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(summary.trackName).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    if live { Badge(text: L("In corso"), color: Theme.bad) }
                }
                Text(Fmt.day.string(from: summary.date)).font(.caption).foregroundStyle(Theme.sub)
                if let layout = summary.layoutName {
                    Label(layout, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.sub)
                        .lineLimit(1)
                }
                if let car = summary.carName, !car.isEmpty {
                    Label(car, systemImage: summary.vehicle.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Badge(text: summary.lapCount == 1 ? L("1 giro") : L("\(summary.lapCount) giri"), color: Theme.accent)
                    Badge(text: summary.source, color: Theme.sub)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("BEST").font(.system(size: 10, weight: .heavy)).tracking(1).foregroundStyle(Theme.sub)
                Text(Fmt.lap(summary.best))
                    .font(Theme.timeFont(24))
                    .monospacedDigit()
                    .foregroundStyle(Theme.purple)
                if let ideal = summary.ideal {
                    Text("ideale \(Fmt.lap(ideal))").font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.sub)
                }
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.line)
        }
        .padding(16)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(live ? Theme.bad.opacity(0.6) : Theme.line.opacity(0.8), lineWidth: 1))
    }
}
