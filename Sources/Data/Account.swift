import Foundation
import Observation
import Security

/// Your TrackLap account: the name everyone sees on the leaderboards and on your garage. The token
/// the server gives at sign-in stays in the Keychain; the password is never kept on the phone.
@Observable
final class AccountStore {
    private(set) var name: String?
    /// Your public garage's code, once you have shown a car.
    private(set) var garage: String?
    @ObservationIgnored private(set) var token: String?

    var isSignedIn: Bool { token != nil && name != nil }

    /// Called after signing in or out, for whoever keeps something tied to the account.
    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        token = Keychain.read("token")
        let d = UserDefaults.standard
        name = d.string(forKey: "accountName")
        garage = d.string(forKey: "accountGarage")
        if token == nil { name = nil }
    }

    @MainActor
    func signUp(name: String, password: String) async throws {
        apply(try await Server.signUp(name: name.trimmingCharacters(in: .whitespaces), password: password))
    }

    @MainActor
    func signIn(name: String, password: String) async throws {
        apply(try await Server.signIn(name: name.trimmingCharacters(in: .whitespaces), password: password))
    }

    @MainActor
    func signOut() async {
        if let token { await Server.signOut(token: token) }
        clear()
    }

    @MainActor
    func changePassword(old: String, new: String) async throws {
        guard let token else { throw Server.Failure.signedOut }
        apply(try await Server.changePassword(token: token, old: old, new: new))
    }

    /// The account, its garage and its laps on the leaderboards, for good.
    @MainActor
    func delete(password: String) async throws {
        guard let token else { throw Server.Failure.signedOut }
        try await Server.deleteAccount(token: token, password: password)
        clear()
    }

    /// Checks the token is still good (another phone may have changed the password) and picks up the
    /// garage made from another phone.
    @MainActor
    func refresh() async {
        guard let token else { return }
        do {
            let me = try await Server.me(token: token)
            name = me.name
            setGarage(me.garage)
        } catch Server.Failure.signedOut {
            clear()
        } catch {}
    }

    /// Your garage's code, made on the server the first time.
    @MainActor
    func garageCode() async throws -> String {
        if let garage { return garage }
        guard let token else { throw Server.Failure.signedOut }
        let code = try await Server.openGarage(token: token)
        setGarage(code)
        return code
    }

    /// A request came back refused for the token: signed out here too.
    func signedOutElsewhere() { clear() }

    private func apply(_ s: Server.SignedIn) {
        token = s.token
        Keychain.write("token", s.token)
        name = s.account.name
        UserDefaults.standard.set(s.account.name, forKey: "accountName")
        setGarage(s.account.garage)
        onChange?()
    }

    private func setGarage(_ code: String?) {
        garage = code
        UserDefaults.standard.set(code, forKey: "accountGarage")
    }

    private func clear() {
        token = nil
        name = nil
        Keychain.write("token", nil)
        UserDefaults.standard.removeObject(forKey: "accountName")
        setGarage(nil)
        onChange?()
    }
}

/// A few strings in the Keychain, readable after the first unlock (a lap may be published with the
/// phone locked in the car mount).
enum Keychain {
    private static let service = "com.local.tracklap"

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }
}
