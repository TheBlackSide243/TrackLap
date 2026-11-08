import SwiftUI

/// Someone's shared sessions, in their garage or on a friend's page: track, day, laps and best,
/// and every lap time when a session is opened. Nothing at all when they share none with you.
struct SharedSessionsSection: View {
    @Environment(AppModel.self) private var model
    let code: String
    @State private var shared: SharedSessions?
    @State private var open: String?
    @State private var all = false

    private static let first = 10

    var body: some View {
        Group {
            if let shared, !shared.sessions.isEmpty {
                let list = all ? shared.sessions : Array(shared.sessions.prefix(Self.first))
                SectionLabel(L("Sessioni"))
                VStack(spacing: 10) {
                    ForEach(list) { s in row(s) }
                    if !all && shared.sessions.count > Self.first {
                        Button { withAnimation(.snappy) { all = true } } label: {
                            Text(L("Mostra tutte (\(shared.sessions.count))"))
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
        .task(id: code) { await load() }
    }

    private func row(_ s: SharedSession) -> some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.track).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.lap(s.best))
                        .font(Theme.timeFont(22))
                        .monospacedDigit()
                        .foregroundStyle(Theme.purple)
                }
                HStack(spacing: 8) {
                    GPSBadge(source: s.source == "device" ? SourceKind.device : SourceKind.phone)
                    Text(Fmt.day.string(from: s.day)).font(.caption).foregroundStyle(Theme.sub)
                    Spacer(minLength: 0)
                    Text(s.laps.count == 1 ? L("1 giro") : L("\(s.laps.count) giri"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.sub)
                    Image(systemName: open == s.id ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.sub)
                }
                Label(s.car ?? s.vehicle.title, systemImage: s.vehicle.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
                if open == s.id { laps(s) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { open = open == s.id ? nil : s.id } }
    }

    private func laps(_ s: SharedSession) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 6) {
            ForEach(Array(s.laps.enumerated()), id: \.offset) { i, t in
                HStack(spacing: 6) {
                    Text(verbatim: "\(i + 1)").font(.caption2.weight(.bold)).foregroundStyle(Theme.sub).frame(minWidth: 18, alignment: .trailing)
                    Text(Fmt.lap(t))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(t == s.best ? Theme.purple : Theme.text)
                }
            }
        }
        .padding(.top, 4)
    }

    private func load() async {
        // Your own garage shows your sessions in the Sessions tab already.
        guard code != model.account.garage else { return }
        shared = try? await Server.sessions(code: code, token: model.account.token)
    }
}
