import SwiftUI

/// Finding a track: the catalog and OpenStreetMap names while you type, venues near you or near a
/// town, all without blocking the screen; only downloading the chosen layout shows a spinner.
struct TrackSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (UUID) -> Void

    @State private var query = ""
    @State private var found: [TrackCandidate] = []
    @State private var places: [PlaceCandidate] = []
    @State private var searching = false
    @State private var searchFailed = false
    @State private var near: [TrackCandidate] = []
    @State private var nearTitle: String?
    @State private var nearBusy = false
    @State private var nearTask: Task<Void, Never>?
    @State private var downloading: String?
    @State private var message: String?

    private static let radiusKm = 50.0

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let catalog = Catalog.matching(trimmed)
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Button { startNearby(nil) } label: {
                            HStack(spacing: 12) {
                                AppGlyph(symbol: "location.circle.fill", size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Piste vicino a me").foregroundStyle(Theme.text)
                                    Text("Entro 50 km, da OpenStreetMap").font(.caption).foregroundStyle(Theme.sub)
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

                    if let nearTitle {
                        Section {
                            if nearBusy { progressRow(L("Cerco su OpenStreetMap: a volte i server sono lenti…")).id("near") }
                            ForEach(near) { candidateRow($0) }
                        } header: {
                            Text(nearTitle)
                        }
                    }

                    if !catalog.isEmpty {
                        Section {
                            ForEach(catalog) { candidateRow($0) }
                        } header: {
                            Text(trimmed.isEmpty ? L("Circuiti famosi") : L("Dal catalogo"))
                        }
                    }

                    if trimmed.count >= 3 {
                        Section {
                            if searching && found.isEmpty && places.isEmpty { progressRow(L("Cerco…")) }
                            ForEach(found) { candidateRow($0) }
                            ForEach(places) { placeRow($0) }
                            if !searching && found.isEmpty && places.isEmpty {
                                Text(searchFailed
                                     ? L("La ricerca non risponde: controlla la connessione e riprova.")
                                     : L("Nessun risultato. Prova con il paese più vicino e scegli «Piste vicino a…»."))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.sub)
                                    .listRowBackground(Theme.panel)
                            }
                        } header: {
                            Text("Su OpenStreetMap")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.bg)
                .onChange(of: nearTitle) { _, title in
                    if title != nil { withAnimation { proxy.scrollTo("near", anchor: .top) } }
                }
            }
            .navigationTitle("Cerca pista")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Circuito, kartodromo o città"))
            .autocorrectionDisabled()
            .task(id: trimmed) { await search(trimmed) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Chiudi") { dismiss() } }
            }
            .overlay { if let downloading { ProgressOverlay(text: downloading) } }
        }
        .presentationBackground(Theme.bg)
        .onDisappear { nearTask?.cancel() }
    }

    private func candidateRow(_ c: TrackCandidate) -> some View {
        Button { Task { await pick(c) } } label: {
            HStack(spacing: 12) {
                AppGlyph(symbol: c.icon, size: 34, color: c.kind == .karting ? Theme.yellow : Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: c.name).foregroundStyle(Theme.text).lineLimit(2)
                    Text(verbatim: c.subtitle).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
            }
        }
        .disabled(downloading != nil)
        .listRowBackground(Theme.panel)
    }

    private func placeRow(_ p: PlaceCandidate) -> some View {
        Button { startNearby(p) } label: {
            HStack(spacing: 12) {
                AppGlyph(symbol: "mappin.circle.fill", size: 34, color: Theme.sub)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Piste vicino a \(p.name)")).foregroundStyle(Theme.text).lineLimit(1)
                    Text(verbatim: p.detail).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.sub)
            }
        }
        .listRowBackground(Theme.panel)
    }

    private func progressRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().tint(Theme.accent)
            Text(text).font(.subheadline).foregroundStyle(Theme.sub)
        }
        .listRowBackground(Theme.panel)
    }

    /// Runs a moment after you stop typing; a new letter cancels the search in flight.
    private func search(_ q: String) async {
        guard q.count >= 3 else {
            found = []
            places = []
            searching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        searching = true
        searchFailed = false
        async let tracks = try? Photon.tracks(matching: q)
        async let towns = try? Photon.places(matching: q)
        let (t, p) = await (tracks, towns)
        if Task.isCancelled { return }
        let known = Catalog.matching(q)
        found = TrackFinder.merge(t ?? []).filter { c in !known.contains { TrackFinder.same($0, c) } }
        places = p ?? []
        searchFailed = t == nil && p == nil
        searching = false
    }

    private func startNearby(_ place: PlaceCandidate?) {
        nearTask?.cancel()
        message = nil
        near = []
        nearBusy = true
        nearTitle = place.map { L("Vicino a \($0.name)") } ?? L("Vicino a te")
        nearTask = Task { await nearby(place) }
    }

    /// Catalog circuits and names on Photon answer at once; the full tag search on Overpass,
    /// which can take half a minute, fills in the rest.
    private func nearby(_ place: PlaceCandidate?) async {
        defer { if !Task.isCancelled { nearBusy = false } }
        let center: Coord
        if let place {
            center = place.center
        } else {
            do {
                center = Coord(try await model.phone.currentLocation().coordinate)
            } catch {
                if !Task.isCancelled {
                    message = error.localizedDescription
                    nearTitle = nil
                }
                return
            }
        }
        let radius = Self.radiusKm
        let known = Catalog.all.filter { Geo.distance($0.center, center) <= radius * 1000 }
        let quick = await Photon.nearby(in: GeoBox(around: center, meters: radius * 1000))
        if Task.isCancelled { return }
        near = TrackFinder.sorted(TrackFinder.merge(known + quick), from: center).filter { ($0.distanceKm ?? 0) <= radius }
        let full = try? await Overpass.nearby(center, radiusKm: radius)
        if Task.isCancelled { return }
        if let full {
            near = TrackFinder.sorted(TrackFinder.merge(known + full + near), from: center)
        }
        if near.isEmpty {
            message = full == nil ? FinderError.busy.localizedDescription : L("Nessuna pista trovata entro 50 km.")
        }
    }

    private func pick(_ c: TrackCandidate) async {
        downloading = L("Scarico il tracciato di \(c.name)…")
        defer { downloading = nil }
        let t = await TrackFinder.track(name: c.name, place: c.place.isEmpty ? c.kindTitle : c.place, center: c.center,
                                        box: c.searchBox, karting: c.kind == .karting)
        model.save(track: t)
        onCreated(t.id)
    }
}
