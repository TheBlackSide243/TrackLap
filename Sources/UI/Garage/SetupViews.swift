import SwiftUI
import UIKit

/// A setup to open from a car's page.
struct SetupRef: Hashable, Identifiable {
    let id: UUID
}

/// A setup in a list: its conditions, name, version and the best lap driven with it.
struct SetupRow: View {
    @Environment(AppModel.self) private var model
    let setup: CarSetup

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let active = setup.id == model.activeSetupID
        HStack(spacing: 12) {
            WeatherGlyph(weather: setup.weather)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(setup.displayName).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    if active { Badge(text: L("In uso"), color: Theme.accent) }
                }
                Text(subtitle).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let best = best {
                Text(Fmt.lap(best))
                    .font(Theme.timeFont(17))
                    .monospacedDigit()
                    .foregroundStyle(Theme.purple)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.line)
        }
        .padding(12)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(active ? Theme.accent.opacity(0.7) : Theme.line.opacity(0.8), lineWidth: 1))
        .contentShape(shape)
    }

    private var subtitle: String {
        var parts = [setup.weather.title]
        if !setup.track.isEmpty { parts.append(setup.track) }
        parts.append(L("v\(setup.version)"))
        parts.append(Fmt.dayShort.string(from: setup.updated))
        return parts.joined(separator: " · ")
    }

    private var best: Double? {
        model.sessions.summaries.filter { $0.setupID == setup.id }.compactMap(\.best).min()
    }
}

struct WeatherGlyph: View {
    let weather: SetupWeather
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: weather.symbol)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size * 0.45, weight: .semibold))
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }

    private var color: Color {
        switch weather {
        case .dry: Theme.yellow
        case .mixed: Theme.accent
        case .wet: Color(rgb: 96, 165, 250)
        }
    }
}

/// A setup's values by group, only those that are set.
struct SetupValuesView: View {
    let values: SetupValues

