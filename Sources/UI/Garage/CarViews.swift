import SwiftUI
import UIKit

/// A car's photo filling its frame: from the garage folder, from the server, or a drawn car when
/// there is none.
struct CarPhotoView: View {
    @Environment(AppModel.self) private var model
    let photo: CarPhoto
    var contentMode: ContentMode = .fill

    var body: some View {
        switch photo {
        case .local(let id):
            if let image = model.garage.image(id) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                CarPlaceholder()
            }
        case .remote(let url):
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: contentMode)
                case .failure: CarPlaceholder()
                default:
                    ZStack {
                        CarPlaceholder()
                        ProgressView().tint(Theme.sub)
                    }
                }
            }
        case .empty:
            CarPlaceholder()
        }
    }
}

struct CarPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.input, Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "car.side.fill")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Theme.sub.opacity(0.45))
        }
    }
}

/// A car in a grid: the photo, its name and its numbers.
struct CarCard: View {
    let info: CarInfo
    var badge: String? = nil

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { CarPhotoView(photo: info.photo) }
                .clipped()
                .overlay(alignment: .topLeading) {
                    if let badge { CarBadge(text: badge).padding(8) }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(info.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Theme.panel)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.line.opacity(0.8), lineWidth: 1))
        .contentShape(shape)
    }

    private var caption: String {
        let mods = info.mods.count
        let parts = [info.subtitle.isEmpty ? nil : info.subtitle,
                     mods == 0 ? nil : mods == 1 ? L("1 modifica") : L("\(mods) modifiche")]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? L("Nessun dato") : text
    }
}

/// The car you drive, across the top of your garage.
struct CarHeroCard: View {
    let info: CarInfo
    let badge: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay { CarPhotoView(photo: info.photo) }
            .overlay {
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) { CarBadge(text: badge, filled: true).padding(12) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.name)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                    SpecChips(info: info)
                }
                .padding(16)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1))
            .contentShape(shape)
    }
}

/// Power, weight and the two together, as small glass chips over a photo.
struct SpecChips: View {
    let info: CarInfo

    var body: some View {
        HStack(spacing: 6) {
            if let p = info.power { chip(Fmt.power(p), Fmt.powerUnit) }
            if let w = info.weight { chip(Fmt.weight(w), Fmt.weightUnit) }
            if let r = info.ratio { chip(Fmt.ratio(r), Fmt.ratioUnit) }
        }
    }

    private func chip(_ value: String, _ unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value).font(.system(size: 14, weight: .heavy, design: .rounded)).monospacedDigit()
            Text(unit).font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }
}

struct CarBadge: View {
    let text: String
    var filled = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(filled ? Color.black : Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filled ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .environment(\.colorScheme, .dark)
    }
}

/// A car's page: the photo across the top (it stretches when pulled down, and opens full screen),
/// the numbers, the modifications and the notes, then whatever the screen adds below.
struct CarDetailContent<Extra: View>: View {
    let info: CarInfo
    var badge: String? = nil
    @ViewBuilder var extra: Extra
    @State private var viewing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                VStack(spacing: 14) {
                    SpecGrid(info: info)
                    if !info.mods.isEmpty {
                        SectionLabel(info.mods.count == 1 ? L("1 modifica") : L("\(info.mods.count) modifiche"))
                        ModsPanel(mods: info.mods)
                    }
                    let notes = info.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty {
                        SectionLabel(L("Note"))
                        Panel {
                            Text(notes)
                                .font(.body)
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    extra
                }
                .padding(16)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.bg.ignoresSafeArea())
        .fullScreenCover(isPresented: $viewing) { PhotoViewer(photo: info.photo) }
    }

    private var hero: some View {
        GeometryReader { g in
            let pull = max(0, g.frame(in: .scrollView).minY)
            CarPhotoView(photo: info.photo)
                .frame(width: g.size.width, height: g.size.height + pull)
                .clipped()
                .overlay {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).frame(height: 110)
                        Spacer()
                        LinearGradient(colors: [.clear, Theme.bg.opacity(0.7), Theme.bg], startPoint: .top, endPoint: .bottom).frame(height: 150)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let badge { CarBadge(text: badge, filled: true) }
                        Text(info.name)
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)
                        if let year = info.year {
                            Text(String(year)).font(.headline).foregroundStyle(Theme.sub)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }
                .offset(y: -pull)
                .contentShape(Rectangle())
                .onTapGesture { if info.photo != .empty { viewing = true } }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
    }
}

