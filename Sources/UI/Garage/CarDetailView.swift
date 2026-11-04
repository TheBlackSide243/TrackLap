import SwiftUI
import UIKit

/// One of your cars: its page, whether you drive it in Live, your best times with it on each track,
/// and its link when the garage is public.
struct CarDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let carID: UUID
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var newSetup = false

    var body: some View {
        if let car = model.garage.car(carID) {
            let active = car.id == model.activeCarID
            CarDetailContent(info: car.info, badge: active ? L("In uso in Live") : nil) {
                drive(car, active: active)
                setups(car)
                times(car)
                drags(car)
                share(car)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = true } label: { Label("Modifica", systemImage: "pencil") }
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                    .accessibilityLabel(L("Altro"))
                }
            }
            .sheet(isPresented: $editing) {
                CarEditorView(car: car).environment(model)
            }
            .sheet(isPresented: $newSetup) {
                SetupEditorView(setup: nil, carID: car.id).environment(model)
            }
            .navigationDestination(for: SetupRef.self) { SetupDetailView(setupID: $0.id) }
            .confirmationDialog(L("Eliminare \(car.displayName)?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Elimina l'auto"), role: .destructive) {
                    dismiss()
                    model.deleteCar(car.id)
                }
            } message: {
                Text("Le sessioni restano, senza il collegamento all'auto.")
            }
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    @ViewBuilder
    private func drive(_ car: Car, active: Bool) -> some View {
        if active {
            Panel {
                HStack(spacing: 12) {
                    Image(systemName: "steeringwheel")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("La stai usando in Live").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("Le prossime sessioni e i tempi in classifica sono con quest'auto.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            Button { withAnimation { model.setActiveCar(car.id) } } label: {
                Label("Usa quest'auto in Live", systemImage: "steeringwheel")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    /// The car's setups, each kept apart: the one for the wet stays when you make one for the dry.
    @ViewBuilder
    private func setups(_ car: Car) -> some View {
        let list = model.garage.setups(of: car.id)
        HStack {
            SectionLabel(list.isEmpty ? L("Assetti") : L("Assetti (\(list.count))"))
            Button { newSetup = true } label: {
                Label("Nuovo", systemImage: "plus").font(.caption.weight(.bold))
            }
            .foregroundStyle(Theme.accent)
        }
        if list.isEmpty {
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Salva qui i tuoi assetti", systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("Uno per il bagnato, uno per l'asciutto, uno per pista: pressioni, campanature, ammortizzatori e tutto il resto. Ogni modifica tiene la versione di prima, e ogni sessione si ricorda l'assetto con cui l'hai fatta. Restano solo sul telefono.")
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(spacing: 8) {
                ForEach(list) { s in
                    NavigationLink(value: SetupRef(id: s.id)) { SetupRow(setup: s) }
                        .buttonStyle(PressableStyle())
                }
            }
        }
    }

    /// The best lap with this car on each track, from your sessions.
    @ViewBuilder
    private func times(_ car: Car) -> some View {
        let best = Dictionary(grouping: model.sessions.summaries.filter { $0.carID == car.id && $0.best != nil }) { $0.trackName }
            .compactMap { _, list in list.min { ($0.best ?? .infinity) < ($1.best ?? .infinity) } }
            .sorted { $0.date > $1.date }
        if !best.isEmpty {
            SectionLabel(L("I tuoi migliori tempi con quest'auto"))
            VStack(spacing: 8) {
                ForEach(best) { s in
                    let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                    HStack(spacing: 12) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.purple)
                            .frame(width: 32, height: 32)
                            .background(Theme.purple.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.trackName).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                            Text([Fmt.dayShort.string(from: s.date), SourceKind(sessionSource: s.source).short].joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 0)
                        Text(Fmt.lap(s.best))
                            .font(Theme.timeFont(20))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                    }
                    .padding(12)
                    .background(Theme.panel, in: shape)
                    .overlay(shape.strokeBorder(Theme.line.opacity(0.8), lineWidth: 1))
                }
            }
        }
    }

    /// The best of every drag measure done with this car.
    @ViewBuilder
    private func drags(_ car: Car) -> some View {
        let records = model.drags.records(car: car.id)
        let measures = DragMeasure.all().filter { records[$0.name] != nil }
        if !measures.isEmpty {
            SectionLabel(L("I tuoi migliori Drag con quest'auto"))
            Panel(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(measures.enumerated()), id: \.element.id) { i, m in
                        if let r = records[m.name] {
                            if i > 0 { Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.horizontal, 10) }
                            HStack(spacing: 10) {
                                Image(systemName: m.kind == .braking ? "arrow.down.to.line" : m.kind == .distance ? "flag.checkered" : "speedometer")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 22)
                                Text(verbatim: m.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Theme.text)
                                Text(Fmt.dayShort.string(from: r.run.date))
                                    .font(.caption)
                                    .foregroundStyle(Theme.sub)
                                Spacer(minLength: 0)
                                Text(r.result.kind == .braking ? "\(Fmt.shortDistance(r.result.distance)) \(Fmt.shortDistanceUnit)"
                                     : "\(Fmt.dragTime(r.result.time)) s")
                                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.purple)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func share(_ car: Car) -> some View {
        if model.garage.isPublic, let code = model.account.garage {
            ShareLink(item: Server.garageURL(code: code, car: car.id.uuidString),
                      subject: Text(car.displayName),
                      message: Text(L("\(car.displayName) nel mio garage su TrackLap"))) {
                Label("Condividi quest'auto", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

/// A car of someone else's garage, opened from its page or from a leaderboard.
struct PublicCarView: View {
    let info: CarInfo
    let code: String
    let owner: String
    @State private var reporting = false
    @State private var thanks = false

    var body: some View {
        CarDetailContent(info: info) {
            Label(L("Dal garage di \(owner)"), systemImage: "person.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.sub)
                .frame(maxWidth: .infinity, alignment: .leading)
            ShareLink(item: Server.garageURL(code: code, car: info.id), subject: Text(info.name)) {
                Label("Condividi quest'auto", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { reporting = true } label: { Label("Segnala", systemImage: "exclamationmark.bubble") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                }
                .accessibilityLabel(L("Altro"))
            }
        }
        .reportDialog(isPresented: $reporting, code: code, car: info.id, thanks: $thanks)
    }
}

extension View {
    /// Reasons to report a garage or one of its cars, and a thank-you once it is sent.
    func reportDialog(isPresented: Binding<Bool>, code: String, car: String?, thanks: Binding<Bool>) -> some View {
        confirmationDialog(L("Perché lo segnali?"), isPresented: isPresented, titleVisibility: .visible) {
            ForEach([L("Foto inadatta"), L("Testo offensivo"), L("Non è la sua auto"), L("Spam")], id: \.self) { reason in
                Button(reason) {
                    Task {
                        try? await Server.report(code: code, car: car, reason: reason)
                        thanks.wrappedValue = true
                    }
                }
            }
        } message: {
            Text("La segnalazione arriva a chi gestisce TrackLap. Con più segnalazioni il garage viene nascosto finché non viene controllato.")
        }
        .alert(L("Grazie della segnalazione"), isPresented: thanks) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La controlliamo il prima possibile.")
        }
    }
}
