import UIKit
import Observation

/// Your cars: an index (garage.json) and one JPEG per photo in the garage folder. Public, the
/// garage goes to the server a moment after every change: the cars first, then the photos the server
/// says it is missing.
@Observable
final class GarageStore {
    enum SyncState: Equatable {
        case idle, syncing
        case done(Date)
        case failed(String)
    }

    private(set) var cars: [Car] = []
    /// The setups of every car. They stay on this phone: never sent anywhere, only to a file you
    /// export yourself.
    private(set) var setups: [CarSetup] = []
    /// Shown to everyone at the garage's link and next to your laps on the leaderboards.
    private(set) var isPublic: Bool
    private(set) var sync: SyncState = .idle

    @ObservationIgnored var account: AccountStore?
    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var pending: Task<Void, Never>?

    private var dir: URL { Files.docs.appendingPathComponent("garage", isDirectory: true) }
    private var indexURL: URL { Files.docs.appendingPathComponent("garage.json") }
    private var setupsURL: URL { Files.docs.appendingPathComponent("setups.json") }

    /// The longest side of a stored photo, in pixels, and the most the server takes.
    static let photoSide: CGFloat = 1600
    static let maxPhotoBytes = 1_400_000

    init() {
        isPublic = UserDefaults.standard.bool(forKey: "garagePublic")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cars = Files.read([Car].self, from: indexURL) ?? []
        setups = Files.read([CarSetup].self, from: setupsURL) ?? []
        // In screenshot mode the photos come before their cars.
        if Showcase.screen == nil { sweep() }
    }

    func car(_ id: UUID?) -> Car? {
        guard let id else { return nil }
        return cars.first { $0.id == id }
    }

    var isFull: Bool { cars.count >= Car.maxCars }

    /// A new car goes first; the photo it had before, if it changed, is deleted.
    func save(_ car: Car) {
        let old = self.car(car.id)
        if let i = cars.firstIndex(where: { $0.id == car.id }) {
            cars[i] = car
        } else {
            guard !isFull else { return }
            cars.insert(car, at: 0)
        }
        if let photo = old?.photo, photo != car.photo { discardPhoto(photo) }
        changed()
    }

