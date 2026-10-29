import SwiftUI
import CoreLocation

struct DeviceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "antenna.radiowaves.left.and.right", title: "Dispositivo", subtitle: model.source.title)

                    SectionLabel("Sorgente GPS")
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

                    SectionLabel("Cronometro")
                    SettingsPanel()

                    SectionLabel("Informazioni")
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

private struct SourceCard: View {
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
                        StatTile(title: "Satelliti", value: "\(ble.sats)", color: ble.sats >= 8 ? Theme.good : Theme.yellow)
                        StatTile(title: "Frequenza", value: "\(ble.rateHz)", unit: "Hz")
                        StatTile(title: "Firmware", value: ble.info?.fw ?? "—")
                    }
                    if let gps = ble.info?.gps {
                        Text("Modulo GPS: \(gps)").font(.caption).foregroundStyle(Theme.sub)
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
                        Label(ble.state == .scanning ? "Ferma la ricerca" : "Cerca dispositivi",
                              systemImage: ble.state == .scanning ? "stop.fill" : "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(ble.state == .off || ble.state == .unauthorized || ble.state == .unsupported)
                }
            }
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

private struct PhoneSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let phone = model.phone
        SectionLabel("iPhone")
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    StatTile(title: "Precisione", value: phone.accuracy.map { "\(Int($0.rounded()))" } ?? "—", unit: "m")
                    StatTile(title: "Frequenza", value: Fmt.hz(model.gpsRate))
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
            }
        }
    }
}

private struct AboutPanel: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                row("Versione", version)
                row("Protocollo BLE", "TrackLap v1")
                row("Mappe e piste", "© OpenStreetMap")
                Text("Il cronometraggio interpola il passaggio sulla linea tra due fix GPS: a 10 Hz la precisione è di qualche centesimo.")
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
                    .padding(.top, 4)
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
