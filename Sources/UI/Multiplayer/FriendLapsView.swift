import SwiftUI
import UniformTypeIdentifiers

/// The laps friends sent, by track: chase one in Live, or delete it. They come in when a .tracklap
/// file is opened with TrackLap, or from Files with the button at the top.
struct FriendLapsView: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if model.friends.laps.isEmpty {
                    Panel(padding: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: "person.2.fill").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.accent)
                            Text("Ancora nessun giro degli amici").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                            Text("Chiedi a un amico di aprire una sua sessione e toccare Condividi il giro migliore: il file .tracklap che ti manda si apre con TrackLap e finisce qui.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.sub)
                        }
                    }
                }
                ForEach(groups, id: \.track) { g in
                    SectionLabel(g.name)
                    ForEach(g.laps) { f in
                        FriendLapRow(lap: f, chased: model.challenge?.id == f.id) {
                            model.chase(f)
                        }
                        .contextMenu {
                            Button { model.chase(f) } label: { Label("Sfidalo in Live", systemImage: "flag.2.crossed.fill") }
                            Button(role: .destructive) { model.deleteFriendLap(f.id) } label: { Label("Elimina", systemImage: "trash") }
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(L("Giri degli amici"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.trackLap], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                var added = 0
                for url in urls {
                    do {
                        try model.importLap(from: url)
                        added += 1
                    } catch {
                        message = error.localizedDescription
                    }
                }
                if added > 0, message == nil { message = added == 1 ? L("1 giro aggiunto.") : L("\(added) giri aggiunti.") }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    /// By track, the track with the newest lap first; the laps fastest first.
    private var groups: [(track: UUID, name: String, laps: [FriendLap])] {
        var order: [UUID] = []
        for f in model.friends.laps where !order.contains(f.trackID) { order.append(f.trackID) }
        return order.map { id in
            let laps = model.friends.laps(on: id)
            return (id, model.tracks.track(id)?.name ?? laps.first?.trackName ?? "", laps)
        }
    }
}

private struct FriendLapRow: View {
    let lap: FriendLap
    let chased: Bool
    let onChase: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 12) {
            Text(String(lap.driver.prefix(1)).uppercased())
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(width: 38, height: 38)
                .background(chased ? Theme.yellow : Theme.purple, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(lap.driver).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 6) {
                    Badge(text: lap.sourceTitle, color: Theme.sub)
                    if !lap.vehicle.isEmpty { Text(lap.vehicle).font(.caption).foregroundStyle(Theme.sub).lineLimit(1) }
                }
                Text(Fmt.dayShort.string(from: lap.date)).font(.caption2).foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.lap(lap.time))
                    .font(Theme.timeFont(22))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                Button(action: onChase) {
                    Label(chased ? L("In sfida") : L("Sfida"), systemImage: "flag.2.crossed.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(chased ? Color.black : Theme.yellow)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(chased ? Theme.yellow : Theme.yellow.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(chased ? Theme.yellow.opacity(0.06) : Theme.panel, in: shape)
        .overlay(shape.strokeBorder(chased ? Theme.yellow.opacity(0.7) : Theme.line.opacity(0.8), lineWidth: 1))
    }
}
