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

    /// Once, on the first launch, and again from Device; in screenshot mode only for its own screen.
    private var showIntro: Bool {
        Showcase.screen == nil ? !introSeen : Showcase.screen == .intro
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            LiveView()
                .id(model.units)
                .tabItem { Label("Live", systemImage: "stopwatch.fill") }
                .tag(AppTab.live)
            TracksView()
                .id(model.units)
                .tabItem { Label("Piste", systemImage: "map.fill") }
                .tag(AppTab.tracks)
            SessionsView()
                .id(model.units)
                .tabItem { Label("Sessioni", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.sessions)
            DeviceView()
                .tabItem { Label("Dispositivo", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(AppTab.device)
        }
        .task { model.runShowcase() }
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
