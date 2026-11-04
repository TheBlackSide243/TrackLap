import SwiftUI
import UIKit
import PhotosUI

/// A new car or one to change: the photo, the name, the numbers in the units of the settings, the
/// modifications one per line, and notes.
struct CarEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let original: Car?
    private let onSave: (Car) -> Void

    @State private var car: Car
    @State private var year: String
    @State private var power: String
    @State private var weight: String
    @State private var mods: [ModLine]
    @State private var pick: PhotosPickerItem?
    @State private var loadingPhoto = false
    /// Photos picked here and not saved: deleted when the editor closes.
    @State private var picked: [String] = []
    @FocusState private var focus: Field?

    private enum Field: Hashable { case name, year, power, weight, mod(UUID), notes }

    struct ModLine: Identifiable, Equatable {
        var id = UUID()
        var text: String
    }

    init(car: Car?, onSave: @escaping (Car) -> Void = { _ in }) {
        original = car
        self.onSave = onSave
        let c = car ?? Car()
        _car = State(initialValue: c)
        _year = State(initialValue: c.year.map(String.init) ?? "")
        _power = State(initialValue: c.power.map { Fmt.power($0) } ?? "")
        _weight = State(initialValue: c.weight.map { Fmt.weight($0) } ?? "")
        _mods = State(initialValue: c.mods.map { ModLine(text: $0) })
    }

    private var canSave: Bool { !car.name.trimmingCharacters(in: .whitespaces).isEmpty && !loadingPhoto }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    photo
                    SectionLabel(L("L'auto"))
                    Panel(padding: 6) {
                        VStack(spacing: 0) {
                            row(icon: "car.fill") {
                                TextField(L("Marca e modello"), text: limited($car.name, Car.maxName))
                                    .textInputAutocapitalization(.words)
                                    .focused($focus, equals: .name)
                                    .submitLabel(.next)
                                    .onSubmit { focus = .year }
                            }
                            divider
                            row(icon: "calendar") {
                                TextField(L("Anno"), text: digits($year, 4))
                                    .keyboardType(.numberPad)
                                    .focused($focus, equals: .year)
                            }
                            divider
                            row(icon: "bolt.fill", unit: Fmt.powerUnit) {
                                TextField(L("Potenza"), text: digits($power, 4))
                                    .keyboardType(.numberPad)
                                    .focused($focus, equals: .power)
                            }
                            divider
                            row(icon: "scalemass.fill", unit: Fmt.weightUnit) {
                                TextField(L("Peso"), text: digits($weight, 5))
                                    .keyboardType(.numberPad)
                                    .focused($focus, equals: .weight)
                            }
                        }
                    }
                    if let r = ratio {
                        Label(L("Peso/potenza: \(Fmt.ratio(r)) \(Fmt.ratioUnit)"), systemImage: "gauge.with.dots.needle.67percent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                    }

                    SectionLabel(L("Modifiche"))
                    modsEditor

                    SectionLabel(L("Note"))
                    Panel(padding: 12) {
                        TextField(L("Gomme, assetto, com'è in pista…"), text: limited($car.notes, Car.maxNotes), axis: .vertical)
                            .lineLimit(3...8)
                            .focused($focus, equals: .notes)
                            .foregroundStyle(Theme.text)
                    }

                    if original != nil {
                        Button(role: .destructive) {
                            dismiss()
                            model.deleteCar(car.id)
                        } label: {
                            Label("Elimina l'auto", systemImage: "trash")
                        }
                        .buttonStyle(SecondaryButtonStyle(color: Theme.bad))
                        .padding(.top, 8)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(original == nil ? L("Nuova auto") : L("Modifica auto"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Annulla")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Salva")) { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L("Fine")) { focus = nil }
                }
            }
        }
        .presentationBackground(Theme.bg)
        .interactiveDismissDisabled(dirty)
        .onChange(of: pick) { _, item in load(item) }
        .onDisappear { cleanUp() }
    }

    // MARK: - Photo

    private var photo: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return PhotosPicker(selection: $pick, matching: .images) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    if let id = car.photo {
                        CarPhotoView(photo: .local(id))
                    } else {
                        ZStack {
                            LinearGradient(colors: [Theme.input, Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
                            VStack(spacing: 10) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(Theme.accent)
                                Text("Aggiungi una foto").font(.headline).foregroundStyle(Theme.text)
                                Text("La più bella: è quella che vedono tutti").font(.caption).foregroundStyle(Theme.sub)
                            }
                        }
                    }
                }
                .overlay {
                    if loadingPhoto {
                        ZStack {
                            Color.black.opacity(0.4)
                            ProgressView().tint(.white)
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if car.photo != nil {
                        Label("Cambia", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                            .padding(10)
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(car.photo == nil ? Theme.accent.opacity(0.5) : Theme.line.opacity(0.8),
                                            style: StrokeStyle(lineWidth: 1, dash: car.photo == nil ? [6, 5] : [])))
        }
        .buttonStyle(PressableStyle())
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        loadingPhoto = true
        Task { @MainActor in
            defer {
                loadingPhoto = false
                pick = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            // Made smaller away from the main thread: a 48-megapixel photo takes a moment.
            let jpeg = await Task.detached(priority: .userInitiated) { UIImage(data: data).flatMap(GarageStore.jpeg) }.value
            guard let jpeg, let id = model.garage.storePhoto(jpeg: jpeg) else { return }
            picked.append(id)
            withAnimation(.easeOut(duration: 0.2)) { car.photo = id }
        }
    }

    // MARK: - Modifications

    private var modsEditor: some View {
        VStack(spacing: 10) {
            if !mods.isEmpty {
                Panel(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(mods.enumerated()), id: \.element.id) { i, line in
                            HStack(spacing: 10) {
                                Text(verbatim: "\(i + 1)")
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 26, height: 26)
                                    .background(Theme.accent.opacity(0.12), in: Circle())
                                TextField(L("Es. scarico, centralina, freni"), text: modBinding(line.id))
                                    .focused($focus, equals: .mod(line.id))
                                    .submitLabel(.next)
                                    .onSubmit { addMod(after: line.id) }
                                    .foregroundStyle(Theme.text)
                                Button {
                                    withAnimation { mods.removeAll { $0.id == line.id } }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Theme.sub)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Togli"))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            if i < mods.count - 1 {
                                Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 46)
                            }
                        }
                    }
                }
            }
            if mods.count < Car.maxMods {
                Button { addMod(after: nil) } label: {
                    Label("Aggiungi una modifica", systemImage: "plus.circle.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Self.suggestions, id: \.self) { s in
                            Button { addMod(after: nil, text: s) } label: {
                                Text(s)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.text)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Theme.button, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// One tap for the usual ones: the line is added with the start written, to finish typing.
    private static var suggestions: [String] {
        [L("Scarico"), L("Centralina"), L("Aspirazione"), L("Intercooler"), L("Turbo"), L("Assetto"),
         L("Freni"), L("Gomme"), L("Cerchi"), L("Differenziale"), L("Frizione"), L("Sedili"),
         L("Roll-bar"), L("Alleggerimento"), L("Aerodinamica")]
    }

    private func addMod(after id: UUID?, text: String = "") {
        guard mods.count < Car.maxMods else { return }
        let line = ModLine(text: text.isEmpty ? "" : text + " ")
        withAnimation(.easeOut(duration: 0.2)) {
            if let id, let i = mods.firstIndex(where: { $0.id == id }) {
                mods.insert(line, at: i + 1)
            } else {
                mods.append(line)
            }
        }
        focus = .mod(line.id)
    }

    private func modBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { mods.first { $0.id == id }?.text ?? "" },
                set: { v in if let i = mods.firstIndex(where: { $0.id == id }) { mods[i].text = String(v.prefix(Car.maxMod)) } })
    }

    // MARK: - Saving

    private var ratio: Double? {
        guard let p = Int(power), let w = Int(weight), p > 0 else { return nil }
        return Double(Fmt.kg(fromShown: w)) / Double(Fmt.cv(fromShown: p))
    }

    /// The car as the fields have it now.
    private func edited() -> Car {
        var c = car
        c.name = c.name.trimmingCharacters(in: .whitespacesAndNewlines)
        c.year = Int(year).flatMap { (1900...2100).contains($0) ? $0 : nil }
        c.power = Int(power).map { Fmt.cv(fromShown: $0) }.flatMap { $0 > 0 ? $0 : nil }
        c.weight = Int(weight).map { Fmt.kg(fromShown: $0) }.flatMap { $0 >= 50 ? $0 : nil }
        c.mods = mods.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        c.notes = c.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return c
    }

    /// Something typed or picked: swiping the sheet away would lose it, so only the buttons close it.
    private var dirty: Bool {
        var before = original ?? Car()
        before.id = car.id
        before.added = car.added
        return edited() != before
    }

    private func save() {
        let c = edited()
        model.garage.save(c)
        picked.removeAll { $0 == c.photo }
        if c.id == model.activeCarID { model.setActiveCar(c.id) }
        onSave(c)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func cleanUp() {
        for id in picked { model.garage.discardPhoto(id) }
        picked = []
    }

    // MARK: - Pieces

    private func row<Content: View>(icon: String, unit: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            content()
                .foregroundStyle(Theme.text)
            if let unit {
                Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.sub)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 48)
    }

    private func limited(_ b: Binding<String>, _ max: Int) -> Binding<String> {
        Binding(get: { b.wrappedValue }, set: { b.wrappedValue = String($0.prefix(max)) })
    }

    private func digits(_ b: Binding<String>, _ max: Int) -> Binding<String> {
        Binding(get: { b.wrappedValue }, set: { b.wrappedValue = String($0.filter(\.isNumber).prefix(max)) })
    }
}
