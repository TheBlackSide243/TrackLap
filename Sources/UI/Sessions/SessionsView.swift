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
                    FriendsRow(count: model.friends.laps.count) { showFriends = true }
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
                if let car = summary.carName, !car.isEmpty {
                    Label(car, systemImage: "car.fill")
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