    var body: some View {
        VStack(spacing: 14) {
            ForEach(SetupField.Group.allCases) { group in
                let rows = SetupField.all.filter { $0.group == group }.compactMap { f in f.display(values).map { (f.title, $0) } }
                if !rows.isEmpty {
                    Panel(padding: 6) {
                        VStack(spacing: 0) {
                            Label(group.title, systemImage: group.symbol)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 4)
                            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                                if i > 0 { Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.horizontal, 10) }
                                HStack {
                                    Text(row.0).font(.subheadline).foregroundStyle(Theme.sub)
                                    Spacer(minLength: 8)
                                    Text(row.1).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                                        .multilineTextAlignment(.trailing)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                            }
                        }
                    }
                }
            }
            if !values.extra.isEmpty {
                Panel(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach(Array(values.extra.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.horizontal, 10) }
                            HStack {
                                Text(item.label).font(.subheadline).foregroundStyle(Theme.sub)
                                Spacer(minLength: 8)
                                Text(item.value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                        }
                    }
                }
            }
            let notes = values.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !notes.isEmpty {
                Panel {
                    Text(notes).font(.body).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if values.isEmpty {
                Text("Ancora nessun valore: tocca Modifica per scriverli.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// One setup: its values now, every earlier version with what changed, and the sessions driven
/// with it. Changing it never loses anything: the values it had go into the history.
struct SetupDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let setupID: UUID
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var shownRevision: SetupRevision?

    var body: some View {
        if let setup = model.garage.setup(setupID) {
            ScrollView {
                VStack(spacing: 14) {
                    header(setup)
                    drive(setup)
                    SetupValuesView(values: setup.values)
                    sessions(setup)
                    history(setup)
                    Text("Gli assetti restano su questo telefono: non vanno mai online. Per darli a qualcuno si esportano in un file.")
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(setup.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = true } label: { Label("Modifica", systemImage: "slider.horizontal.3") }
                        Button {
                            if let copy = model.garage.duplicate(setup: setup.id) { editingCopy = copy.id }
                        } label: { Label("Duplica", systemImage: "plus.square.on.square") }
                        if let car = model.garage.car(setup.carID) {
                            ShareLink(item: SharedSetupFile(shared: SharedSetup(car: car.displayName, setup: setup)),
                                      preview: SharePreview(setup.displayName)) {
                                Label("Esporta in un file", systemImage: "square.and.arrow.up")
                            }
                        }
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L("Altro"))
                }
            }
            .sheet(isPresented: $editing) { SetupEditorView(setup: setup, carID: setup.carID).environment(model) }
            .sheet(item: Binding(get: { editingCopy.map(SetupRef.init) }, set: { editingCopy = $0?.id })) { ref in
                if let copy = model.garage.setup(ref.id) {
                    SetupEditorView(setup: copy, carID: copy.carID).environment(model)
                }
            }
            .sheet(item: $shownRevision) { r in RevisionSheet(setup: setup, revision: r).environment(model) }
            .confirmationDialog(L("Eliminare questo assetto?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("Elimina l'assetto"), role: .destructive) {
                    dismiss()
                    model.deleteSetup(setup.id)
                }
            } message: {
                Text("Le sessioni restano, con l'assetto com'era quel giorno.")
            }
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    @State private var editingCopy: UUID?

    private func header(_ s: CarSetup) -> some View {
        Panel {
            HStack(spacing: 14) {
                WeatherGlyph(weather: s.weather, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.displayName).font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                    Text([s.weather.title, s.track, model.garage.car(s.carID)?.displayName ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.sub)
                    Text(L("Versione \(s.version) · aggiornato il \(Fmt.dayShort.string(from: s.updated))"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func drive(_ s: CarSetup) -> some View {
        if s.id == model.activeSetupID && s.carID == model.activeCarID {
            Label(L("Lo stai usando in Live: le prossime sessioni se lo ricordano"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.good)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Button { withAnimation { model.drive(setup: s) } } label: {
                Label("Usa questo assetto in Live", systemImage: "steeringwheel")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    @ViewBuilder
    private func sessions(_ s: CarSetup) -> some View {
        let list = model.sessions.summaries.filter { $0.setupID == s.id }
        if !list.isEmpty {
            SectionLabel(L("Sessioni con questo assetto"))
            VStack(spacing: 8) {
                ForEach(list.prefix(8)) { x in
                    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(x.trackName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text([Fmt.dayShort.string(from: x.date), x.setupVersion.map { L("v\($0)") } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.sub)
                        }
                        Spacer(minLength: 0)
                        Text(Fmt.lap(x.best)).font(Theme.timeFont(17)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                    .padding(10)
                    .background(Theme.panel, in: shape)
                    .overlay(shape.strokeBorder(Theme.line.opacity(0.8), lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private func history(_ s: CarSetup) -> some View {
        if !s.history.isEmpty {
            SectionLabel(L("Versioni precedenti"))
            VStack(spacing: 8) {
                ForEach(Array(s.history.enumerated()), id: \.element.id) { i, r in
                    // What the next version changed from this one.
                    let newer = i == 0 ? s.values : s.history[i - 1].values
                    let changes = newer.changes(from: r.values)
                    Button { shownRevision = r } label: {
                        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(L("Versione \(r.version)")).font(.subheadline.weight(.bold)).foregroundStyle(Theme.text)
                                Spacer()
                                Text(L("fino al \(Fmt.dayShort.string(from: r.date))")).font(.caption).foregroundStyle(Theme.sub)
                            }
                            ForEach(changes.prefix(3), id: \.self) { c in
                                Text(c).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                            }
                            if changes.count > 3 {
                                Text(L("e altre \(changes.count - 3) modifiche")).font(.caption).foregroundStyle(Theme.sub)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.panel, in: shape)
                        .overlay(shape.strokeBorder(Theme.line.opacity(0.8), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }
}

/// An earlier version of a setup, to look at or to bring back (as a new version: the one it
/// replaces stays in the history too).
private struct RevisionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let setup: CarSetup
    let revision: SetupRevision

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    SetupValuesView(values: revision.values)
                    Button {
                        var s = setup
                        s.values = revision.values
                        model.garage.save(setup: s)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    } label: {
                        Label(L("Torna a questa versione"), systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Text("La versione di adesso non si perde: va anche lei nello storico.")
                        .font(.caption)
                        .foregroundStyle(Theme.sub)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L("Versione \(revision.version)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("Fine")) { dismiss() } }
            }
        }
        .presentationBackground(Theme.bg)
    }
}

/// A new setup or a change to one: the name, the conditions, the track, every value in the units
/// of the settings, anything else as name and value, and notes.
struct SetupEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private let original: CarSetup?
    @State private var setup: CarSetup
    @State private var numbers: [String: String] = [:]
    /// The numbers as they were shown: a field left alone keeps its value to the last decimal.
    private let shownAtStart: [String: String]

    /// The vehicle the setup is for: a bike has preload and sag instead of camber and wings.
    private var kind: VehicleKind { model.garage.car(setup.carID)?.vehicle ?? .car }

    init(setup: CarSetup?, carID: UUID) {
        original = setup
        let s = setup ?? CarSetup(carID: carID)
        _setup = State(initialValue: s)
        var n: [String: String] = [:]
        for f in SetupField.all {
            if let k = f.number, let x = s.values[keyPath: k] { n[f.id] = SetupField.format(f.shown(x), decimals: f.shownDecimals) }
        }
        _numbers = State(initialValue: n)
        shownAtStart = n
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Panel(padding: 6) {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: "tag.fill").foregroundStyle(Theme.accent).frame(width: 24)
                                TextField(L("Nome (es. Mugello bagnato)"), text: $setup.name).foregroundStyle(Theme.text)
                            }
                            .padding(12)
                            Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 48)
                            HStack(spacing: 12) {
                                Image(systemName: "flag.checkered").foregroundStyle(Theme.accent).frame(width: 24)
                                TextField(L("Pista (facoltativa)"), text: $setup.track).foregroundStyle(Theme.text)
                                if setup.track.isEmpty, let t = model.selectedTrack {
                                    Button(t.name) { setup.track = t.name }
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                            }
                            .padding(12)
                        }
                    }
                    Picker(L("Condizioni"), selection: $setup.weather) {
                        ForEach(SetupWeather.allCases) { w in Label(w.title, systemImage: w.symbol).tag(w) }
                    }
                    .pickerStyle(.segmented)

                    ForEach(SetupField.Group.allCases) { group in
                        let fields = SetupField.fields(for: kind).filter { $0.group == group }
                        if !fields.isEmpty {
                            SectionLabel(group.title)
                            Panel(padding: 6) {
                                VStack(spacing: 0) {
                                    ForEach(Array(fields.enumerated()), id: \.element.id) { i, f in
                                        if i > 0 { Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 12) }
                                        row(f)
                                    }
                                }
                            }
                        }
                    }

                    SectionLabel(L("Altro"))
                    extras

                    SectionLabel(L("Note"))
                    Panel(padding: 12) {
                        TextField(L("Come andava, cosa provare la prossima volta…"), text: $setup.values.notes, axis: .vertical)
                            .lineLimit(3...8)
                            .foregroundStyle(Theme.text)
                    }
                    if original != nil {
                        Text("Salvando, i valori di adesso restano nelle versioni precedenti.")
                            .font(.caption)
                            .foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(original == nil ? L("Nuovo assetto") : L("Modifica assetto"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Annulla")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Salva")) { save() }.fontWeight(.bold)
                }
            }
        }
        .presentationBackground(Theme.bg)
        .interactiveDismissDisabled(edited() != (original ?? CarSetup(id: setup.id, carID: setup.carID, created: setup.created, updated: setup.updated)))
    }

    @ViewBuilder
    private func row(_ f: SetupField) -> some View {
        HStack(spacing: 10) {
            Text(f.title).font(.subheadline).foregroundStyle(Theme.sub)
            Spacer(minLength: 8)
            if let k = f.text {
                TextField("—", text: Binding(get: { setup.values[keyPath: k] }, set: { setup.values[keyPath: k] = String($0.prefix(40)) }))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.text)
            } else {
                TextField("—", text: Binding(get: { numbers[f.id] ?? "" }, set: { numbers[f.id] = Self.clean($0) }))
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: 110)
                if !f.shownUnit.isEmpty {
                    Text(f.shownUnit).font(.caption.weight(.semibold)).foregroundStyle(Theme.sub).frame(minWidth: 30, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var extras: some View {
        VStack(spacing: 10) {
            if !setup.values.extra.isEmpty {
                Panel(padding: 6) {
                    VStack(spacing: 0) {
                        ForEach($setup.values.extra) { $item in
                            HStack(spacing: 8) {
                                TextField(L("Voce"), text: $item.label).foregroundStyle(Theme.text)
                                TextField(L("Valore"), text: $item.value).multilineTextAlignment(.trailing).foregroundStyle(Theme.text)
                                Button { setup.values.extra.removeAll { $0.id == item.id } } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(Theme.sub)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            Button { setup.values.extra.append(SetupItem(label: "", value: "")) } label: {
                Label("Aggiungi una voce", systemImage: "plus.circle.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    /// Digits, one decimal separator and a leading minus (camber is negative).
    private static func clean(_ s: String) -> String {
        var out = ""
        for c in s.replacingOccurrences(of: ",", with: ".") {
            if c.isNumber || (c == "." && !out.contains(".")) || (c == "-" && out.isEmpty) { out.append(c) }
        }
        return String(out.prefix(8))
    }

    private func edited() -> CarSetup {
        var s = setup
        for f in SetupField.all {
            guard let k = f.number, numbers[f.id] != shownAtStart[f.id] else { continue }
            s.values[keyPath: k] = Double(numbers[f.id] ?? "").map { f.kept($0) }
        }
        s.values.extra = s.values.extra.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty || !$0.value.isEmpty }
        s.name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.track = s.track.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }

    private func save() {
        let s = edited()
        model.garage.save(setup: s)
        // A new setup made while driving that car is the one in use.
        if original == nil, s.carID == model.activeCarID { model.setActiveSetup(s.id) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// A .tracklapsetup file opened: which of your cars it is for.
struct SetupImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let shared: SharedSetup

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Panel {
                        HStack(spacing: 14) {
                            WeatherGlyph(weather: shared.setup.weather, size: 52)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(shared.setup.displayName).font(.title3.weight(.heavy)).foregroundStyle(Theme.text)
                                Text(L("Assetto per \(shared.car)")).font(.subheadline).foregroundStyle(Theme.sub)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if model.garage.cars.isEmpty {
                        Text("Aggiungi prima un veicolo nel Garage: l'assetto va con un veicolo.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.sub)
                    } else {
                        SectionLabel(L("Aggiungilo a"))
                        ForEach(model.garage.cars) { car in
                            Button {
                                model.garage.importSetup(shared, for: car.id)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                dismiss()
                            } label: {
                                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                                HStack(spacing: 12) {
                                    CarPhotoView(photo: car.info.photo, kind: car.vehicle)
                                        .frame(width: 56, height: 42)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    Text(car.displayName).font(.headline).foregroundStyle(Theme.text)
                                    Spacer(minLength: 0)
                                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                                }
                                .padding(10)
                                .background(Theme.panel, in: shape)
                                .overlay(shape.strokeBorder(Theme.line.opacity(0.8), lineWidth: 1))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    SetupValuesView(values: shared.setup.values)
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(L("Importa assetto"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Annulla")) { dismiss() } }
            }
        }
        .presentationBackground(Theme.bg)
    }
}

/// The setup you drive with, next to the car in Live and Drag.
struct ActiveSetupChip: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false

    var body: some View {
        if let car = model.activeCar {
            let list = model.garage.setups(of: car.id)
            Menu {
                if !list.isEmpty {
                    Picker(L("Assetto"), selection: Binding(get: { model.activeSetupID }, set: { model.setActiveSetup($0) })) {
                        Text("Nessuno").tag(UUID?.none)
                        ForEach(list) { s in
                            Label(s.displayName, systemImage: s.weather.symbol).tag(UUID?.some(s.id))
                        }
                    }
                    Divider()
                }
                Button { creating = true } label: { Label("Nuovo assetto", systemImage: "plus") }
            } label: {
                HStack(spacing: 5) {
                    if let s = model.activeSetup {
                        Image(systemName: s.weather.symbol).symbolRenderingMode(.multicolor).font(.caption2)
                        Text(s.displayName).lineLimit(1)
                    } else {
                        Image(systemName: "slider.horizontal.3").font(.caption2.weight(.bold)).foregroundStyle(Theme.sub)
                        Text("Assetto")
                    }
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.sub)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: 150, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.panel, in: Capsule())
                .overlay(Capsule().strokeBorder(model.activeSetup == nil ? Theme.line : Theme.accent.opacity(0.6), lineWidth: 1))
            }
            .accessibilityLabel(L("Assetto in uso"))
            .sheet(isPresented: $creating) { SetupEditorView(setup: nil, carID: car.id).environment(model) }
        }
    }
}
