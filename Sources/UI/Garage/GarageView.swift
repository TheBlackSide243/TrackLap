import SwiftUI

/// The Garage tab: your cars with their photos, the one you drive on top, and the switch that shows
/// them to everyone at a link of their own.
struct GarageView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var editing: EditorTarget?
    @State private var signingIn = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "car.fill", title: L("Garage"), subtitle: subtitle) {
                        if !model.garage.cars.isEmpty && !model.garage.isFull {
                            Button { editing = .new } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.accent, in: Circle())
                            }
                            .accessibilityLabel(L("Aggiungi un'auto"))
                        }
                    }

                    if model.garage.cars.isEmpty {
                        EmptyGarage { editing = .new }
                    } else {
                        cars
                    }

                    SectionLabel(L("Garage pubblico"))
                    PublishPanel(signIn: { signingIn = true })
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { CarDetailView(carID: $0) }
            .sheet(item: $editing) { target in
                CarEditorView(car: target.car(in: model.garage)) { saved in
                    if case .new = target, model.garage.cars.count == 1 { model.setActiveCar(saved.id) }
                }
                .environment(model)
            }
            .sheet(isPresented: $signingIn) { AccountSheet().environment(model) }
        }
    }

    @ViewBuilder
    private var cars: some View {
        let active = model.activeCar
        let others = model.garage.cars.filter { $0.id != active?.id }
        if let active {
            NavigationLink(value: active.id) {
                CarHeroCard(info: active.info, badge: L("In uso in Live"))
            }
            .buttonStyle(PressableStyle())
            .contextMenu { menu(for: active) }
        }
        if !others.isEmpty {
            if active != nil { SectionLabel(L("Le altre auto")) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                ForEach(others) { car in
                    NavigationLink(value: car.id) {
                        CarCard(info: car.info)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu { menu(for: car) }
                }
            }
        }
        if model.garage.isFull {
            Text("Il garage ha posto per \(Car.maxCars) auto.")
                .font(.caption)
                .foregroundStyle(Theme.sub)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func menu(for car: Car) -> some View {
        if car.id == model.activeCarID {
            Button { model.setActiveCar(nil) } label: { Label("Non usarla più in Live", systemImage: "car.side") }
        } else {
            Button { model.setActiveCar(car.id) } label: { Label("Usa in Live", systemImage: "steeringwheel") }
        }
        Button { editing = .edit(car.id) } label: { Label("Modifica", systemImage: "pencil") }
        Button { model.garage.move(car.id, by: -1) } label: { Label("Sposta prima", systemImage: "arrow.up") }
        Button { model.garage.move(car.id, by: 1) } label: { Label("Sposta dopo", systemImage: "arrow.down") }
        Button(role: .destructive) { model.deleteCar(car.id) } label: { Label("Elimina", systemImage: "trash") }
    }

    private var subtitle: String {
        let n = model.garage.cars.count
        if n == 0 { return L("Le auto con cui giri in pista") }
        return n == 1 ? L("1 auto") : L("\(n) auto")
    }
}

/// Which car the editor opens on.
enum EditorTarget: Identifiable {
    case new
    case edit(UUID)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let id): id.uuidString
        }
    }

    func car(in garage: GarageStore) -> Car? {
        if case .edit(let id) = self { return garage.car(id) }
        return nil
    }
}

/// Cards shrink a little under the finger.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct EmptyGarage: View {
    let onAdd: () -> Void

    var body: some View {
        Panel(padding: 22, glow: Theme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.12)).frame(width: 64, height: 64)
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
                Text("Il tuo garage è vuoto").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                Text("Aggiungi le auto con cui giri in pista: una foto, i cavalli, il peso e tutte le modifiche. Scegli quella che usi in Live e i tuoi tempi in classifica porteranno a lei.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onAdd) {
                    Label("Aggiungi la prima auto", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
    }
}

/// Showing the garage to everyone: the account it goes under, the switch, the link and how the
/// upload went.
private struct PublishPanel: View {
    @Environment(AppModel.self) private var model
    let signIn: () -> Void

    var body: some View {
        let garage = model.garage
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                if let name = model.account.name {
                    Toggle(isOn: Binding(get: { garage.isPublic }, set: { garage.setPublic($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mostra il garage a tutti").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("Con il nome \(name). Chi ha il link lo vede anche senza l'app, e in classifica i tuoi tempi portano all'auto con cui li hai fatti.")
                                .font(.caption)
                                .foregroundStyle(Theme.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.accent)
                    if garage.isPublic {
                        status
                        if let code = model.account.garage {
                            let url = Server.garageURL(code: code)
                            HStack(spacing: 10) {
                                ShareLink(item: url, subject: Text(L("Il mio garage su TrackLap")),
                                          message: Text(L("Le mie auto da pista, con tutte le modifiche"))) {
                                    Label("Condividi il link", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                Link(destination: url) {
                                    Image(systemName: "safari")
                                        .font(.system(size: 18, weight: .bold))
                                        .frame(width: 52, height: 52)
                                }
                                .foregroundStyle(Theme.accent)
                                .background(Theme.button, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .accessibilityLabel(L("Apri la pagina"))
                            }
                            Text(url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.sub)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fallo vedere a tutti").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Text("Con un account TrackLap il garage ha un link da condividere, e le tue auto compaiono accanto ai tuoi tempi nelle classifiche delle piste.")
                                .font(.caption)
                                .foregroundStyle(Theme.sub)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Button(action: signIn) {
                        Label("Accedi o crea un account", systemImage: "person.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.garage.sync {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Theme.accent)
                Text("Aggiorno il garage online…").font(.caption.weight(.semibold)).foregroundStyle(Theme.sub)
            }
        case .done(let date):
            Label(L("Online, aggiornato alle \(date.formatted(date: .omitted, time: .shortened))"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.good)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.yellow)
                    .fixedSize(horizontal: false, vertical: true)
                Button { model.garage.publishSoon(now: true) } label: { Text("Riprova") }
                    .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
            }
        }
    }
}
