import SwiftUI
import UIKit

/// Signing in, or making an account: a name everyone sees and a password.
struct AccountSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var name = ""
    @State private var password = ""
    @State private var repeated = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case name, password, repeated }

    private var nameOK: Bool { Server.isValidName(name.trimmingCharacters(in: .whitespaces)) }
    private var canSend: Bool {
        guard !busy, !name.isEmpty, !password.isEmpty else { return false }
        return !creating || (nameOK && password.count >= 8 && password == repeated)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        AppGlyph(symbol: "person.crop.circle.fill", size: 64)
                        Text(creating ? L("Crea il tuo account") : L("Accedi a TrackLap"))
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text("Per mostrare il garage a tutti e mettere i tuoi tempi nelle classifiche delle piste, con l'auto con cui li hai fatti.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.sub)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)

                    Picker("", selection: $creating.animation(.easeInOut(duration: 0.2))) {
                        Text("Accedi").tag(false)
                        Text("Nuovo account").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Panel(padding: 6) {
                        VStack(spacing: 0) {
                            field(icon: "person.fill") {
                                TextField(L("Nome utente"), text: $name)
                                    .textContentType(.username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focus, equals: .name)
                                    .submitLabel(.next)
                                    .onSubmit { focus = .password }
                            }
                            divider
                            field(icon: "lock.fill") {
                                SecureField(L("Password"), text: $password)
                                    .textContentType(creating ? UITextContentType.newPassword : UITextContentType.password)
                                    .focused($focus, equals: .password)
                                    .submitLabel(creating ? SubmitLabel.next : SubmitLabel.go)
                                    .onSubmit { if creating { focus = .repeated } else { send() } }
                            }
                            if creating {
                                divider
                                field(icon: "lock.rotation") {
                                    SecureField(L("Ripeti la password"), text: $repeated)
                                        .textContentType(.newPassword)
                                        .focused($focus, equals: .repeated)
                                        .submitLabel(.go)
                                        .onSubmit { send() }
                                }
                            }
                        }
                    }

                    if creating { rules }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }

                    Button(action: send) {
                        if busy {
                            ProgressView().tint(.black)
                        } else {
                            Text(creating ? L("Crea l'account") : L("Accedi"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canSend)

                    Text("Il server di TrackLap tiene il nome utente e la password protetta (mai in chiaro). Puoi eliminare l'account quando vuoi da Dispositivo.")
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annulla")) { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.bg)
        .onChange(of: creating) { _, _ in error = nil }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 6) {
            rule(nameOK, L("Nome utente da 3 a 20 caratteri: lettere, numeri, . - _ (è quello che vedono tutti)"))
            rule(password.count >= 8, L("Password di almeno 8 caratteri"))
            rule(!repeated.isEmpty && password == repeated, L("Le due password sono uguali"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func rule(_ ok: Bool, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ok ? Theme.good : Theme.sub)
        }
        .font(.caption)
        .foregroundStyle(ok ? Theme.text : Theme.sub)
    }

    private func send() {
        guard canSend else { return }
        busy = true
        error = nil
        focus = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                if creating {
                    try await model.account.signUp(name: name, password: password)
                } else {
                    try await model.account.signIn(name: name, password: password)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                withAnimation { self.error = error.localizedDescription }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            content().foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 48)
    }
}

/// The account in Dispositivo: who you are signed in as, and the ways out.
struct AccountPanel: View {
    @Environment(AppModel.self) private var model
    @State private var signingIn = false
    @State private var changing = false
    @State private var deleting = false
    @State private var confirmSignOut = false

    var body: some View {
        Panel {
            if let name = model.account.name {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.black)
                            .frame(width: 46, height: 46)
                            .background(Theme.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.headline).foregroundStyle(Theme.text)
                            Text(model.garage.isPublic ? L("Garage pubblico") : L("Garage visibile solo a te"))
                                .font(.caption)
                                .foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 10) {
                        Button { changing = true } label: { Label("Password", systemImage: "key.fill") }
                            .buttonStyle(SecondaryButtonStyle())
                        Button { confirmSignOut = true } label: { Label("Esci", systemImage: "rectangle.portrait.and.arrow.right") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button(role: .destructive) { deleting = true } label: {
                        Text("Elimina l'account").font(.caption.weight(.semibold)).foregroundStyle(Theme.bad)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Con un account mostri il garage a tutti e i tuoi tempi entrano nelle classifiche delle piste con il tuo nome e la tua auto.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.sub)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { signingIn = true } label: { Label("Accedi o crea un account", systemImage: "person.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .sheet(isPresented: $signingIn) { AccountSheet().environment(model) }
        .sheet(isPresented: $changing) { PasswordSheet(mode: .change).environment(model) }
        .sheet(isPresented: $deleting) { PasswordSheet(mode: .delete).environment(model) }
        .confirmationDialog(L("Uscire dall'account?"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(L("Esci"), role: .destructive) { Task { await model.account.signOut() } }
        } message: {
            Text("Il garage resta sul telefono e online. Per pubblicare di nuovo basta accedere.")
        }
    }
}

/// A new password, or deleting the account: both ask for the password you have now.
struct PasswordSheet: View {
    enum Mode { case change, delete }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var current = ""
    @State private var new = ""
    @State private var busy = false
    @State private var error: String?

    private var canSend: Bool { !busy && !current.isEmpty && (mode == .delete || new.count >= 8) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if mode == .delete {
                        Panel(glow: Theme.bad) {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Non si torna indietro", systemImage: "exclamationmark.triangle.fill")
                                    .font(.headline)
                                    .foregroundStyle(Theme.bad)
                                Text("Vengono cancellati dal server l'account, il garage online con le foto e tutti i tuoi tempi nelle classifiche. Le auto e le sessioni sul telefono restano.")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.sub)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Panel(padding: 6) {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: "lock.fill").foregroundStyle(Theme.accent).frame(width: 24)
                                SecureField(mode == .delete ? L("La tua password") : L("Password attuale"), text: $current)
                                    .textContentType(.password)
                                    .foregroundStyle(Theme.text)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            if mode == .change {
                                Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 48)
                                HStack(spacing: 12) {
                                    Image(systemName: "lock.rotation").foregroundStyle(Theme.accent).frame(width: 24)
                                    SecureField(L("Nuova password (almeno 8 caratteri)"), text: $new)
                                        .textContentType(.newPassword)
                                        .foregroundStyle(Theme.text)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                            }
                        }
                    }
                    if mode == .change {
                        Text("Gli altri telefoni con questo account escono e devono accedere con la nuova password.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.bad)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(action: send) {
                        if busy {
                            ProgressView().tint(.black)
                        } else {
                            Text(mode == .delete ? L("Elimina per sempre") : L("Cambia password"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: mode == .delete ? Theme.bad : Theme.accent))
                    .disabled(!canSend)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(mode == .delete ? L("Elimina l'account") : L("Cambia password"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annulla")) { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.bg)
        .presentationDetents([.medium, .large])
    }

    private func send() {
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                if mode == .delete {
                    try await model.account.delete(password: current)
                    model.garage.setPublic(false)
                } else {
                    try await model.account.changePassword(old: current, new: new)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
