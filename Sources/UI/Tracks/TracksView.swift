import SwiftUI

struct TracksView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [UUID] = []
    @State private var showSearch = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(icon: "map.fill", title: "Piste", subtitle: subtitle)
                    HStack(spacing: 10) {
                        Button { showSearch = true } label: {
                            Label("Cerca pista", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Button { Task { await createHere() } } label: {
                            Label("Crea qui", systemImage: "location.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    SectionLabel("Le tue piste")
                    ForEach(model.tracks.tracks) { track in
                        TrackCard(track: track, selected: track.id == model.selectedTrackID) {
                            model.select(track: track.id)
                        } onEdit: {
                            path.append(track.id)
                        }
                        .contextMenu {
                            Button { path.append(track.id) } label: { Label("Modifica", systemImage: "pencil") }
                            Button(role: .destructive) { model.deleteTrack(track.id) } label: { Label("Elimina", systemImage: "trash") }
                        }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { TrackEditorView(trackID: $0) }
            .sheet(isPresented: $showSearch) {
                TrackSearchView { id in
                    showSearch = false
                    path.append(id)
                }
            }
            .overlay { if busy { ProgressOverlay(text: "Cerco la pista qui intorno…") } }
            .alert("Qualcosa non va", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var subtitle: String {
        let n = model.tracks.tracks.count
        return n == 1 ? "1 pista salvata" : "\(n) piste salvate"
    }

    /// A new track where you are standing, with whatever raceway OpenStreetMap has around.
    private func createHere() async {
        busy = true
        defer { busy = false }
        do {
            let loc = try await model.phone.currentLocation()
            let c = Coord(loc.coordinate)
            let ways = (try? await Overpass.outline(around: c, radius: 900)) ?? []
            let t = Track(name: "Nuova pista", place: "Creata sul posto", center: c, outline: ways)
            model.save(track: t)
            path.append(t.id)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TrackCard: View {
    let track: Track
    let selected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.bg)
                if track.outline.isEmpty && track.start == nil {
                    Image(systemName: "map").font(.title2).foregroundStyle(Theme.line)
                } else {
                    TrackShape(track: track, lineWidth: 2.5)
                }
            }
            .frame(width: 76, height: 76)

            VStack(alignment: .leading, spacing: 6) {
                Text(track.name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if !track.place.isEmpty {
                    Text(track.place).font(.caption).foregroundStyle(Theme.sub).lineLimit(1)
                }
                HStack(spacing: 6) {
                    if track.isReady {
                        Badge(text: "Pronta", color: Theme.good)
                    } else {
                        Badge(text: "Manca il via", color: Theme.yellow)
                    }
                    if track.sectorCount > 0 { Badge(text: "\(track.sectorCount) settori", color: Theme.purple) }
                    if let l = track.length { Badge(text: Fmt.distance(l), color: Theme.sub) }
                }
            }
            Spacer(minLength: 0)
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.button, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(selected ? Theme.accent.opacity(0.08) : Theme.panel, in: shape)
        .overlay(shape.strokeBorder(selected ? Theme.accent : Theme.line.opacity(0.8), lineWidth: selected ? 1.5 : 1))
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .sensoryFeedback(.selection, trigger: selected)
    }
}
