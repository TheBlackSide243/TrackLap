import SwiftUI

struct TrackSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (UUID) -> Void

    @State private var query = ""
    @State private var results: [TrackCandidate] = []
    @State private var resultsTitle = "Risultati"
    @State private var working: String?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { Task { await nearby() } } label: {
                        HStack(spacing: 12) {
                            AppGlyph(symbol: "location.circle.fill", size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Piste vicino a me").foregroundStyle(Theme.text)
                                Text("Entro 60 km, da OpenStreetMap").font(.caption).foregroundStyle(Theme.sub)
                            }
                        }
                    }
                    .listRowBackground(Theme.panel)
                }
                if let message {
                    Section {
                        Text(message).font(.subheadline).foregroundStyle(Theme.sub)
                    }
                    .listRowBackground(Theme.panel)
                }
                if !results.isEmpty {
                    Section(resultsTitle) {
                        ForEach(results) { row($0) }
                    }
                }
                Section("Circuiti italiani") {
                    ForEach(ItalianCircuits.all) { row($0) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Cerca pista")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Nome del circuito o del kartodromo")
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
            }
            .overlay { if let working { ProgressOverlay(text: working) } }
        }
        .presentationBackground(Theme.bg)
    }

    private func row(_ c: TrackCandidate) -> some View {
        Button { Task { await pick(c) } } label: {
            HStack(spacing: 12) {
                AppGlyph(symbol: c.icon, size: 34, color: c.kind == .karting ? Theme.yellow : Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).foregroundStyle(Theme.text).lineLimit(1)
                    Text(c.subtitle).font(.caption).foregroundStyle(Theme.sub)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
            }
        }
        .listRowBackground(Theme.panel)
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        working = "Cerco “\(q)”…"
        defer { working = nil }
        do {
            results = try await Overpass.search(name: q)
            resultsTitle = "Risultati per “\(q)”"
            message = results.isEmpty ? "Nessuna pista trovata in Italia con questo nome. Prova una parola sola, ad esempio il nome del paese." : nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func nearby() async {
        working = "Cerco le piste qui intorno…"
        defer { working = nil }
        do {
            let loc = try await model.phone.currentLocation()
            results = try await Overpass.nearby(Coord(loc.coordinate))
            resultsTitle = "Vicino a te"
            message = results.isEmpty ? "Nessuna pista entro 60 km." : nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func pick(_ c: TrackCandidate) async {
        working = "Scarico il tracciato di \(c.name)…"
        defer { working = nil }
        do {
            let ways = try await Overpass.outline(around: c.center, radius: c.radius)
            let t = Track(name: c.name, place: c.subtitle, center: c.center, outline: ways)
            model.save(track: t)
            onCreated(t.id)
        } catch {
            message = error.localizedDescription
        }
    }
}
