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
        .fullScreenCover(isPresented: Binding(get: { showIntro }, set: { if !$0 { introSeen = true } })) {
            IntroView { introSeen = true }
                .environment(model)
        }
    }
}