    func delete(_ id: UUID) {
        guard let car = car(id) else { return }
        cars.removeAll { $0.id == id }
        setups.removeAll { $0.carID == id }
        Files.write(setups, to: setupsURL)
        if let photo = car.photo { discardPhoto(photo) }
        changed()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = cars.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(cars.count - 1, i + offset))
        guard i != j else { return }
        let car = cars.remove(at: i)
        cars.insert(car, at: j)
        changed()
    }

    // MARK: - Setups

    /// A car's setups, the last changed first.
    func setups(of car: UUID?) -> [CarSetup] {
        setups.filter { $0.carID == car }.sorted { $0.updated > $1.updated }
    }

    func setup(_ id: UUID?) -> CarSetup? {
        guard let id else { return nil }
        return setups.first { $0.id == id }
    }

    /// A new setup, or a change to one: when its values change, the ones it had are kept as a
    /// revision first. Nothing is ever overwritten.
    func save(setup new: CarSetup) {
        var s = new
        if let i = setups.firstIndex(where: { $0.id == s.id }) {
            let old = setups[i]
            s.history = old.history
            if old.values != s.values {
                s.history.insert(SetupRevision(date: Date(), version: old.version, values: old.values), at: 0)
                s.updated = Date()
            } else if old.name != s.name || old.weather != s.weather || old.track != s.track {
                s.updated = Date()
            }
            setups[i] = s
        } else {
            s.created = Date()
            s.updated = Date()
            setups.insert(s, at: 0)
        }
        Files.write(setups, to: setupsURL)
    }

    /// A copy to start another setup from, with no history of its own.
    func duplicate(setup id: UUID) -> CarSetup? {
        guard let s = setup(id) else { return nil }
        var copy = s
        copy.id = UUID()
        copy.name = L("\(s.displayName) (copia)")
        copy.history = []
        save(setup: copy)
        return setup(copy.id)
    }

    func delete(setup id: UUID) {
        setups.removeAll { $0.id == id }
        Files.write(setups, to: setupsURL)
    }

    /// A setup from a file, for one of your cars: a new setup, its history included.
    @discardableResult
    func importSetup(_ shared: SharedSetup, for car: UUID) -> CarSetup {
        var s = shared.setup
        s.id = UUID()
        s.carID = car
        setups.insert(s, at: 0)
        Files.write(setups, to: setupsURL)
        return s
    }

    // MARK: - Photos

    /// A picked photo, made smaller and stored as a JPEG: its new id.
    func storePhoto(_ image: UIImage) -> String? {
        Self.jpeg(image).flatMap { storePhoto(jpeg: $0) }
    }

    /// A photo already made smaller (GarageStore.jpeg), stored: its new id.
    func storePhoto(jpeg data: Data) -> String? {
        let id = UUID().uuidString
        do {
            try data.write(to: file(id), options: .atomic)
        } catch {
            return nil
        }
        return id
    }

    func image(_ photo: String?) -> UIImage? {
        guard let photo else { return nil }
        if let hit = cache.object(forKey: photo as NSString) { return hit }
        guard let img = UIImage(contentsOfFile: file(photo).path) else { return nil }
        cache.setObject(img, forKey: photo as NSString)
        return img
    }

    /// A photo nobody uses any more (the editor was cancelled, the car changed photo).
    func discardPhoto(_ photo: String) {
        guard !cars.contains(where: { $0.photo == photo }) else { return }
        try? FileManager.default.removeItem(at: file(photo))
        cache.removeObject(forKey: photo as NSString)
    }

    private func photoData(_ photo: String) -> Data? { try? Data(contentsOf: file(photo)) }

    private func file(_ photo: String) -> URL { dir.appendingPathComponent(photo + ".jpg") }

    /// Photos left behind by an editor closed in the middle: deleted at launch.
    private func sweep() {
        let used = Set(cars.compactMap(\.photo))
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.pathExtension == "jpg" && !used.contains(f.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: f)
        }
    }

    /// At most 1600 pixels on the longest side, as a JPEG small enough for the server.
    static func jpeg(_ image: UIImage) -> Data? {
        let size = image.size
        let scale = min(1, photoSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        var quality: CGFloat = 0.8
        while quality > 0.3 {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxPhotoBytes { return data }
            quality -= 0.15
        }
        return resized.jpegData(compressionQuality: 0.3)
    }

    // MARK: - Publishing

    func setPublic(_ on: Bool) {
        isPublic = on
        UserDefaults.standard.set(on, forKey: "garagePublic")
        publishSoon(now: true)
    }

    /// After signing in or out: a garage shown from this phone goes up under the new account.
    func accountChanged() {
        sync = .idle
        publishSoon(now: true)
    }

    private func changed() {
        Files.write(cars, to: indexURL)
        publishSoon()
    }

    /// Changes come in bursts (a car saved, then another): one upload a moment after the last.
    func publishSoon(now: Bool = false) {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            if !now { try? await Task.sleep(for: .seconds(1.5)) }
            guard !Task.isCancelled else { return }
            await self?.publish()
        }
    }

    /// Public: the cars and then the missing photos. Private again: the garage is emptied on the
    /// server, so the link shows nothing, but it stays yours for when you show it again.
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
        guard isPublic || account.garage != nil else {
            sync = .idle
            return
        }
        sync = .syncing
        do {
            let code = try await account.garageCode()
            let shown = isPublic ? cars.map(\.published) : []
            let missing = try await Server.putGarage(code: code, cars: shown, token: token)
            for photo in missing {
                guard !Task.isCancelled else { return }
                guard let data = photoData(photo) else { continue }
                try await Server.putPhoto(code: code, photo: photo, jpeg: data, token: token)
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
}
