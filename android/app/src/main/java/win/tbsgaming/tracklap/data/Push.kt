package win.tbsgaming.tracklap.data

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import win.tbsgaming.tracklap.MainActivity
import win.tbsgaming.tracklap.R
import win.tbsgaming.tracklap.ui.L
import win.tbsgaming.tracklap.ui.Strings

/**
 * Notifications from the server through Firebase Cloud Messaging: a friend who accepted your
 * invitation, and a friend's new best lap on a track. This phone's token goes to the server with
 * your account (signing out stops them). The server sends only data, and the app writes the
 * notification in its language. Each kind has its own channel, to be silenced on its own.
 * Firebase is there only when the build has android/app/google-services.json; without it there are
 * no notifications and the rest works.
 */
object Push {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    /** The token and account already sent in this launch. */
    private var sent: String? = null

    fun available(context: Context) = FirebaseApp.getApps(context).isNotEmpty()

    /** The token to the server: once per account in a launch, again after signing in. */
    fun sync(context: Context, account: AccountStore) {
        if (!available(context)) return
        val auth = account.token ?: return
        val name = account.name ?: return
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            val key = token + "/" + name.lowercase()
            if (sent == key) return@addOnSuccessListener
            sent = key
            scope.launch {
                runCatching { Server.addDevice(token, "android", auth) }.onFailure { if (sent == key) sent = null }
            }
        }
    }

    /** A new token from Google: to the server, with the account saved on the phone. */
    fun tokenChanged(context: Context, token: String) {
        sent = null
        val auth = AccountStore(context).token ?: return
        scope.launch { runCatching { Server.addDevice(token, "android", auth) } }
    }

    fun canNotify(context: Context) =
        Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** "Marco accepted your invitation": tapping it opens Friends. */
    fun showFriend(context: Context, id: String, name: String) {
        Strings.init(context)
        show(context, CHANNEL, L("Amici"), "friend:$id", L("Nuovo amico"), L("%@ ha accettato il tuo invito: ora siete amici.", name))
    }

    /** "Marco passed you at Mugello: 1:52.34", or his new best there: tapping it opens Friends. */
    fun showRecord(context: Context, id: String, name: String, track: String, time: String, passed: Boolean) {
        Strings.init(context)
        show(
            context, RECORDS, L("Record degli amici"), "record:$id:$track",
            if (passed) L("Ti hanno superato") else L("Nuovo record"),
            if (passed) L("%@ ti ha superato a %@: %@.", name, track, time) else L("%@ ha un nuovo record a %@: %@.", name, track, time),
        )
    }

    private fun show(context: Context, channel: String, channelName: String, tag: String, title: String, text: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(channel, channelName, NotificationManager.IMPORTANCE_DEFAULT))
        if (!canNotify(context)) return
        val open = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData(Uri.parse("tracklap://friends"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = PendingIntent.getActivity(context, tag.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val note = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFF2DD4BF.toInt())
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        manager.notify(tag.hashCode(), note)
    }

    private const val CHANNEL = "friends"
    private const val RECORDS = "records"
}

/** Firebase's messages: the new token, and the notifications (in the app or not). */
class PushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) = Push.tokenChanged(applicationContext, token)

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val name = data["name"] ?: return
        when (data["kind"]) {
            "friend" -> Push.showFriend(applicationContext, data["friend"] ?: name, name)
            "record" -> Push.showRecord(
                applicationContext, data["friend"] ?: name, name, data["track"] ?: return, data["time"] ?: return, data["passed"] == "1",
            )
        }
    }
}
