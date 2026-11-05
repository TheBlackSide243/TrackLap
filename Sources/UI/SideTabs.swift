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
    /// (about 80 pt). The tabs are then that column, below the status block, instead of a bar
    /// beside it.
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

    static let tabs: [(tab: AppTab, title: LocalizedStringKey, symbol: String)] = [
        (.live, "Live", "stopwatch.fill"),
        (.drag, "Drag", "speedometer"),
        (.tracks, "Piste", "map.fill"),
        (.sessions, "Sessioni", "chart.bar.xaxis"),
        (.garage, "Garage", "car.fill"),
        (.friends, "Amici", "person.2.fill"),
        (.device, "Dispositivo", "antenna.radiowaves.left.and.right"),
    ]

    /// In the closed Duo's status column the tabs stand at the bottom, as the Home screen's dock
    /// does there, and never above this. Above them the system writes the time and the battery
    /// around the front camera, and the whole block moves down when the island grows: about
    /// 166 pt down normally, 202 pt with another app's activity in the island (both measured on
    /// the user's screenshots). iOS tells an app neither how tall the island is nor what another
    /// app shows in it, so the tabs keep clear of it from below instead of guessing.
    static let statusBlockClearance: CGFloat = 224

    var body: some View {
        VStack(spacing: layout.compact ? 0 : 4) {
            Spacer(minLength: layout.statusColumn ? Self.statusBlockClearance : 0)
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
                    .padding(.vertical, layout.compact ? 6 : 8)
                    .background(tab == item.tab ? Theme.button : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item.tab ? .isSelected : [])
            }
            if !layout.statusColumn { Spacer(minLength: 0) }
        }
        .padding(.top, insets.top + 8)
        .padding(.bottom, insets.bottom + (layout.statusColumn ? 16 : 8))
        .padding(.leading, 4)
        .padding(.trailing, layout.statusColumn ? 4 : insets.trailing + 4)
        .frame(width: layout.width)
        .frame(maxHeight: .infinity)
        .background(Theme.bg)
        .overlay(alignment: .leading) {
            if !layout.statusColumn { Rectangle().fill(Theme.line.opacity(0.6)).frame(width: 0.5) }
        }
    }
}

/// The seven tabs along the bottom: the system's bar shows five on an iPhone and puts the rest under
/// "More", so the app draws its own, in the same style as the column on the right.
struct BottomTabBar: View {
    @Binding var tab: AppTab
    let bottomInset: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SideTabBar.tabs, id: \.tab) { item in
                let selected = tab == item.tab
                Button {
                    if tab != item.tab { UISelectionFeedbackGenerator().selectionChanged() }
                    tab = item.tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 19, weight: selected ? .semibold : .regular))
                            .frame(height: 24)
                            .symbolEffect(.bounce, value: selected)
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .foregroundStyle(selected ? Theme.accent : Theme.sub)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7)
                    .padding(.bottom, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, max(bottomInset, 6))
        .background(Theme.bg.opacity(0.97))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 0.5) }
    }
}
