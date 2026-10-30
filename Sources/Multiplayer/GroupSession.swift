import Foundation
import Observation

/// Where a member is, about once a second.
struct GroupPosition: Equatable {
    var coord: Coord
    /// The lap in progress, 0 while not timing.
    var lap: Int
    /// Metres into the lap.
    var distance: Double
    var speed: Double
    /// UTC of the fix in seconds since 1970: GPS time for the ESP32, so two cars compare to the hundredth.
    var utc: Double
    var received: Date
}

/// The track a member is on, by the middle of its start line.
struct GroupTrack: Codable, Equatable {
    var name: String
    var lat: Double
    var lon: Double

    init?(_ t: Track?) {
        guard let t, let s = t.start else { return nil }
        name = t.name
        lat = s.mid.lat
        lon = s.mid.lon
    }

    func isSame(as o: GroupTrack?) -> Bool {
        guard let o else { return false }
        return Geo.distance(Coord(lat, lon), Coord(o.lat, o.lon)) < 300
    }
}

struct GroupMember: Identifiable, Equatable {
    let id: String
    var name: String
    var vehicle: String
    var track: GroupTrack?
    var best: Double?
    var last: Double?
    var laps: Int
    var online: Bool
    /// Index in the group palette, kept for as long as you are in the group.
    var color: Int
    var position: GroupPosition? = nil
    /// When their last lap came in, to light up their row.
    var lapAt: Date? = nil

    var isMoving: Bool {
        guard let p = position else { return false }
        return Date().timeIntervalSince(p.received) < 5 && p.speed > 3
    }
}

/// A row of the group's standings: a member, or you.
struct Standing: Identifiable {
    let id: String
    let name: String
    let vehicle: String
    let best: Double?
    let last: Double?
    let laps: Int
    let online: Bool
    let moving: Bool
    let color: Int?
    let isMe: Bool
    let lapAt: Date?
}

/// The car just ahead of you or just behind on the track, and how many seconds apart you are.
struct TrackGap {
    let name: String
    let seconds: Double
    let color: Int
}

/// A live group on the TrackLap server: who is in it with their best and last lap, where each car is,
/// and your place. The phones time their own laps as always; this only shares them. Messages are the
/// ones of server/src/index.js.
@Observable
final class GroupSession {
    enum Status: Equatable { case off, connecting, live, waiting }

    private(set) var status: Status = .off
    private(set) var code: String? = nil
    /// The others in the group.
    private(set) var members: [GroupMember] = []
    private(set) var problem: String? = nil
    /// Your own times in this group on this track.
    private(set) var mine = Mine()

    struct Mine: Codable, Equatable {
        var track: GroupTrack? = nil
        var best: Double? = nil
        var last: Double? = nil
        var laps = 0
    }

    /// The standings or the group changed: the ESP32's screen shows your place.
    @ObservationIgnored var onStandingsChange: (() -> Void)? = nil

    private let profile: DriverProfile
    @ObservationIgnored private var memberID = ""
    @ObservationIgnored private var task: URLSessionWebSocketTask? = nil
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var retries = 0
    @ObservationIgnored private var lastReport = 0.0
    @ObservationIgnored private var history: [String: [GroupPosition]] = [:]
    @ObservationIgnored private var myHistory: [GroupPosition] = []
    @ObservationIgnored private var colors: [String: Int] = [:]
    @ObservationIgnored private var pinger: Timer? = nil

    private static let codeKey = "group.code"
    private static let memberKey = "group.member"
    private static let mineKey = "group.mine"
    private static let keep: TimeInterval = 300

    init(profile: DriverProfile) {
        self.profile = profile
    }

    var isOn: Bool { code != nil }

    /// Back in the group you were in when the app was closed.
    func resume(on track: Track?) {
        let d = UserDefaults.standard
        guard let code = d.string(forKey: Self.codeKey), let member = d.string(forKey: Self.memberKey) else { return }
        self.code = code
        memberID = member
        if let data = d.data(forKey: Self.mineKey), let m = try? JSONDecoder().decode(Mine.self, from: data) { mine = m }
        setTrack(track)
        connect()
    }

    /// A new group on the server, joined at once.
    func create(on track: Track?) async throws {
        let code = try await Server.createGroup()
        join(code, on: track)
    }

