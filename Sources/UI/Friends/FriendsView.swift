import SwiftUI
import UIKit

/// The Friends tab: the drivers you are friends with, and your invitation link. Whoever opens the
/// link in TrackLap becomes your friend, and you theirs; friends see each other's garage (also one
/// shown to friends only), their best lap on every track and a few numbers. Setups never go online.
struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var signingIn = false
    @State private var removing: Friend?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "person.2.fill", title: L("Amici"), subtitle: subtitle)
                    if model.account.isSignedIn {
                        InvitePanel()
                        SectionLabel(L("I tuoi amici"))
                        list
                    } else {
                        signedOut
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.friendList.refresh() }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Friend.self) { FriendDetailView(friend: $0) }
            .sheet(isPresented: $signingIn) { AccountSheet().environment(model) }
            .confirmationDialog(L("Togliere \(removing?.name ?? "") dagli amici?"),
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible, presenting: removing) { friend in
                Button(L("Togli dagli amici"), role: .destructive) {
                    Task { try? await model.friendList.remove(friend) }
                }
                Button(L("Annulla"), role: .cancel) {}
            } message: { _ in
                Text("Non vedrete più garage e tempi l'uno dell'altro. Per tornare amici serve un invito nuovo.")
            }
        }
        .task(id: model.account.name) { await model.friendList.refresh() }
        .onChange(of: model.tab) { _, tab in
            if tab == .friends { Task { await model.friendList.refresh() } }
        }
        // A friend added from an invitation link: back to the list, where they are now.
        .onChange(of: model.friendList.friends.count) { path = NavigationPath() }
    }

    private var subtitle: String {
        guard model.account.isSignedIn else { return L("Garage e tempi dei tuoi amici") }
        let n = model.friendList.friends.count
        return n == 0 ? L("Ancora nessun amico") : n == 1 ? L("1 amico") : L("\(n) amici")
    }

    @ViewBuilder
    private var list: some View {
        let store = model.friendList
        if store.friends.isEmpty {
            switch store.state {
            case .idle, .loading:
                ProgressView().tint(Theme.accent).padding(40)
            case .failed(let message):
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { Task { await store.refresh() } } label: { Text("Riprova") }
                            .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
                    }
                }
            case .loaded:
                Panel(padding: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "person.2").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.sub)
                        Text("Ancora nessun amico").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                        Text("Manda il tuo invito: chi lo apre in TrackLap diventa tuo amico, e tu suo.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(store.friends) { friend in
                    NavigationLink(value: friend) { FriendRow(friend: friend) }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button(role: .destructive) { removing = friend } label: {
                                Label("Togli dagli amici", systemImage: "person.badge.minus")
                            }
                        }
                }
            }
            if case .failed(let message) = store.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var signedOut: some View {
        Panel(padding: 22) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "person.2.fill").font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.accent)
                Text("Garage e tempi dei tuoi amici").font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                Text("Con un account TrackLap mandi un invito ai tuoi amici: quando lo aprono vedete i garage, i giri migliori su ogni pista e le statistiche l'uno dell'altro.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
                    .fixedSize(horizontal: false, vertical: true)
                Button { signingIn = true } label: {
                    Label("Accedi o crea un account", systemImage: "person.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }
}

/// A friend in the list: the initial, the name and since when.
private struct FriendRow: View {
    let friend: Friend

    var body: some View {
        Panel(padding: 12) {
            HStack(spacing: 12) {
                FriendAvatar(friend: friend, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    if let since = friend.sinceDate {
                        Text(L("Amici dal \(since.formatted(date: .abbreviated, time: .omitted))"))
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.sub)
            }
        }
    }
}

/// The initial of a friend's name in a circle.
struct FriendAvatar: View {
    let friend: Friend
    var size: CGFloat = 46

    var body: some View {
        Text(friend.initial)
            .font(.system(size: size * 0.43, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.black)
            .frame(width: size, height: size)
            .background(Theme.accent, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Your invitation link, to send to a friend however you like.
private struct InvitePanel: View {
    @Environment(AppModel.self) private var model
    @State private var url: URL?
    @State private var error: String?
    @State private var busy = false
    @State private var renewing = false

    var body: some View {
        Panel(glow: Theme.accent) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Invita un amico").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        Text("Mandagli il tuo link: quando lo apre in TrackLap diventate amici. Il link vale una settimana e funziona per più amici.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let url {
                    ShareLink(item: url, subject: Text(L("Diventiamo amici su TrackLap")),
                              message: Text(L("Apri il link per diventare mio amico su TrackLap: vedrai il mio garage e i miei tempi."))) {
                        Label("Manda l'invito", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button { renewing = true } label: {
                        Text("Fai un link nuovo").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.sub)
                    .disabled(busy)
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { Task { await load() } } label: { Text("Riprova") }
                        .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
                } else {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: model.account.name) { await load() }
        .confirmationDialog(L("Fare un link nuovo?"), isPresented: $renewing, titleVisibility: .visible) {
            Button(L("Fai un link nuovo")) { Task { await load(renew: true) } }
            Button(L("Annulla"), role: .cancel) {}
        } message: {
            Text("Il link che hai già mandato smette di funzionare. Gli amici che hai già restano.")
        }
    }

    private func load(renew: Bool = false) async {
        guard model.account.isSignedIn else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            url = try await model.friendList.inviteURL(renew: renew)
        } catch {
            if url == nil { self.error = error.localizedDescription }
        }
    }
}
