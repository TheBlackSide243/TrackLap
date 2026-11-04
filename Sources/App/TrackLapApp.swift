import SwiftUI
import UIKit

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
    @State private var keyboardUp = false
    /// Signing in for a group invitation that came in without an account.
    @State private var inviteSignIn = false

    /// Once, on the first launch, and again from Device; in screenshot mode only for its own screen.
    private var showIntro: Bool {
        Showcase.screen == nil ? !introSeen : Showcase.screen == .intro
    }

    var body: some View {
        @Bindable var model = model
        GeometryReader { geo in
            let layout = SideTabsLayout(place: tabbarPlace, size: geo.size, insets: geo.safeAreaInsets)
            let edges: Edge.Set = layout.side ? .trailing : (keyboardUp ? [] : .bottom)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    tabs
                    // Hidden while typing, so it does not ride up on the keyboard.
                    if !layout.side && !keyboardUp {
                        BottomTabBar(tab: $model.tab, bottomInset: geo.safeAreaInsets.bottom)
                    }
                }
                if layout.side {
                    SideTabBar(tab: $model.tab, layout: layout, insets: geo.safeAreaInsets)
                }
            }
            .ignoresSafeArea(edges: edges)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardUp = false }
        .task { model.runShowcase() }
        .task {
            await model.account.refresh()
            model.garage.publishSoon(now: true)
        }
        .sheet(item: $model.shownGarage) { link in
            PublicGarageView(link: link)
                .environment(model)
        }
        .sheet(isPresented: Binding(get: { model.importedSetup != nil }, set: { if !$0 { model.importedSetup = nil } })) {
            if let shared = model.importedSetup {
                SetupImportSheet(shared: shared).environment(model)
            }
        }
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
        // Groups need an account: an invitation opened while signed out asks first, then joins.
        .alert(L("Serve un account"),
               isPresented: Binding(get: { model.pendingJoin != nil && !model.account.isSignedIn && !inviteSignIn }, set: { _ in })) {
            Button(L("Accedi o crea un account")) { inviteSignIn = true }
            Button(L("Annulla"), role: .cancel) { model.pendingJoin = nil }
        } message: {
            Text(L("Ti hanno invitato nel gruppo \(model.pendingJoin ?? ""). Accedi o crea un account e ci entri subito."))
        }
        .sheet(isPresented: $inviteSignIn, onDismiss: { if !model.account.isSignedIn { model.pendingJoin = nil } }) {
            AccountSheet().environment(model)
        }
        .onChange(of: model.account.isSignedIn) { _, on in
            if on { model.joinPending() }
        }
        .fullScreenCover(isPresented: Binding(get: { showIntro }, set: { if !$0 { introSeen = true } })) {
            IntroView { introSeen = true }
                .environment(model)
        }
    }

    /// The six tabs in a TabView of five, its bar always hidden: the app draws its own. With six,
    /// an iPhone's TabView moves the last ones into a hidden "More" tab, with a back button of its
    /// own above them; so Garage and Device share the fifth, one above the other. The TabView keeps
    /// each tab with its navigation and pauses the ones not shown (Live's clock among them).
    private var tabs: some View {
        TabView(selection: Binding(get: { Self.systemTab(model.tab) }, set: { _ in })) {
            LiveView().id(model.units).toolbar(.hidden, for: .tabBar).tag(AppTab.live)
            DragView().id(model.units).toolbar(.hidden, for: .tabBar).tag(AppTab.drag)
            TracksView().id(model.units).toolbar(.hidden, for: .tabBar).tag(AppTab.tracks)
            SessionsView().id(model.units).toolbar(.hidden, for: .tabBar).tag(AppTab.sessions)
            ZStack {
                shared(.garage) { GarageView().id(model.units) }
                shared(.device) { DeviceView() }
            }
            .toolbar(.hidden, for: .tabBar)
            .tag(AppTab.garage)
        }
    }

    /// The TabView tab an app tab is in: Device is in Garage's.
    private static func systemTab(_ t: AppTab) -> AppTab { t == .device ? .garage : t }

    private func shared<Content: View>(_ tab: AppTab, @ViewBuilder _ content: () -> Content) -> some View {
        let shown = model.tab == tab
        return content()
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .accessibilityHidden(!shown)
            .zIndex(shown ? 1 : 0)
    }

    /// An invitation to a group (tracklap://join/…) or a .tracklap file from a friend.
    private func open(_ url: URL) {
        if model.open(url) { return }
        guard url.isFileURL else { return }
        if url.pathExtension.lowercased() == "tracklapsetup" {
            do {
                model.importedSetup = try SharedSetup.read(url)
            } catch {
                importError = error.localizedDescription
            }
            return
        }
        do {
            imported = try model.importLap(from: url)
        } catch {
            importError = error.localizedDescription
        }
    }
}
