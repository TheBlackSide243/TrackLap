package win.tbsgaming.tracklap.data

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.ListSerializer
import win.tbsgaming.tracklap.model.Friend
import win.tbsgaming.tracklap.model.FriendInvite
import win.tbsgaming.tracklap.model.FriendProfile
import java.io.File

/**
 * The drivers you are friends with on TrackLap, and your invitation link. The list is kept in
 * friend-list.json too, so the tab shows it at once and without signal; the server is asked again
 * every time the tab opens.
 */
class FriendStore {
    sealed interface Load {
        data object Idle : Load
        data object Loading : Load
        data object Loaded : Load
        data class Failed(val message: String) : Load
    }

    @set:JvmName("assignFriends") var friends by mutableStateOf<List<Friend>>(emptyList()); private set
    @set:JvmName("assignState") var state by mutableStateOf<Load>(Load.Idle); private set
    var account: AccountStore? = null

    private var invite: FriendInvite? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val file get() = File(Files.docs, "friend-list.json")
    private val list = ListSerializer(Friend.serializer())

    init {
        friends = Files.read(list, file) ?: emptyList()
    }

    suspend fun refresh() {
        val token = token() ?: return
        state = Load.Loading
        state = try {
            put(Server.friends(token))
            Load.Loaded
        } catch (e: ServerFailure) {
            Load.Failed(handle(e))
        }
    }

    /** Your invitation link: the same one while it has more than a day left. */
    suspend fun inviteURL(renew: Boolean = false): String {
        val current = invite
        if (!renew && current != null && current.expires - System.currentTimeMillis() > DAY_MS) return Server.inviteURL(current.code)
        val token = token() ?: throw ServerFailure(ServerFailure.Kind.signedOut)
        try {
            val made = Server.invite(token, renew)
            invite = made
            return Server.inviteURL(made.code)
        } catch (e: ServerFailure) {
            handle(e)
            throw e
        }
    }

    /** An invitation accepted: the new friend joins the list. */
    suspend fun accept(code: String): Friend {
        val token = token() ?: throw ServerFailure(ServerFailure.Kind.signedOut)
        try {
            val friend = Server.accept(code, token)
            put(friends.filter { it.id != friend.id } + friend)
            return friend
        } catch (e: ServerFailure) {
            handle(e)
            throw e
        }
    }

    suspend fun profile(friend: Friend): FriendProfile {
        val token = token() ?: throw ServerFailure(ServerFailure.Kind.signedOut)
        try {
            return Server.friend(friend.id, token)
        } catch (e: ServerFailure) {
            if (e.kind == ServerFailure.Kind.notFriend) put(friends.filter { it.id != friend.id }) else handle(e)
            throw e
        }
    }

    /** No longer friends, for both of you. */
    suspend fun remove(friend: Friend) {
        val token = token() ?: throw ServerFailure(ServerFailure.Kind.signedOut)
        try {
            Server.removeFriend(friend.id, token)
        } catch (e: ServerFailure) {
            if (e.kind != ServerFailure.Kind.notFriend) {
                handle(e)
                throw e
            }
        }
        put(friends.filter { it.id != friend.id })
    }

    fun friend(id: String): Friend? = friends.firstOrNull { it.id == id }

    /** Signed in as someone else, or out: their friends are not yours. */
    fun accountChanged() {
        invite = null
        state = Load.Idle
        put(emptyList())
        scope.launch { refresh() }
    }

    private fun token(): String? = account?.takeIf { it.isSignedIn }?.token

    private fun put(value: List<Friend>) {
        friends = value.sortedBy { it.name.lowercase() }
        Files.write(friends, list, file)
    }

    /** The message for an error; a token refused means signed out here too. */
    private fun handle(e: ServerFailure): String {
        if (e.kind == ServerFailure.Kind.signedOut) account?.signedOutElsewhere()
        return e.message
    }

    private companion object {
        const val DAY_MS = 24 * 3600 * 1000.0
    }
}
