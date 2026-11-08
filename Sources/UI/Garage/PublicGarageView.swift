import SwiftUI

/// Someone's public garage, opened from a leaderboard or from its link: the cars in a grid, and the
/// car of the lap straight away when it came from a leaderboard.
struct PublicGarageView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let link: GarageLink
    @State private var garage: PublicGarage?
    @State private var error: String?
    @State private var path: [String] = []
    @State private var reporting = false
    @State private var thanks = false
    @AppStorage("hiddenGarages") private var hiddenRaw = ""

    private var hidden: Bool { HiddenGarages.contains(link.code, in: hiddenRaw) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    if hidden {
                        hiddenNotice
                    } else if let garage {
                        content(garage)
                    } else if let error {
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.yellow)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button { Task { await load() } } label: { Text("Riprova") }
                                    .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
                            }
                        }
                    } else {
                        ProgressView().tint(Theme.accent).padding(60)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(garage.map { L("Il garage di \($0.name)") } ?? L("Garage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Fine")) { dismiss() }
                }
                if garage != nil && !hidden {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            ShareLink(item: Server.garageURL(code: link.code)) {
                                Label("Condividi il garage", systemImage: "square.and.arrow.up")
                            }
                            if garage?.mine != true {
                                Button(role: .destructive) { reporting = true } label: {
                                    Label("Segnala", systemImage: "exclamationmark.bubble")
                                }
                                Button(role: .destructive) {
                                    hiddenRaw = HiddenGarages.adding(link.code, to: hiddenRaw)
                                } label: {
                                    Label("Nascondi questo garage", systemImage: "eye.slash")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(L("Altro"))
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let garage, let car = garage.cars.first(where: { $0.id == id }) {
                    PublicCarView(info: garage.info(car), code: garage.code, owner: garage.name)
                }
            }
            .reportDialog(isPresented: $reporting, code: link.code, car: nil, thanks: $thanks)
        }
        .presentationBackground(Theme.bg)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ g: PublicGarage) -> some View {
        HStack(spacing: 14) {
            Text(String(g.name.prefix(1)).uppercased())
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.black)
                .frame(width: 56, height: 56)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).font(.title2.weight(.heavy)).foregroundStyle(Theme.text).lineLimit(1)
                Text(g.cars.count == 1 ? L("1 veicolo") : L("\(g.cars.count) veicoli"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
            }
            Spacer(minLength: 0)
        }
        if g.cars.isEmpty {
            Panel(padding: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "car.side").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.sub)
                    Text("Nessun veicolo in questo garage").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                    Text("I veicoli compaiono qui quando il pilota li mostra a tutti.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.sub)
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                ForEach(g.infos) { info in
                    NavigationLink(value: info.id) {
                        CarCard(info: info, badge: info.id == link.car ? L("Questo giro") : nil)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        SharedSessionsSection(code: g.code)
    }

    private var hiddenNotice: some View {
        Panel(padding: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "eye.slash").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.sub)
                Text("Hai nascosto questo garage").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                Text("I suoi veicoli non compaiono più nelle classifiche che apri.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
                Button { hiddenRaw = HiddenGarages.removing(link.code, from: hiddenRaw) } label: {
                    Text("Mostralo di nuovo")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func load() async {
        error = nil
        do {
            let g = try await Server.garage(code: link.code, token: model.account.token)
            garage = g
            if let car = link.car, path.isEmpty, g.cars.contains(where: { $0.id == car }) {
                path = [car]
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Garages you chose not to see, kept as one string of codes (an @AppStorage value).
enum HiddenGarages {
    static func contains(_ code: String, in raw: String) -> Bool {
        raw.split(separator: ",").contains { $0 == code }
    }

    static func adding(_ code: String, to raw: String) -> String {
        contains(code, in: raw) ? raw : (raw.isEmpty ? code : raw + "," + code)
    }

    static func removing(_ code: String, from raw: String) -> String {
        raw.split(separator: ",").filter { $0 != code }.joined(separator: ",")
    }
}
