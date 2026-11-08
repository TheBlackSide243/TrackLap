import Foundation
import Observation

/// Who sees your sessions in your garage, apart from who sees the cars.
enum SessionAudience: String, CaseIterable, Identifiable {
    case nobody, friends, everyone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nobody: L("Nessuno")
        case .friends: L("Solo amici")
        case .everyone: L("Tutti")
        }
    }

    var summary: String {
        switch self {
        case .nobody: L("Le sessioni restano su questo telefono.")
        case .friends: L("I tuoi amici vedono pista, data e tempi di ogni sessione.")
        case .everyone: L("Chiunque apra il tuo garage vede pista, data e tempi di ogni sessione.")
        }
    }
}

/// A session as it goes to the server: where, when, the lap times and what it was driven with.
/// No traces and no positions: those stay on the phone.
struct SharedSession: Codable, Identifiable, Hashable {
    var id: String
    var track: String
    /// Milliseconds since 1970.
    var date: Double
    var laps: [Double]
    var best: Double?
    var car: String?
    var kind: String?
    /// "device" or "phone".
    var source: String

    var day: Date { Date(timeIntervalSince1970: date / 1000) }
    var vehicle: VehicleKind { VehicleKind(rawValue: kind ?? "") ?? .car }
}

/// Someone's shared sessions as the server sends them.
struct SharedSessions: Decodable {
    var code: String
    var name: String
    var audience: String
    var sessions: [SharedSession]
    var mine: Bool?
}

/// Your sessions in your garage on the server, for everyone or for your friends: the list goes up a
/// moment after a session is saved or deleted. Set to nobody, the list is removed from the server.
@Observable
final class SharedSessionStore {
    private(set) var audience: SessionAudience
    private(set) var sync: GarageStore.SyncState = .idle

    @ObservationIgnored var account: AccountStore?
    @ObservationIgnored var sessions: SessionStore?
    @ObservationIgnored var garage: GarageStore?
    @ObservationIgnored private var pending: Task<Void, Never>?

    /// What the server takes, with some room for the rest of the request.
    static let maxSessions = 300
    static let maxLaps = 200
    static let maxBytes = 240_000

    init() {
        audience = SessionAudience(rawValue: UserDefaults.standard.string(forKey: "sessionAudience") ?? "") ?? .nobody
    }

    func setAudience(_ a: SessionAudience) {
        let was = audience
        audience = a
        UserDefaults.standard.set(a.rawValue, forKey: "sessionAudience")
        if a != was { publishSoon(now: true) }
    }

    func accountChanged() {
        sync = .idle
        publishSoon(now: true)
    }

    /// Sessions are saved after every lap: one upload a while after the last.
    func publishSoon(now: Bool = false) {
        guard Edition.online else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            if !now { try? await Task.sleep(for: .seconds(10)) }
            guard !Task.isCancelled else { return }
            await self?.publish()
        }
    }

    @MainActor
    func publish() async {
        if Showcase.screen != nil {
            sync = .done(Date())
            return
        }
        guard let account, account.isSignedIn, let token = account.token else {
            sync = .idle
            return
        }
        // Never shared and nothing to take down.
        guard audience != .nobody || UserDefaults.standard.bool(forKey: "sessionsShared") else {
            sync = .idle
            return
        }
        sync = .syncing
        do {
            let code = try await account.garageCode()
            if audience == .nobody {
                try await Server.deleteSessions(code: code, token: token)
                UserDefaults.standard.set(false, forKey: "sessionsShared")
            } else {
                let list = shared()
                try await Server.putSessions(code: code, sessions: list, audience: audience == .friends ? "friends" : "all", token: token)
                UserDefaults.standard.set(true, forKey: "sessionsShared")
            }
            sync = .done(Date())
        } catch Server.Failure.signedOut {
            account.signedOutElsewhere()
            sync = .failed(Server.Failure.signedOut.localizedDescription)
        } catch {
            guard !Task.isCancelled else { return }
            sync = .failed(error.localizedDescription)
        }
    }

    /// The newest sessions driven for real, as many as fit in one request.
    private func shared() -> [SharedSession] {
        guard let sessions else { return [] }
        var list: [SharedSession] = sessions.withLapTimes().compactMap { s in
            let source = SourceKind(sessionSource: s.source)
            guard source != .demo, let times = s.lapTimes, !times.isEmpty else { return nil }
            let laps = times.prefix(Self.maxLaps).map { ($0 * 1000).rounded() / 1000 }
            // The car's name only when the garage is shown: a hidden garage keeps it to itself.
            let car = garage?.isShown == true ? s.carName : nil
            return SharedSession(id: s.id.uuidString, track: String(s.trackName.prefix(60)),
                                 date: (s.date.timeIntervalSince1970 * 1000).rounded(), laps: Array(laps),
                                 best: laps.min(), car: car.map { String($0.prefix(40)) },
                                 kind: s.vehicle.rawValue, source: source == .device ? "device" : "phone")
        }
        list.sort { $0.date > $1.date }
        if list.count > Self.maxSessions { list = Array(list.prefix(Self.maxSessions)) }
        let encoder = JSONEncoder()
        while list.count > 1, let data = try? encoder.encode(list), data.count > Self.maxBytes {
            list.removeLast(max(1, list.count / 10))
        }
        return list
    }
}
