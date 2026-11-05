import SwiftUI
import UIKit

/// A friend invitation opened from its link (tracklap://friend/<code>): who it is from, and the
/// button that makes you friends. Signed out, you sign in or make an account first, then accept.
struct FriendInviteSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let code: String
    @State private var name: String?
    @State private var error: String?
    @State private var busy = false
    @State private var signingIn = false

    private var isMine: Bool {
        guard let name, let me = model.account.name else { return false }
        return name.caseInsensitiveCompare(me) == .orderedSame
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let name {
                        invitation(from: name)
                    } else if let error {
                        failure(error)
                    } else {
                        ProgressView().tint(Theme.accent).padding(60)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Non ora")) { dismiss() }
                }
            }
            .sheet(isPresented: $signingIn) { AccountSheet().environment(model) }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.bg)
        .task { await load() }
    }

    @ViewBuilder
    private func invitation(from name: String) -> some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: 30, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.black)
            .frame(width: 72, height: 72)
            .background(Theme.accent, in: Circle())
        Text(L("\(name) ti invita su TrackLap"))
            .font(.title2.weight(.heavy))
            .foregroundStyle(Theme.text)
            .multilineTextAlignment(.center)
        Text("Diventate amici: vedrete i vostri garage, i giri migliori su ogni pista e le statistiche.")
            .font(.subheadline)
            .foregroundStyle(Theme.sub)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.yellow)
                .fixedSize(horizontal: false, vertical: true)
        }
        if !model.account.isSignedIn {
            Text("Serve un account TrackLap: accedi o creane uno, poi accetti.")
                .font(.caption)
                .foregroundStyle(Theme.sub)
                .multilineTextAlignment(.center)
            Button { signingIn = true } label: {
                Label("Accedi o crea un account", systemImage: "person.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        } else if isMine {
            Text("È il tuo invito: mandalo a un amico.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.yellow)
                .multilineTextAlignment(.center)
        } else {
            Button(action: accept) {
                if busy {
                    ProgressView().tint(.black)
                } else {
                    Label("Accetta", systemImage: "person.badge.plus")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(busy)
        }
    }

    private func failure(_ message: String) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.yellow)
                    .fixedSize(horizontal: false, vertical: true)
                Button { Task { await load() } } label: { Text("Riprova") }
                    .buttonStyle(SecondaryButtonStyle(color: Theme.yellow))
            }
        }
    }

    private func load() async {
        error = nil
        do {
            name = try await Server.inviter(code: code)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func accept() {
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await model.friendList.accept(code)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                model.tab = .friends
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
