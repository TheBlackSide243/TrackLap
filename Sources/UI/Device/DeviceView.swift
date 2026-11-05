import SwiftUI
import UIKit
import CoreLocation

struct DeviceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "antenna.radiowaves.left.and.right", title: L("Dispositivo"), subtitle: model.source.title)

                    SectionLabel(L("Sorgente GPS"))
                    VStack(spacing: 10) {
                        ForEach(SourceKind.allCases) { k in
                            SourceCard(kind: k, selected: k == model.source) { model.setSource(k) }
                        }
                    }

                    switch model.source {
                    case .device: BLESection()
                    case .phone: PhoneSection()
                    case .demo: DemoSection()
                    }

                    SectionLabel(L("Cronometro"))
                    SettingsPanel()

                    SectionLabel(L("Account"))
                    AccountPanel()

                    SectionLabel(L("Tu e gli amici"))
                    FriendsPanel()

                    SectionLabel(L("Informazioni"))
                    AboutPanel()
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// A GPS source to pick, also used by the intro.
struct SourceCard: View {
    let kind: SourceKind
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 14) {
            AppGlyph(symbol: kind.icon, size: 44, color: selected ? Theme.accent : Theme.sub)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(.headline).foregroundStyle(Theme.text)
                Text(kind.detail).font(.caption).foregroundStyle(Theme.sub).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? Theme.accent : Theme.line)
        }
        .padding(14)
        .background(selected ? Theme.accent.opacity(0.08) : Theme.panel, in: shape)
        .overlay(shape.strokeBorder(selected ? Theme.accent : Theme.line.opacity(0.8), lineWidth: selected ? 1.5 : 1))
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

private struct BLESection: View {
    @Environment(AppModel.self) private var model
    @State private var editingPins = false

    var body: some View {
        let ble = model.ble
        SectionLabel("ESP32")
        Panel(glow: ble.state == .connected ? Theme.good : nil) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: icon(ble.state))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(ble.state == .connected ? Theme.good : Theme.accent)
                        .symbolEffect(.pulse, isActive: ble.state == .scanning || ble.state == .connecting)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ble.stateTitle).font(.headline).foregroundStyle(Theme.text)
                        Text(ble.stateDetail).font(.caption).foregroundStyle(Theme.sub)
                    }
                    Spacer(minLength: 0)
                }

                if ble.state == .connected {
                    HStack(spacing: 10) {
                        StatTile(title: L("Satelliti"), value: "\(ble.sats)", color: ble.sats >= 8 ? Theme.good : Theme.yellow)
                        StatTile(title: L("Frequenza"), value: "\(ble.rateHz)", unit: "Hz")
                        StatTile(title: L("Firmware"), value: ble.info?.fw ?? "—")
                    }
                    if let info = ble.info {
                        DeviceDetails(info: info) { editingPins = true }
                    }
                    HStack(spacing: 10) {
                        Button {
                            if let t = model.selectedTrack { ble.send(track: t) }
                        } label: {
                            Label("Invia pista", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.selectedTrack?.isReady != true)
                        Button(role: .destructive) { ble.disconnect() } label: {
                            Label("Scollega", systemImage: "xmark")
                        }
                        .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
                    }
                } else {
                    ForEach(ble.devices) { d in
                        Button { ble.connect(d) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "cpu").foregroundStyle(Theme.accent)
                                Text(d.name).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(d.rssi) dBm").font(.caption.monospacedDigit()).foregroundStyle(Theme.sub)
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.line)
                            }
                            .padding(12)
                            .background(Theme.input, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        if ble.state == .scanning { ble.stopScan() } else { ble.scan() }
                    } label: {
                        Label(ble.state == .scanning ? L("Ferma la ricerca") : L("Cerca dispositivi"),
                              systemImage: ble.state == .scanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(ble.state == .off || ble.state == .unauthorized || ble.state == .unsupported)
                }
            }
        }
        .sheet(isPresented: $editingPins) {
            GPSPinsSheet(info: ble.info) { ble.setGPSPins(rx: $0, tx: $1) }
        }
    }

    private func icon(_ s: BLEManager.State) -> String {
        switch s {
        case .connected: return "checkmark.seal.fill"
        case .scanning, .connecting: return "dot.radiowaves.left.and.right"
        case .off, .unauthorized, .unsupported: return "exclamationmark.triangle.fill"
        case .idle: return "cpu"
        }
    }
}

