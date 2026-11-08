import Foundation

/// The TrackLap server (server/ in the repository, a Cloudflare Worker): new live groups, the online
/// leaderboards, the accounts, the friends and the garages. `-server <url>` on the command line points the
/// app at another one.
enum Server {
    static var base: URL {
        URL(string: UserDefaults.standard.string(forKey: "server") ?? "https://tracklap.tbsgaming.win")!
    }

    enum Failure: LocalizedError {
        case offline, refused, signedOut, taken, wrongLogin, wrongPassword, badName, shortPassword, tooMany, notFound
        case friendsOnly, noInvite, cannotBefriend, notFriend, sessionsFriendsOnly

        var errorDescription: String? {
            switch self {
            case .offline: L("Il server di TrackLap non risponde: controlla la connessione e riprova.")
            case .refused: L("Il server ha rifiutato la richiesta.")
            case .signedOut: L("Sei uscito dall'account: accedi di nuovo.")
            case .taken: L("Questo nome utente è già preso: scegline un altro.")
            case .wrongLogin: L("Nome utente o password sbagliati.")
            case .wrongPassword: L("La password non è giusta.")
            case .badName: L("Il nome utente va da 3 a 20 caratteri: lettere, numeri, punto, trattino e trattino basso, senza spazi.")
            case .shortPassword: L("La password deve avere almeno 8 caratteri.")
            case .tooMany: L("Troppi tentativi: riprova tra qualche minuto.")
            case .notFound: L("Questo garage non esiste più, oppure è stato nascosto.")
            case .friendsOnly: L("Questo pilota mostra il garage solo ai suoi amici.")
            case .noInvite: L("Questo invito non vale più: chiedine uno nuovo a chi te lo ha mandato.")
            case .cannotBefriend: L("Non puoi accettare questo invito: è il tuo, oppure uno di voi ha già 200 amici.")
            case .notFriend: L("Non siete più amici.")
            case .sessionsFriendsOnly: L("Questo pilota mostra le sessioni solo ai suoi amici.")
            }
        }
    }

    // MARK: - Groups

    /// A new group: its five-letter code.
    static func createGroup() async throws -> String {
        struct Created: Decodable { var code: String }
        return try await send(request("v1/rooms", method: "POST"), as: Created.self).code
    }

