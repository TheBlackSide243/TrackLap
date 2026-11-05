import Foundation
import Observation

/// The drivers you are friends with on TrackLap, and your invitation link. The list is kept in
/// friend-list.json too, so the tab shows it at once and without signal; the server is asked again
/// every time the tab opens.
@Observable
final class FriendStore {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var friends: [Friend] = []
    private(set) var state: LoadState = .idle

    @ObservationIgnored var account: AccountStore?
    @ObservationIgnored private var invite: FriendInvite?

    private var url: URL { Files.docs.appendingPathComponent("friend-list.json") }

    init() {
        friends = Files.read([Friend].self, from: url) ?? []
    }

    /// The eight letters of an invitation (the same alphabet as the group and garage codes).
    static func isInviteCode(_ code: String) -> Bool {
        code.range(of: "^[A-HJ-NP-Z2-9]{8}$", options: .regularExpression) != nil
    }

    @MainActor
    func refresh() async {
        guard let token = signedInToken() else { return }
        state = .loading
        do {
            set(try await Server.friends(token: token))
            state = .loaded
        } catch {
            state = .failed(handle(error))
        }
    }

    /// Your invitation link: the same one while it has more than a day left.
    @MainActor
    func inviteURL(renew: Bool = false) async throws -> URL {
        if !renew, let invite, invite.expiry.timeIntervalSinceNow > 24 * 3600 {
            return Server.inviteURL(code: invite.code)
        }
        guard let token = signedInToken() else { throw Server.Failure.signedOut }
        do {
            let made = try await Server.invite(token: token, renew: renew)
            invite = made
            return Server.inviteURL(code: made.code)
        } catch {
            _ = handle(error)
            throw error
        }
    }

    /// An invitation accepted: the new friend joins the list.
    @MainActor
    @discardableResult
    func accept(_ code: String) async throws -> Friend {
        guard let token = signedInToken() else { throw Server.Failure.signedOut }
        do {
            let friend = try await Server.accept(invite: code, token: token)
            set(friends.filter { $0.id != friend.id } + [friend])
            return friend
        } catch {
            _ = handle(error)
            throw error
        }
    }

    @MainActor
    func profile(_ friend: Friend) async throws -> FriendProfile {
        guard let token = signedInToken() else { throw Server.Failure.signedOut }
        do {
            return try await Server.friend(id: friend.id, token: token)
        } catch Server.Failure.notFriend {
            set(friends.filter { $0.id != friend.id })
            throw Server.Failure.notFriend
        } catch {
            _ = handle(error)
            throw error
        }
    }

    /// No longer friends, for both of you.
    @MainActor
    func remove(_ friend: Friend) async throws {
        guard let token = signedInToken() else { throw Server.Failure.signedOut }
        do {
            try await Server.removeFriend(id: friend.id, token: token)
        } catch Server.Failure.notFriend {
        } catch {
            _ = handle(error)
            throw error
        }
        set(friends.filter { $0.id != friend.id })
    }

    /// Signed in as someone else, or out: their friends are not yours.
    func accountChanged() {
        invite = nil
        state = .idle
        set([])
        Task { @MainActor in await refresh() }
    }

    private func signedInToken() -> String? {
        guard Showcase.screen == nil, let account, account.isSignedIn else { return nil }
        return account.token
    }

    private func set(_ list: [Friend]) {
        friends = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        Files.write(friends, to: url)
    }

    /// The message for an error; a token refused means signed out here too.
    private func handle(_ error: Error) -> String {
        if case Server.Failure.signedOut = error { account?.signedOutElsewhere() }
        return error.localizedDescription
    }
}