/// The chip, the GPS module and the pins it is wired to, as the ESP32 reports them.
private struct DeviceDetails: View {
    let info: DeviceInfo
    let onPins: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let gps = info.gps {
                if gps.isEmpty {
                    Label("Nessun GPS risponde: controlla i fili e i pin.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.yellow)
                } else {
                    Text("Modulo GPS: \(gps)").font(.caption).foregroundStyle(Theme.sub)
                }
            }
            if let imu = info.imu, !imu.isEmpty {
                Text("Accelerometro: \(imu)").font(.caption).foregroundStyle(Theme.sub)
            }
            if let rx = info.rx, let tx = info.tx {
                Button(action: onPins) {
                    HStack(spacing: 12) {
                        Image(systemName: "cable.connector").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.chip ?? "ESP32").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("GPS su RX \(rx) · TX \(tx)").font(.caption.monospacedDigit()).foregroundStyle(Theme.sub)
                        }
                        Spacer()
                        Text("Cambia pin").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    }
                    .padding(12)
                    .background(Theme.input, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Which GPIOs the GPS is wired to, for boards that use the chip's defaults for something else.
private struct GPSPinsSheet: View {
    let info: DeviceInfo?
    /// nil, nil = the chip's defaults.
    let onSave: (Int?, Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rx = 0
    @State private var tx = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pin del GPS").font(.title3.weight(.bold)).foregroundStyle(Theme.text)
            Text("Il TX del GPS va sul pin RX dell'ESP32, l'RX del GPS sul pin TX. L'ESP32 salva i pin e si riavvia.")
                .font(.caption)
                .foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
            pin(L("RX, dal TX del GPS"), $rx)
            pin(L("TX, verso l'RX del GPS"), $tx)
            Button {
                onSave(rx, tx)
                dismiss()
            } label: {
                Label("Salva e riavvia", systemImage: "arrow.clockwise")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(rx == tx || (rx == info?.rx && tx == info?.tx))
            Button {
                onSave(nil, nil)
                dismiss()
            } label: {
                Text("Pin predefiniti del chip")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium])
        .presentationBackground(Theme.bg)
        .onAppear {
            rx = info?.rx ?? 0
            tx = info?.tx ?? 0
        }
    }

    private func pin(_ title: String, _ value: Binding<Int>) -> some View {
        Stepper(value: value, in: 0...48) {
            HStack {
                Text(title).foregroundStyle(Theme.text)
                Spacer()
                Text(verbatim: "GPIO \(value.wrappedValue)").monospacedDigit().foregroundStyle(Theme.accent)
            }
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PhoneSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phone = model.phone
        SectionLabel("iPhone")
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatTile(title: L("Precisione"), value: phone.accuracy.map { "\(Int($0.rounded()))" } ?? "—", unit: "m")
                    StatTile(title: L("Frequenza"), value: Fmt.hz(model.gpsRate))
                }
                if phone.authorization == .denied || phone.authorization == .restricted {
                    Text("Posizione negata: abilitala in Impostazioni → TrackLap → Posizione.")
                        .font(.caption)
                        .foregroundStyle(Theme.bad)
                } else {
                    Text("Con lo schermo bloccato il GPS continua a registrare durante la sessione.")
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                }
            }
        }
    }
}

private struct DemoSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SectionLabel("Demo")
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Ritmo del pilota").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("\(Int((model.demo.pace * 100).rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                Slider(value: Binding(get: { model.demo.pace }, set: { model.demo.pace = $0 }), in: 0.85...1.05, step: 0.01)
                Text("L'auto segue il tracciato di OpenStreetMap quando forma un anello chiuso; altrimenti gira su un circuito generato che passa dalla tua linea del via.")
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
            }
        }
    }
}