    static func groupURL(_ code: String) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("v1/rooms/\(code)/ws"), resolvingAgainstBaseURL: false)!
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        return c.url!
    }

    // MARK: - Leaderboards

    /// The leaderboard of a track, found by its start line and the length of a lap. Signed in, your
    /// laps come back marked as yours.
    static func board(for track: Track, length: Double?, token: String?) async throws -> Leaderboard {
        guard let start = track.start else { return Leaderboard(track: nil, laps: []) }
        var c = URLComponents(url: base.appendingPathComponent("v1/boards"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.6f", start.mid.lat)),
            URLQueryItem(name: "lon", value: String(format: "%.6f", start.mid.lon)),
            URLQueryItem(name: "len", value: String(Int(length ?? 0))),
        ]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return try await send(req, as: Leaderboard.self)
    }

    /// A lap for the leaderboard: the server keeps it if it is your best there with that GPS, under
    /// your account's name and linked to the car, if that car is in your public garage.
    @discardableResult
    static func submit(_ lap: Lap, source: SourceKind, track: Track, car: UUID?, kind: VehicleKind, token: String) async throws -> Submitted {
        guard let start = track.start, source != .demo else { throw Failure.refused }
        struct Body: Encodable {
            struct T: Encodable { var name: String; var lat: Double; var lon: Double }
            var source: String
            var time, distance: Double
            var sectors: [Double]
            var date: Double
            var track: T
            var car: String?
            var kind: String
        }
        let body = Body(source: source.rawValue, time: lap.time, distance: lap.distance, sectors: lap.sectors,
                        date: (lap.startedAt.timeIntervalSince1970 * 1000).rounded(),
                        track: .init(name: track.name, lat: start.mid.lat, lon: start.mid.lon),
                        car: car?.uuidString, kind: kind.rawValue)
        return try await send(request("v1/laps", method: "POST", json: body, token: token), as: Submitted.self)
    }

    // MARK: - Accounts

    struct Account: Decodable {
        var id: String
        var name: String
        var garage: String?
    }

    struct SignedIn: Decodable {
        var token: String
        var account: Account
    }

    private struct Credentials: Encodable {
        var username: String
        var password: String
    }

    static func signUp(name: String, password: String) async throws -> SignedIn {
        try await send(request("v1/accounts", method: "POST", json: Credentials(username: name, password: password)), as: SignedIn.self) {
            switch $0 {
            case 409: return Failure.taken
            case 400: return Self.isValidName(name) ? Failure.shortPassword : Failure.badName
            case 429: return Failure.tooMany
            default: return nil
            }
        }
    }

    static func signIn(name: String, password: String) async throws -> SignedIn {
        try await send(request("v1/sessions", method: "POST", json: Credentials(username: name, password: password)), as: SignedIn.self) {
            switch $0 {
            case 403: return Failure.wrongLogin
            case 429: return Failure.tooMany
            default: return nil
            }
        }
    }

    static func signOut(token: String) async {
        _ = try? await send(request("v1/sessions", method: "DELETE", token: token), as: OK.self)
    }

    static func me(token: String) async throws -> Account {
        try await send(request("v1/me", token: token), as: Account.self)
    }

    static func changePassword(token: String, old: String, new: String) async throws -> SignedIn {
        struct Body: Encodable { var old: String; var new: String }
        return try await send(request("v1/me/password", method: "POST", json: Body(old: old, new: new), token: token), as: SignedIn.self) {
            switch $0 {
            case 403: return Failure.wrongPassword
            case 400: return Failure.shortPassword
            default: return nil
            }
        }
    }

    static func deleteAccount(token: String, password: String) async throws {
        struct Body: Encodable { var password: String }
        _ = try await send(request("v1/me", method: "DELETE", json: Body(password: password), token: token), as: OK.self) {
            $0 == 403 ? Failure.wrongPassword : nil
        }
    }

    static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9_.-]{3,20}$", options: .regularExpression) != nil
    }

    // MARK: - Garages

    /// Your garage's code, made the first time.
    static func openGarage(token: String) async throws -> String {
        struct Opened: Decodable { var code: String }
        return try await send(request("v1/me/garage", method: "POST", token: token), as: Opened.self).code
    }

    /// Your cars as they are now, for everyone ("all") or for your friends only ("friends"); the
    /// answer lists the photos the server does not have yet.
    static func putGarage(code: String, cars: [Car], audience: String, token: String) async throws -> [String] {
        struct Body: Encodable { var cars: [Car]; var audience: String }
        struct Answer: Decodable { var missing: [String] }
        return try await send(request("v1/garages/\(code)", method: "PUT", json: Body(cars: cars, audience: audience), token: token),
                              as: Answer.self).missing
    }

    static func putPhoto(code: String, photo: String, jpeg: Data, token: String) async throws {
        var req = request("v1/garages/\(code)/photos/\(photo)", method: "PUT", token: token)
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.httpBody = jpeg
        req.timeoutInterval = 60
        _ = try await send(req, as: OK.self)
    }

    static func garage(code: String, token: String?) async throws -> PublicGarage {
        try await send(request("v1/garages/\(code)", token: token), as: PublicGarage.self) {
            $0 == 404 ? Failure.notFound : $0 == 403 ? Failure.friendsOnly : nil
        }
    }

    /// Your sessions for everyone ("all") or for your friends only ("friends").
    static func putSessions(code: String, sessions: [SharedSession], audience: String, token: String) async throws {
        struct Body: Encodable { var sessions: [SharedSession]; var audience: String }
        var req = request("v1/garages/\(code)/sessions", method: "PUT", json: Body(sessions: sessions, audience: audience), token: token)
        req.timeoutInterval = 30
        _ = try await send(req, as: OK.self)
    }

    /// Your sessions no longer shown to anyone.
    static func deleteSessions(code: String, token: String) async throws {
        _ = try await send(request("v1/garages/\(code)/sessions", method: "DELETE", token: token), as: OK.self) { $0 == 404 ? Failure.notFound : nil }
    }

    /// Someone's shared sessions: none when they share none.
    static func sessions(code: String, token: String?) async throws -> SharedSessions {
        try await send(request("v1/garages/\(code)/sessions", token: token), as: SharedSessions.self) {
            $0 == 404 ? Failure.notFound : $0 == 403 ? Failure.sessionsFriendsOnly : nil
        }
    }

    static func report(code: String, car: String?, reason: String) async throws {
        struct Body: Encodable { var reason: String; var car: String? }
        _ = try await send(request("v1/garages/\(code)/report", method: "POST", json: Body(reason: reason, car: car)), as: OK.self)
    }

    static func photoURL(code: String, photo: String) -> URL {
        base.appendingPathComponent("v1/garages/\(code)/photos/\(photo)")
    }

    /// The page anyone can open, also without the app; with a car, it opens on that car.
    static func garageURL(code: String, car: String? = nil) -> URL {
        var c = URLComponents(url: base.appendingPathComponent("g/\(code)"), resolvingAgainstBaseURL: false)!
        c.fragment = car
        return c.url!
    }

    // MARK: - Friends

    /// Your invitation link's code: the same for a week; `renew` makes a new one, and the old one
    /// stops working.
    static func invite(token: String, renew: Bool = false) async throws -> FriendInvite {
        struct Body: Encodable { var renew: Bool }
        return try await send(request("v1/me/invite", method: "POST", json: Body(renew: renew), token: token), as: FriendInvite.self)
    }

    /// The page an invitation link opens, also without the app: who it is from, and a button for
    /// TrackLap (tracklap://friend/<code>).
    static func inviteURL(code: String) -> URL {
        base.appendingPathComponent("f/\(code)")
    }

    /// Who an invitation is from, while it is good.
    static func inviter(code: String) async throws -> String {
        struct From: Decodable { var name: String }
        return try await send(request("v1/invites/\(code)"), as: From.self) { $0 == 404 ? Failure.noInvite : nil }.name
    }

    /// An invitation accepted: you are friends both ways from now.
    static func accept(invite code: String, token: String) async throws -> Friend {
        struct Body: Encodable { var code: String }
        return try await send(request("v1/friends", method: "POST", json: Body(code: code), token: token), as: Friend.self) {
            switch $0 {
            case 404: return Failure.noInvite
            case 409: return Failure.cannotBefriend
            default: return nil
            }
        }
    }

    static func friends(token: String) async throws -> [Friend] {
        struct List: Decodable { var friends: [Friend] }
        return try await send(request("v1/friends", token: token), as: List.self).friends
    }

    /// A friend with their best laps and numbers; only while you are friends.
    static func friend(id: String, token: String) async throws -> FriendProfile {
        try await send(request("v1/friends/\(id)", token: token), as: FriendProfile.self) { $0 == 404 ? Failure.notFriend : nil }
    }

    /// This phone's token from Apple, so a friend accepting your invitation reaches it; tied to the
    /// session, signing out stops it.
    static func addDevice(token device: String, platform: String, account token: String) async throws {
        struct Body: Encodable { var token: String; var platform: String }
        _ = try await send(request("v1/me/push", method: "PUT", json: Body(token: device, platform: platform), token: token), as: OK.self)
    }

    /// No longer friends, for both.
    static func removeFriend(id: String, token: String) async throws {
        _ = try await send(request("v1/friends/\(id)", method: "DELETE", token: token), as: OK.self) { $0 == 404 ? Failure.notFriend : nil }
    }

    // MARK: - Plumbing

    private struct OK: Decodable {}

    private static func request(_ path: String, method: String = "GET", token: String? = nil) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 15
        if let token { req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return req
    }

    private static func request(_ path: String, method: String, json: some Encodable, token: String? = nil) -> URLRequest {
        var req = request(path, method: method, token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(json)
        return req
    }

    /// Sends and decodes; `failure` turns an HTTP status into a more precise error.
    private static func send<T: Decodable>(_ req: URLRequest, as type: T.Type,
                                           failure: (Int) -> Failure? = { _ in nil }) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Failure.offline
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.refused }
        guard (200..<300).contains(http.statusCode) else {
            if let f = failure(http.statusCode) { throw f }
            throw http.statusCode == 401 ? Failure.signedOut : http.statusCode == 429 ? Failure.tooMany : Failure.refused
        }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { throw Failure.refused }
        return value
    }
}

