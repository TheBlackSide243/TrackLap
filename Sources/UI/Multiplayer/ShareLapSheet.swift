import SwiftUI

/// Sends a lap to friends as a .tracklap file with your name on it, through WhatsApp, Messages,
/// AirDrop or anything else in the share sheet.
struct ShareLapSheet: View {
    @Environment(AppModel.self) private var model
    let lap: Lap
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Condividi il giro").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            Panel(glow: Theme.purple) {
                HStack(spacing: 14) {
                    AppGlyph(symbol: "flag.checkered", color: Theme.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.trackName).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                        Text(L("Giro \(lap.number)") + " · " + Fmt.dayShort.string(from: session.date))
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 0)
                    Text(Fmt.lap(lap.time))
                        .font(Theme.timeFont(26))
                        .monospacedDigit()
                        .foregroundStyle(Theme.purple)
                }
            }
            ProfileFields()
            if let shared {
                Text("Chi lo riceve lo apre con TrackLap: lo sfida in Live, anche sul cruscotto dell'ESP32, e lo confronta curva per curva nell'analisi.")
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(item: SharedLapFile(shared: shared),
                          preview: SharePreview(model.profile.displayName + " · " + session.trackName + " · " + Fmt.lap(lap.time))) {
                    Label("Invia il giro", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.profile.hasName)
                if !model.profile.hasName {
                    Text("Scrivi il tuo nome: è quello che vedranno gli amici.")
                        .font(.caption)
                        .foregroundStyle(Theme.yellow)
                }
            } else {
                Label("La pista di questa sessione non c'è più: senza la sua linea del via il giro non si può condividere.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.yellow)
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.bg)
    }

    private var shared: SharedLap? {
        guard let track = model.tracks.track(session.trackID), track.isReady else { return nil }
        return SharedLap(driver: model.profile.displayName, vehicle: model.profile.displayVehicle,
                         source: SourceKind(sessionSource: session.source).rawValue, date: lap.startedAt, track: track, lap: lap)
    }
}
