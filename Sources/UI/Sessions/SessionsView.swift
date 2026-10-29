import SwiftUI

struct SessionsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "chart.bar.xaxis", title: "Sessioni", subtitle: subtitle)
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
        }
    }

    private var subtitle: String {
        let n = model.sessions.summaries.count
        return n == 1 ? "1 sessione" : "\(n) sessioni"
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
                    if live { Badge(text: "In corso", color: Theme.bad) }
                }
                Text(Fmt.day.string(from: summary.date)).font(.caption).foregroundStyle(Theme.sub)
                HStack(spacing: 6) {
                    Badge(text: summary.lapCount == 1 ? "1 giro" : "\(summary.lapCount) giri", color: Theme.accent)
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