    func join(_ raw: String, on track: Track?) {
        let code = Self.clean(raw)
        guard code.count == 5 else {
            problem = L("Il codice del gruppo ha cinque caratteri.")
            return
        }
        close()
        self.code = code
        memberID = UUID().uuidString
        mine = Mine(track: GroupTrack(track))
        problem = nil
        let d = UserDefaults.standard
        d.set(code, forKey: Self.codeKey)
        d.set(memberID, forKey: Self.memberKey)
        saveMine()
        connect()
    }

    func leave() {
        close()
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.codeKey)
        d.removeObject(forKey: Self.memberKey)
        d.removeObject(forKey: Self.mineKey)
        onStandingsChange?()
    }

    /// Letters and digits of a code as typed, in capitals; O and I read as 0 and 1 are not in codes.
    static func clean(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(5))
    }

    static func inviteURL(_ code: String) -> URL { URL(string: "tracklap://join/\(code)")! }

    // MARK: - Your side

    /// The track you time on: the group compares you with those on the same one.
    func setTrack(_ t: Track?) {
        let g = GroupTrack(t)
        if let g, g.isSame(as: mine.track) {
            mine.track = g
            return
        }
        mine = Mine(track: g)
        myHistory = []
        saveMine()
        if status == .live { sendHello() }
        onStandingsChange?()
    }

    /// Your name or vehicle changed.
    func profileChanged() {
        if status == .live { sendHello() }
    }

    /// Every fix: kept for the gaps on track, sent to the others once a second.
    func report(_ s: Sample, lap: Int, distance: Double) {
        guard code != nil else { return }
        let utc = s.utc ?? s.wall.timeIntervalSince1970
        let p = GroupPosition(coord: s.coord, lap: lap, distance: distance, speed: s.speed, utc: utc, received: Date())
        if let last = myHistory.last, abs(utc - last.utc) < 0.5 {} else { Self.remember(p, in: &myHistory) }
        guard status == .live, abs(utc - lastReport) >= 1 else { return }
        lastReport = utc
        send(PosWire(lat: s.coord.lat, lon: s.coord.lon, lap: lap, d: distance, v: s.speed, g: utc))
    }

    func finished(_ lap: Lap) {
        guard code != nil else { return }
        mine.last = lap.time
        mine.best = min(mine.best ?? .infinity, lap.time)
        mine.laps += 1
        saveMine()
        if status == .live { send(LapWire(n: lap.number, time: lap.time)) }
        onStandingsChange?()
    }

    // MARK: - Standings

    private func sameTrack(_ m: GroupMember) -> Bool {
        guard let t = mine.track else { return m.track == nil }
        return t.isSame(as: m.track)
    }

    /// Everyone on your track, fastest best lap first, then those still without a lap.
    var standings: [Standing] {
        var rows = members.filter(sameTrack).map {
            Standing(id: $0.id, name: $0.name, vehicle: $0.vehicle, best: $0.best, last: $0.last, laps: $0.laps,
                     online: $0.online, moving: $0.isMoving, color: $0.color, isMe: false, lapAt: $0.lapAt)
        }
        rows.append(Standing(id: memberID, name: profile.displayName, vehicle: profile.displayVehicle, best: mine.best,
                             last: mine.last, laps: mine.laps, online: true, moving: false, color: nil, isMe: true, lapAt: nil))
        return rows.sorted { a, b in
            switch (a.best, b.best) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.name.localizedCompare(b.name) == .orderedAscending
            }
        }
    }

    /// The members on another track.
    var elsewhere: [GroupMember] { members.filter { !sameTrack($0) } }

    /// Your place among those with a lap and the gap to the one just ahead; when first, the margin
    /// over the second (negative).
    var place: (position: Int, count: Int, gap: Double, rival: String)? {
        let ranked = standings.filter { $0.best != nil }
        guard ranked.count > 1, let i = ranked.firstIndex(where: \.isMe), let best = ranked[i].best else { return nil }
        let other = ranked[i == 0 ? 1 : i - 1]
        return (i + 1, ranked.count, best - (other.best ?? best), other.name)
    }

    /// The cars just ahead and just behind on the track, and how far apart in time you are at the
    /// same point of it: the moment each of you passed there, by the GPS clocks.
    func trackGaps(lapLength length: Double) -> (ahead: TrackGap?, behind: TrackGap?) {
        let now = Date()
        guard length > 200, let me = myHistory.last, me.lap > 0, now.timeIntervalSince(me.received) < 5 else { return (nil, nil) }
        var ahead: (d: Double, gap: TrackGap)? = nil
        var behind: (d: Double, gap: TrackGap)? = nil
        for m in members where m.online && sameTrack(m) {
            guard let p = m.position, p.lap > 0, now.timeIntervalSince(p.received) < 5 else { continue }
            var a = (p.distance - me.distance).truncatingRemainder(dividingBy: length)
            if a < 0 { a += length }
            if a < length / 2 {
                guard let t = Self.time(at: me.distance, in: history[m.id] ?? [], length: length) else { continue }
                let gap = me.utc - t
                if gap > 0, gap < 600, ahead == nil || a < ahead!.d {
                    ahead = (a, TrackGap(name: m.name, seconds: gap, color: m.color))
                }
            } else {
                guard let t = Self.time(at: p.distance, in: myHistory, length: length) else { continue }
                let gap = p.utc - t
                if gap > 0, gap < 600, behind == nil || length - a < behind!.d {
                    behind = (length - a, TrackGap(name: m.name, seconds: gap, color: m.color))
                }
            }
        }
        return (ahead?.gap, behind?.gap)
    }

    /// When a car last passed a point `x` metres into the lap, between the two positions around it.
    static func time(at x: Double, in h: [GroupPosition], length: Double) -> Double? {
        guard h.count > 1 else { return nil }
        for i in stride(from: h.count - 1, to: 0, by: -1) {
            let a = h[i - 1]
            let b = h[i]
            guard a.lap > 0, b.lap > 0 else { continue }
            var db = b.distance
            if b.lap == a.lap + 1 { db += length } else if b.lap != a.lap { continue }
            var target = x
            if target < a.distance { target += length }
            guard db > a.distance, target <= db else { continue }
            return a.utc + (b.utc - a.utc) * (target - a.distance) / (db - a.distance)
        }
        return nil
    }

    private static func remember(_ p: GroupPosition, in h: inout [GroupPosition]) {
        h.append(p)
        if let i = h.firstIndex(where: { p.received.timeIntervalSince($0.received) < keep }), i > 0 { h.removeFirst(i) }
    }

    // MARK: - Connection

    private func connect() {
        guard let code else { return }
        generation += 1
        let gen = generation
        task?.cancel(with: .goingAway, reason: nil)
        status = retries == 0 ? .connecting : .waiting
        let t = URLSession.shared.webSocketTask(with: Server.groupURL(code))
        task = t
        t.resume()
        sendHello()
        receive(gen)
        pinger?.invalidate()
        let timer = Timer(timeInterval: 25, repeats: true) { [weak self] _ in self?.task?.send(.string(#"{"t":"ping"}"#)) { _ in } }
        RunLoop.main.add(timer, forMode: .common)
        pinger = timer
    }

    private func close() {
        generation += 1
        pinger?.invalidate()
        pinger = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        code = nil
        status = .off
        members = []
        history = [:]
        myHistory = []
        colors = [:]
        retries = 0
    }

    private func receive(_ gen: Int) {
        task?.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                switch result {
                case .success(let message):
                    if case .string(let s) = message { self.handle(s) }
                    self.receive(gen)
                case .failure:
                    self.dropped(gen)
                }
            }
        }
    }

    /// Lost: tried again, sooner at first; a group that is gone or full is left.
    private func dropped(_ gen: Int) {
        guard code != nil else { return }
        if let http = task?.response as? HTTPURLResponse, http.statusCode == 404 {
            leave()
            problem = L("Questo gruppo non esiste più: creane uno nuovo.")
            return
        }
        if task?.closeCode.rawValue == 4029 {
            leave()
            problem = L("Il gruppo è pieno.")
            return
        }
        status = .waiting
        retries += 1
        let delay = min(15, pow(2, Double(min(retries, 4))))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, gen == self.generation, self.code != nil else { return }
            self.connect()
        }
    }

    private func handle(_ s: String) {
        let data = Data(s.utf8)
        let decoder = JSONDecoder()
        guard let kind = try? decoder.decode(Kind.self, from: data) else { return }
        switch kind.t {
        case "state":
            guard let st = try? decoder.decode(StateWire.self, from: data) else { return }
            status = .live
            retries = 0
            problem = nil
            members = st.members.filter { $0.id != memberID }.map { member($0) }
            for p in st.positions ?? [] { apply(p) }
            onStandingsChange?()
        case "member":
            guard let m = try? decoder.decode(MemberMessage.self, from: data).member, m.id != memberID else { return }
            let updated = member(m)
            if let i = members.firstIndex(where: { $0.id == m.id }) { members[i] = updated } else { members.append(updated) }
            onStandingsChange?()
        case "pos":
            if let p = try? decoder.decode(PosWire.self, from: data) { apply(p) }
        case "lap":
            guard let l = try? decoder.decode(LapWire.self, from: data), let i = members.firstIndex(where: { $0.id == l.id }) else { return }
            members[i].best = l.best ?? members[i].best
            members[i].last = l.last ?? l.time
            members[i].laps = l.laps ?? members[i].laps + 1
            members[i].lapAt = Date()
            onStandingsChange?()
        default:
            break
        }
    }

    private func member(_ w: MemberWire) -> GroupMember {
        let old = members.first { $0.id == w.id }
        let color = colors[w.id] ?? colors.count
        colors[w.id] = color
        return GroupMember(id: w.id, name: w.name, vehicle: w.vehicle ?? "", track: w.track, best: w.best, last: w.last,
                           laps: w.laps ?? 0, online: w.online ?? true, color: color, position: old?.position, lapAt: old?.lapAt)
    }

    private func apply(_ w: PosWire) {
        guard let id = w.id, let i = members.firstIndex(where: { $0.id == id }) else { return }
        let p = GroupPosition(coord: Coord(w.lat, w.lon), lap: w.lap, distance: w.d, speed: w.v, utc: w.g, received: Date())
        members[i].position = p
        Self.remember(p, in: &history[id, default: []])
    }

    private func sendHello() {
        send(HelloWire(id: memberID, name: profile.displayName, vehicle: profile.displayVehicle, track: mine.track,
                       best: mine.best, last: mine.last, laps: mine.laps))
    }

    private func send<T: Encodable>(_ value: T) {
        guard let data = try? JSONEncoder().encode(value), let s = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func saveMine() {
        if let data = try? JSONEncoder().encode(mine) { UserDefaults.standard.set(data, forKey: Self.mineKey) }
    }

    // MARK: - Screenshot mode

    /// A pretend group for the screenshot mode (see Showcase): no server, the members driven by
    /// `showcaseMove` and `showcaseLap`.
    func showcase(code: String, members: [GroupMember], on track: Track?, best: Double?) {
        close()
        self.code = code
        mine = Mine(track: GroupTrack(track), best: best, last: best.map { $0 + 0.8 }, laps: 4)
        self.members = members
        for m in members { colors[m.id] = m.color }
        status = .live
    }

    func showcaseMove(_ id: String, to p: GroupPosition) {
        guard let i = members.firstIndex(where: { $0.id == id }) else { return }
        members[i].position = p
        Self.remember(p, in: &history[id, default: []])
    }

    func showcaseLap(_ id: String, time: Double) {
        guard let i = members.firstIndex(where: { $0.id == id }) else { return }
        members[i].last = time
        members[i].best = min(members[i].best ?? .infinity, time)
        members[i].laps += 1
        members[i].lapAt = Date()
        onStandingsChange?()
    }
}

// MARK: - Messages

private struct Kind: Decodable { var t: String }

private struct MemberWire: Decodable {
    var id: String
    var name: String
    var vehicle: String?
    var track: GroupTrack?
    var best: Double?
    var last: Double?
    var laps: Int?
    var online: Bool?
}

private struct MemberMessage: Decodable { var member: MemberWire }

private struct StateWire: Decodable {
    var you: String
    var members: [MemberWire]
    var positions: [PosWire]?
}

private struct HelloWire: Encodable {
    var t = "hello"
    var id: String
    var name: String
    var vehicle: String
    var track: GroupTrack?
    var best: Double?
    var last: Double?
    var laps: Int
}

private struct PosWire: Codable {
    var t = "pos"
    var id: String? = nil
    var lat: Double
    var lon: Double
    var lap: Int
    var d: Double
    var v: Double
    var g: Double
}

private struct LapWire: Codable {
    var t = "lap"
    var id: String? = nil
    var n: Int
    var time: Double
    var best: Double? = nil
    var last: Double? = nil
    var laps: Int? = nil
}
