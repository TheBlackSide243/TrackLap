import Foundation

/// Which of the two apps this is. TrackLap Lite, the free one, is built from the same sources with
/// LITE (project.yml, target TrackLapLite): Live, Drag, Tracks, Sessions and Device, everything on
/// the phone. The full TrackLap adds what goes through the server: the account, friends, the online
/// leaderboards, live groups, the garage with its vehicles and setups, and shared sessions.
enum Edition {
    #if LITE
    static let isLite = true
    #else
    static let isLite = false
    #endif

    /// Accounts, friends, leaderboards, groups, the garage and sharing.
    static var online: Bool { !isLite }
}
