import SwiftUI
import MapKit
import UIKit

/// Satellite map of the track: tap the track to place the start line and up to four intermediates.
struct TrackEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let trackID: UUID

    @State private var draft: Track?
    @State private var camera: MapCameraPosition = .automatic
    @State private var tool: Tool = .start
    @State private var width: Double = 24
    @State private var pending: Coord?
    @State private var hint: String?
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false

    enum Tool: String, CaseIterable, Identifiable {
        case start, sector
        var id: String { rawValue }
        var title: String { self == .start ? L("Linea del via") : L("Intermedio") }
    }

    var body: some View {
        Group {
            if let draft {
                editor(draft)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
            }
        }
        .navigationTitle(draft?.name ?? L("Pista"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { newName = draft?.name ?? ""; renaming = true } label: { Label("Rinomina", systemImage: "pencil") }
                    Button { update { $0.sectors = [] } } label: { Label("Togli gli intermedi", systemImage: "minus.circle") }
                    Button { update { $0.start = nil } } label: { Label("Togli la linea del via", systemImage: "flag.slash") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina pista", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Rinomina pista", isPresented: $renaming) {
            TextField("Nome", text: $newName)
            Button("Salva") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { update { $0.name = name } }
            }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Eliminare la pista?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                model.deleteTrack(trackID)
                dismiss()
            }
        }
        .onAppear(perform: load)
    }

    private func editor(_ t: Track) -> some View {
        ZStack(alignment: .bottom) {
            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(Array(t.outline.enumerated()), id: \.offset) { item in
                        MapPolyline(coordinates: item.element.map(\.cl))
                            .stroke(Theme.accent.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                    ForEach(Array(t.sectors.enumerated()), id: \.offset) { item in
                        MapPolyline(coordinates: [item.element.a.cl, item.element.b.cl])
                            .stroke(Theme.yellow, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        Annotation("I\(item.offset + 1)", coordinate: item.element.mid.cl, anchor: .bottom) {
                            GateBadge(text: "I\(item.offset + 1)", color: Theme.yellow)
                        }
                        .annotationTitles(.hidden)
                    }
                    if let s = t.start {
                        MapPolyline(coordinates: [s.a.cl, s.b.cl])
                            .stroke(.white, style: StrokeStyle(lineWidth: 8))
                        MapPolyline(coordinates: [s.a.cl, s.b.cl])
                            .stroke(.black, style: StrokeStyle(lineWidth: 8, dash: [4, 4]))
                        Annotation("Via", coordinate: s.mid.cl, anchor: .bottom) {
                            GateBadge(text: L("VIA"), color: .white, icon: "flag.checkered")
                        }
                        .annotationTitles(.hidden)
                    }
                    if let pending {
                        Annotation("", coordinate: pending.cl) {
                            Circle().fill(Theme.accent).frame(width: 14, height: 14)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }
                    UserAnnotation()
                }
                .mapStyle(.imagery(elevation: .flat))
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .onTapGesture { point in
                    if let c = proxy.convert(point, from: .local) { tap(Coord(c)) }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            controls(t)
        }
    }

    private func controls(_ t: Track) -> some View {
        VStack(spacing: 12) {
            Text(hint ?? defaultHint(t))
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.default, value: hint)

            Picker("Strumento", selection: $tool) {
                ForEach(Tool.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Image(systemName: "arrow.left.and.right").foregroundStyle(Theme.sub)
                Slider(value: $width, in: 8...60, step: 1, onEditingChanged: { editing in
                    if !editing { resizeGates() }
                })
                Text("\(Int(width)) m").font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(Theme.sub).frame(width: 40)
            }

            if !t.sectors.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(t.sectors.indices), id: \.self) { i in
                            Button {
                                update { $0.sectors.remove(at: i) }
                            } label: {
                                Label("I\(i + 1)", systemImage: "xmark.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.yellow)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Theme.yellow.opacity(0.14), in: Capsule())
                            }
                        }
                    }
                }
            }

            HStack(spacing: 10) {
                Button { Task { await markHere() } } label: {
                    Label("Segna qui", systemImage: "location.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                Button {
                    model.select(track: t.id)
                    model.tab = .live
                } label: {
                    Label(model.selectedTrackID == t.id ? L("In uso") : L("Usa pista"), systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!t.isReady)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Theme.line.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func defaultHint(_ t: Track) -> String {
        if pending != nil { return L("Tocca l'altro lato della pista.") }
        switch tool {
        case .start:
            if t.outline.isEmpty { return L("Nessun tracciato su OpenStreetMap: tocca i due lati della pista per il via.") }
            return t.start == nil ? L("Tocca la pista nel punto del traguardo.") : L("Tocca di nuovo per spostare il via.")
        case .sector:
            return t.sectors.count < 4 ? L("Tocca la pista per aggiungere un intermedio (\(t.sectors.count)/4).") : L("Hai già 4 intermedi: toccane uno sotto per toglierlo.")
        }
    }

    // MARK: - Editing

    private func load() {
        guard draft == nil, let t = model.tracks.track(trackID) else { return }
        draft = t
        if let s = t.start { width = max(8, min(60, s.width.rounded())) }
        if t.start == nil { tool = .start }
        camera = .region(TrackGeometry.region(for: t.allPoints, fallback: t.center))
    }

    private func update(_ change: (inout Track) -> Void) {
        guard var t = draft else { return }
        change(&t)
        draft = t
        model.save(track: t)
    }

    private func resizeGates() {
        let w = width
        update { track in
            track.start = track.start?.resized(w)
            track.sectors = track.sectors.map { gate in gate.resized(w) }
        }
    }

    private func tap(_ c: Coord) {
        guard let t = draft else { return }
        let gate: GateLine
        if let p = pending {
            gate = GateLine(a: p, b: c)
            pending = nil
        } else if let g = TrackGeometry.gate(at: c, outline: t.outline, width: width) {
            gate = g
        } else {
            pending = c
            hint = nil
            return
        }
        place(gate)
    }

    private func place(_ gate: GateLine) {
        switch tool {
        case .start:
            update { $0.start = gate }
            hint = L("Linea del via messa. Ora aggiungi gli intermedi, se vuoi.")
            tool = .sector
        case .sector:
            guard (draft?.sectors.count ?? 0) < 4 else {
                hint = L("Massimo 4 intermedi.")
                return
            }
            update { $0.sectors.append(gate) }
            hint = nil
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// The line where you are now: across your direction of travel when moving, otherwise across the track.
    private func markHere() async {
        var coord: Coord?
        var heading: Double?
        if let p = model.engine.position, let w = model.lastFixWall, Date().timeIntervalSince(w) < 3 {
            coord = p
            if model.engine.speed > 2 { heading = model.engine.heading }
        } else if let loc = try? await model.phone.currentLocation() {
            coord = Coord(loc.coordinate)
            if loc.course >= 0 && loc.speed > 2 { heading = loc.course }
        }
        guard let coord else {
            hint = L("Posizione non disponibile.")
            return
        }
        let gate = heading.map { TrackGeometry.gate(at: coord, heading: $0, width: width) }
            ?? TrackGeometry.gate(at: coord, outline: draft?.outline ?? [], width: width)
        guard let gate else {
            hint = L("Sei lontano dal tracciato: fermati sulla linea e riprova, oppure tocca la mappa.")
            return
        }
        place(gate)
        camera = .region(MKCoordinateRegion(center: coord.cl, latitudinalMeters: 250, longitudinalMeters: 250))
    }
}

private struct GateBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.system(size: 11, weight: .heavy))
        .foregroundStyle(.black)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color, in: Capsule())
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .padding(.bottom, 6)
    }
}