private struct SettingsPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TabbarPlace.key) private var tabbarPlace: TabbarPlace = .auto

    private var currentLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale.current.localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 16) {
                Stepper(value: Binding(get: { model.minLapTime }, set: { model.setMinLapTime($0) }), in: 5...180, step: 5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Giro minimo: \(Int(model.minLapTime)) s").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("Passaggi sul via più ravvicinati vengono ignorati.").font(.caption).foregroundStyle(Theme.sub)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scala della barra del delta").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Picker("Scala", selection: Binding(get: { model.deltaScale }, set: { model.setDeltaScale($0) })) {
                        Text("± 0,5 s").tag(0.5)
                        Text("± 1 s").tag(1.0)
                        Text("± 2 s").tag(2.0)
                        Text("± 5 s").tag(5.0)
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delta rispetto a").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Picker("Delta rispetto a", selection: Binding(get: { model.deltaReference }, set: { model.setDeltaReference($0) })) {
                        ForEach(DeltaReference.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Il record è il giro più veloce delle sessioni precedenti su questa pista.").font(.caption).foregroundStyle(Theme.sub)
                }
                Toggle(isOn: Binding(get: { model.voiceOn }, set: { model.setVoice($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Annuncio vocale").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("A fine giro legge tempo e distacco, nel Drag i tempi principali, abbassando la musica.").font(.caption).foregroundStyle(Theme.sub)
                    }
                }
                .tint(Theme.accent)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unità").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Picker("Unità", selection: Binding(get: { model.units }, set: { model.setUnits($0) })) {
                        ForEach(Units.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Barra delle schede").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                    Picker("Barra delle schede", selection: $tabbarPlace) {
                        ForEach(TabbarPlace.allCases) { Text(verbatim: $0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Automatica: a destra quando lo schermo è più largo che alto, come l'iPhone in orizzontale o il Duo aperto, e nella colonna dell'ora del Duo chiuso.").font(.caption).foregroundStyle(Theme.sub)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lingua").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("Si cambia nelle Impostazioni di iOS, alla voce TrackLap.").font(.caption).foregroundStyle(Theme.sub)
                        }
                        Spacer()
                        Text(verbatim: currentLanguage).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Your name and vehicle for the laps you share, the live group and the leaderboards.
private struct FriendsPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.profile
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                ProfileFields()
                Toggle(isOn: Binding(get: { p.publishLaps }, set: { p.setPublish($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pubblica i miei best").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("Il giro migliore di ogni sessione va nella classifica online della sua pista, con il nome del tuo account e l'auto in uso. Mai i giri della Demo.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                    }
                }
                .tint(Theme.accent)
                .disabled(!model.account.isSignedIn)
                if !model.account.isSignedIn {
                    Text("Per pubblicare i tempi serve un account: lo crei qui sopra.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.yellow)
                }
                Text("I gruppi live, le classifiche e il garage pubblico passano dal server di TrackLap: riceve il nome, l'auto, i tempi, le auto che mostri con le loro foto e, solo mentre sei in un gruppo, la posizione in pista.")
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
            }
        }
    }
}

private struct AboutPanel: View {
    @AppStorage("introSeen") private var introSeen = false

    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                row(L("Versione"), version)
                row(L("Protocollo BLE"), "TrackLap v1")
                row(L("Mappe e piste"), "© OpenStreetMap")
                Text("Il cronometraggio interpola il passaggio sulla linea tra due fix GPS: a 10 Hz la precisione è di qualche centesimo.")
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
                    .padding(.top, 4)
                Button { introSeen = false } label: {
                    Label("Rivedi l'introduzione", systemImage: "sparkles")
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 6)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.subheadline).foregroundStyle(Theme.sub)
            Spacer()
            Text(v).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
        }
    }
}
