import CallKit
import SwiftUI
import UIKit

/// Where the tabs stand (Device → Tab bar). Automatic, the default, puts them in a column on the
/// right edge when the screen is wider than it is tall and narrower than an iPad's (an iPhone on
/// its side in the car mount, the iPhone Duo opened), and in the closed Duo's status column; at the
/// bottom otherwise. The right edge whatever the language: it is where the thumb holding the phone is.
enum TabbarPlace: String, CaseIterable, Identifiable {
    case auto, bottom, right

    var id: String { rawValue }

    static let key = "tabbarPlace"

    var title: String {
        switch self {
        case .auto: L("Automatica")
        case .bottom: L("In basso")
        case .right: L("A destra")
        }
    }
}

/// How the tab column fits the screen, from its full size and its safe-area insets.
struct SideTabsLayout {
    /// A right inset this wide is not a camera cutout (an iPhone on its side keeps about 60 pt
    /// there): it is the column the iPhone Duo's closed screen writes the time and the battery in
    /// (about 80 pt, the status block about 150 pt tall). The tabs are then that column, their icons
    /// below the status block, instead of a bar beside it.
    static let statusColumnMin: CGFloat = 70

    let side: Bool
    let statusColumn: Bool
    let width: CGFloat
    /// The icons alone: a phone on its side is short.
    let compact: Bool

    init(place: TabbarPlace, size: CGSize, insets: EdgeInsets) {
        let full = CGSize(width: size.width + insets.leading + insets.trailing,
                          height: size.height + insets.top + insets.bottom)
        let wide = full.width >= full.height && full.width < 1000
        let status = insets.trailing >= Self.statusColumnMin
        side = place == .right || (place == .auto && (wide || status))
        statusColumn = side && status
        width = statusColumn ? max(84, insets.trailing) : 76 + insets.trailing
        compact = full.height < 480
    }
}

/// The tabs as a column on the right edge, in place of the bar at the bottom.
struct SideTabBar: View {
    @Binding var tab: AppTab
    let layout: SideTabsLayout
    let insets: EdgeInsets
    let islandTall: Bool

    static let tabs: [(tab: AppTab, title: LocalizedStringKey, symbol: String)] = [
        (.live, "Live", "stopwatch.fill"),
        (.drag, "Drag", "speedometer"),
        (.tracks, "Piste", "map.fill"),
        (.sessions, "Sessioni", "chart.bar.xaxis"),
        (.device, "Dispositivo", "antenna.radiowaves.left.and.right"),
    ]

    /// In the status column the icons start below the time, the battery and the front camera, whose
    /// ring ends about 166 pt down on the closed Duo (measured on the user's screenshot), lower still
    /// while the island is taller (a call, the screen being recorded).
    private var top: CGFloat {
        guard layout.statusColumn else { return insets.top + 8 }
        return max(insets.top + 8, islandTall ? 288 : 184)
    }

    var body: some View {
        VStack(spacing: layout.compact || islandTall ? 0 : 4) {
            if !layout.statusColumn { Spacer(minLength: 0) }
            ForEach(Self.tabs, id: \.tab) { item in
                Button {
                    tab = item.tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20))
                            .frame(height: 24)
                        if !layout.compact {
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .foregroundStyle(tab == item.tab ? Theme.accent : Theme.sub)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, layout.compact || islandTall ? 6 : 8)
                    .background(tab == item.tab ? Theme.button : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item.tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.top, top)
        .padding(.bottom, insets.bottom + 8)
        .padding(.leading, 4)
        .padding(.trailing, layout.statusColumn ? 4 : insets.trailing + 4)
        .frame(width: layout.width)
        .frame(maxHeight: .infinity)
        .background(Theme.bg)
        .overlay(alignment: .leading) {
            if !layout.statusColumn { Rectangle().fill(Theme.line.opacity(0.6)).frame(width: 0.5) }
        }
        .animation(.easeOut(duration: 0.3), value: islandTall)
    }
}

/// Whether the island is taller than usual, which pushes the closed Duo's time and battery down.
/// iOS does not say how tall the island is, nor what another app shows in it, but two of the
/// reasons it grows it does tell: the screen being recorded and a call going on, a phone call or
/// any app's (CallKit).
@Observable
final class IslandWatch: NSObject, CXCallObserverDelegate {
    private(set) var tall = false
    @ObservationIgnored private let calls = CXCallObserver()

    override init() {
        super.init()
        calls.setDelegate(self, queue: .main)
        for name in [UIScreen.capturedDidChangeNotification, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(update), name: name, object: nil)
        }
        update()
    }

    @objc func update() {
        let recording = UIApplication.shared.connectedScenes.contains {
            ($0 as? UIWindowScene)?.traitCollection.sceneCaptureState == .active
        }
        let now = recording || calls.calls.contains { !$0.hasEnded }
        if now != tall { tall = now }
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) { update() }
}