struct Leaderboard: Decodable {
    struct BoardTrack: Decodable {
        var id: String
        var name: String
    }

    struct Entry: Decodable, Identifiable {
        var rank: Int
        var name: String
        var vehicle: String
        /// The driver's garage and the car of this lap, when they show it.
        var garage: String?
        var car: String?
        var source: String
        var time: Double
        /// Milliseconds since 1970.
        var date: Double
        var mine: Bool
        /// "car", "motorcycle" or "scooter"; nil for laps from before 0.10.0.
        var vehicleKind: VehicleKind?

        enum CodingKeys: String, CodingKey {
            case rank, name, vehicle, garage, car, source, time, date, mine
            case vehicleKind = "kind"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            rank = try c.decode(Int.self, forKey: .rank)
            name = try c.decode(String.self, forKey: .name)
            vehicle = try c.decode(String.self, forKey: .vehicle)
            garage = try c.decodeIfPresent(String.self, forKey: .garage)
            car = try c.decodeIfPresent(String.self, forKey: .car)
            source = try c.decode(String.self, forKey: .source)
            time = try c.decode(Double.self, forKey: .time)
            date = try c.decode(Double.self, forKey: .date)
            mine = try c.decode(Bool.self, forKey: .mine)
            vehicleKind = (try? c.decodeIfPresent(String.self, forKey: .vehicleKind)).flatMap { VehicleKind(rawValue: $0) }
        }

        var id: String { source + String(rank) }
        var day: Date { Date(timeIntervalSince1970: date / 1000) }
        var kind: SourceKind? { SourceKind(rawValue: source) }

        var carLink: GarageLink? {
            guard let garage, !garage.isEmpty else { return nil }
            return GarageLink(code: garage, car: car?.isEmpty == false ? car : nil)
        }
    }

    var track: BoardTrack?
    var laps: [Entry]
}

struct Submitted: Decodable {
    var rank: Int
    var of: Int
}

/// A public garage to open, on one of its cars or on the whole garage.
struct GarageLink: Identifiable, Hashable {
    var code: String
    var car: String?

    var id: String { code + "/" + (car ?? "") }

    /// tracklap://garage/<code>[/<car>], from the garage page's button.
    init?(url: URL) {
        guard url.scheme == "tracklap", url.host == "garage" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let code = parts.first?.uppercased(), code.count == 8 else { return nil }
        self.init(code: code, car: parts.count > 1 ? parts[1] : nil)
    }

    init(code: String, car: String?) {
        self.code = code
        self.car = car
    }
}
