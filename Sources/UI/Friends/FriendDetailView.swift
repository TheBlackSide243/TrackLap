import SwiftUI

/// A car of a friend's garage to open.
private struct FriendCarRef: Hashable {
    let id: String
}

/// A friend: their numbers, their garage and their best lap on every track, from the online
/// leaderboards.
struct FriendDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let friend: Friend
    @State private var profile: FriendProfile?
    @State private var garage: PublicGarage?
    @State private var garageError: String?
    @State private var error: String?
    @State private var removing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let profile {
                    if let stats = profile.stats, !profile.laps.isEmpty { numbers(stats) }
                    SectionLabel(L("Garage"))
                    garageSection
                    SectionLabel(L("Giri migliori"))
                    laps(profile.laps)
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
        .refreshable { await load() }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(friend.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { removing = true } label: {
                        Label("Togli dagli amici", systemImage: "person.badge.minus")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(L("Altro"))
            }
        }
        .navigationDestination(for: FriendCarRef.self) { ref in
            if let garage, let car = garage.cars.first(where: { $0.id == ref.id }) {
                PublicCarView(info: garage.info(car), code: garage.code, owner: garage.name)
            }
        }
        .confirmationDialog(L("Togliere \(friend.name) dagli amici?"), isPresented: $removing, titleVisibility: .visible) {
            Button(L("Togli dagli amici"), role: .destructive) {
                Task {
                    try? await model.friendList.remove(friend)
                    dismiss()
                }
            }
            Button(L("Annulla"), role: .cancel) {}
        } message: {
            Text("Non vedrete più garage e tempi l'uno dell'altro. Per tornare amici serve un invito nuovo.")
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            FriendAvatar(friend: friend, size: 60)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name).font(.title2.weight(.heavy)).foregroundStyle(Theme.text).lineLimit(1)
                if let since = friend.sinceDate {
                    Text(L("Amici dal \(since.formatted(date: .abbreviated, time: .omitted))"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.sub)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Numbers

    private func numbers(_ s: FriendProfile.Stats) -> some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(title: L("Piste"), value: "\(s.tracks)")
                StatTile(title: L("Sessioni"), value: "\(s.sessions)")
                StatTile(title: L("Primo in classifica"), value: "\(s.wins)", unit: s.wins == 1 ? L("pista") : L("piste"),
                         color: s.wins > 0 ? Theme.purple : Theme.text)
                StatTile(title: L("Ultima volta in pista"),
                         value: s.lastDay.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "–")
            }
            if let favourite = s.favourite {
                Panel(padding: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "heart.fill").foregroundStyle(Theme.accent)
                        Text("Pista preferita").font(.subheadline).foregroundStyle(Theme.sub)
                        Spacer(minLength: 8)
                        Text(favourite).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text).lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Garage

    @ViewBuilder
    private var garageSection: some View {
        if let garage, !garage.cars.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                ForEach(garage.infos) { info in
                    NavigationLink(value: FriendCarRef(id: info.id)) { CarCard(info: info) }
                        .buttonStyle(PressableStyle())
                }
            }
        } else {
            Panel(padding: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "car.side").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.sub)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nessuna auto da vedere").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text(garageError ?? L("\(friend.name) non mostra il garage, oppure non ci ha ancora messo auto."))
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Laps

    @ViewBuilder
    private func laps(_ laps: [FriendProfile.Best]) -> some View {
        if laps.isEmpty {
            Panel(padding: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "stopwatch").font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.sub)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nessun giro in classifica").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("I giri migliori compaiono qui quando li manda nelle classifiche online delle piste.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(laps) { lap in lapRow(lap) }
            }
        }
    }

    private func lapRow(_ lap: FriendProfile.Best) -> some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(lap.track.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Fmt.lap(lap.time))
                        .font(Theme.timeFont(22))
                        .monospacedDigit()
                        .foregroundStyle(lap.rank == 1 ? Theme.purple : Theme.text)
                }
                HStack(spacing: 8) {
                    GPSBadge(source: lap.kind)
                    Text(place(lap)).font(.caption.weight(.semibold)).foregroundStyle(lap.rank == 1 ? Theme.purple : Theme.sub)
                    Spacer(minLength: 0)
                }
                Text(sessions(lap)).font(.caption).foregroundStyle(Theme.sub)
                if !lap.vehicle.isEmpty { vehicle(lap) }
            }
        }
    }

    /// The car of the lap, which opens it when it is in the garage you can see.
    @ViewBuilder
    private func vehicle(_ lap: FriendProfile.Best) -> some View {
        let label = Label(lap.vehicle, systemImage: "car.fill").font(.caption.weight(.semibold))
        if let garage, garage.code == lap.garage, garage.cars.contains(where: { $0.id == lap.car }) {
            NavigationLink(value: FriendCarRef(id: lap.car)) { label.foregroundStyle(Theme.accent) }
        } else {
            label.foregroundStyle(Theme.sub)
        }
    }

    private func place(_ lap: FriendProfile.Best) -> String {
        lap.of == 1 ? L("Unico in classifica") : L("\(lap.rank)° su \(lap.of)")
    }

    private func sessions(_ lap: FriendProfile.Best) -> String {
        let day = lap.lastDay.formatted(date: .abbreviated, time: .omitted)
        return lap.sessions == 1 ? L("1 sessione, il \(day)") : L("\(lap.sessions) sessioni, l'ultima il \(day)")
    }

    private func load() async {
        error = nil
        do {
            let p = try await model.friendList.profile(friend)
            profile = p
            garageError = nil
            if let code = p.garage {
                do {
                    garage = try await Server.garage(code: code, token: model.account.token)
                } catch Server.Failure.notFound {
                    garage = nil
                } catch {
                    garageError = error.localizedDescription
                }
            } else {
                garage = nil
            }
        } catch Server.Failure.notFriend {
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
