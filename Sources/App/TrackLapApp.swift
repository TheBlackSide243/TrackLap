import SwiftUI

@main
struct TrackLapApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("introSeen") private var introSeen = false
    @State private var imported: FriendLap?
    @State private var importError: String?
    @AppStorage(TabbarPlace.key) private var tabbarPlace: TabbarPlace = .auto

    /// Once, on the first launch, and again from Device; in screenshot mode only for its own screen.
    private var showIntro: Bool {
        Showcase.screen == nil ? !introSeen : Showcase.screen == .intro
    }

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let layout = SideTabsLayout(place: tabbarPlace, size: geo.size, insets: geo.safeAreaInsets)
            HStack(spacing: 0) {
                tabs(hideBar: layout.side)
                if layout.side {
                    SideTabBar(tab: $model.tab, layout: layout, insets: geo.safeAreaInsets)
                }
            }
            .ignoresSafeArea(edges: layout.side ? .trailing : [])
        }
        .background(Theme.bg.ignoresSafeArea())
        .task { model.runShowcase() }
        .onChange(of: model.tab) { _, tab in model.setDragMode(tab == .drag) }
        .onOpenURL(perform: open)
        .alert(L("Giro di un amico"), isPresented: Binding(get: { imported != nil }, set: { if !$0 { imported = nil } }),
               presenting: imported) { f in
            Button(L("Sfidalo in Live")) { model.chase(f) }
            Button("OK", role: .cancel) {}
        } message: { f in
            Text(L("\(f.driver): \(Fmt.lap(f.time)) a \(f.trackName). Lo trovi anche in Sessioni → Giri degli amici."))
        }
        .alert(importError ?? "", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .fullScreenCover(isPresented: Binding(get: { showIntro }, set: { if !$0 { introSeen = true } })) {
            IntroView { introSeen = true }
                .environment(model)
        }
    }

    /// The five tabs; beside a SideTabBar the system's bar at the bottom is hidden. Hidden, not
    /// removed, so each tab keeps its place and navigation when the phone turns.
    private func tabs(hideBar: Bool) -> some View {
        @Bindable var model = model
        let bar: Visibility = hideBar ? .hidden : .automatic
        return TabView(selection: $model.tab) {
            LiveView()
                .id(model.units)
                .toolbar(bar, for: .tabBar)
                .tabItem { Label("Live", systemImage: "stopwatch.fill") }
                .tag(AppTab.live)
            DragView()
                .id(model.units)
                .toolbar(bar, for: .tabBar)
                .tabItem { Label("Drag", systemImage: "speedometer") }
                .tag(AppTab.drag)
            TracksView()
                .id(model.units)
                .toolbar(bar, for: .tabBar)
                .tabItem { Label("Piste", systemImage: "map.fill") }
                .tag(AppTab.tracks)
            SessionsView()
                .id(model.units)
                .toolbar(bar, for: .tabBar)
                .tabItem { Label("Sessioni", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.sessions)
            DeviceView()
                .toolbar(bar, for: .tabBar)
                .tabItem { Label("Dispositivo", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AppTab.device)
        }
    }

    /// An invitation to a group (tracklap://join/…) or a .tracklap file from a friend.
    private func open(_ url: URL) {
        if model.open(url) { return }
        guard url.isFileURL else { return }
        do {
            imported = try model.importLap(from: url)
        } catch {
            importError = error.localizedDescription
        }
    }
}