/// The numbers of a car as tiles: power, weight, the ratio and the year.
struct SpecGrid: View {
    let info: CarInfo

    var body: some View {
        let tiles = items
        if !tiles.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(tiles) { t in
                    StatTile(title: t.title, value: t.value, unit: t.unit, color: t.accent ? Theme.accent : Theme.text)
                }
            }
        }
    }

    private struct Item: Identifiable {
        var title: String
        var value: String
        var unit: String?
        var accent = false
        var id: String { title }
    }

    private var items: [Item] {
        var out: [Item] = []
        if let p = info.power { out.append(Item(title: L("Potenza"), value: Fmt.power(p), unit: Fmt.powerUnit, accent: true)) }
        if let w = info.weight { out.append(Item(title: L("Peso"), value: Fmt.weight(w), unit: Fmt.weightUnit)) }
        if let r = info.ratio { out.append(Item(title: L("Peso/potenza"), value: Fmt.ratio(r), unit: Fmt.ratioUnit)) }
        if let y = info.year { out.append(Item(title: L("Anno"), value: String(y), unit: nil)) }
        return out
    }
}

/// The modifications, numbered, in the order they were written.
struct ModsPanel: View {
    let mods: [String]

    var body: some View {
        Panel(padding: 6) {
            VStack(spacing: 0) {
                ForEach(Array(mods.enumerated()), id: \.offset) { i, mod in
                    HStack(alignment: .top, spacing: 12) {
                        Text(verbatim: "\(i + 1)")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                            .frame(width: 26, height: 26)
                            .background(Theme.accent.opacity(0.12), in: Circle())
                        Text(mod)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    if i < mods.count - 1 {
                        Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 0.5).padding(.leading, 48)
                    }
                }
            }
        }
    }
}

/// A photo full screen: pinch or double-tap to zoom, drag to look around, swipe down to close.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: CarPhoto
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            CarPhotoView(photo: photo, contentMode: .fit)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnify.simultaneously(with: drag))
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                    }
                }
                .ignoresSafeArea()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .environment(\.colorScheme, .dark)
            }
            .padding(16)
            .accessibilityLabel(L("Chiudi"))
        }
        .statusBarHidden()
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in scale = max(1, min(5, lastScale * v.magnification)) }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.01 { withAnimation(.spring) { reset() } }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { v in
                offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
            }
            .onEnded { v in
                if scale <= 1.01 {
                    if v.translation.height > 120 { dismiss() } else { withAnimation(.spring) { reset() } }
                } else {
                    lastOffset = offset
                }
            }
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}

/// The car you drive, from your garage: the next sessions remember it and your laps on the
/// leaderboards link to it. In Live and in Drag.
struct ActiveCarChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            if model.garage.cars.isEmpty {
                Button { model.tab = .garage } label: { Label("Aggiungi un'auto al garage", systemImage: "plus") }
            } else {
                Picker(L("Auto in uso"), selection: Binding(get: { model.activeCarID }, set: { model.setActiveCar($0) })) {
                    Text("Nessuna").tag(UUID?.none)
                    ForEach(model.garage.cars) { car in
                        Text(car.displayName).tag(UUID?.some(car.id))
                    }
                }
                Divider()
                Button { model.tab = .garage } label: { Label("Apri il garage", systemImage: "car.fill") }
            }
        } label: {
            HStack(spacing: 6) {
                if let car = model.activeCar {
                    CarPhotoView(photo: car.info.photo)
                        .frame(width: 20, height: 20)
                        .clipShape(Circle())
                    Text(car.displayName).lineLimit(1)
                } else {
                    Image(systemName: "car.fill").font(.caption2.weight(.bold)).foregroundStyle(Theme.sub)
                    Text("Scegli l'auto")
                }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.sub)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: 190, alignment: .leading)
            .padding(.leading, model.activeCar == nil ? 10 : 4)
            .padding(.trailing, 10)
            .padding(.vertical, model.activeCar == nil ? 6 : 3)
            .background(Theme.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(model.activeCar == nil ? Theme.line : Theme.accent.opacity(0.6), lineWidth: 1))
        }
        .accessibilityLabel(L("Auto in uso"))
    }
}
