import UIKit
import UserNotifications

/// Notifications from the server; for now one kind: a friend who accepted your invitation. iOS asks
/// once, the first time you open Friends signed in. The token Apple gives this iPhone goes to the
/// server with your account, and signing out stops them. The words come from Localizable.strings:
/// the server sends the Italian key ("%@ ha accettato il tuo invito: ora siete amici.") and the name.
/// Tapping one opens Friends.
@MainActor
final class PushNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotifications()

    private weak var model: AppModel?
    private var token: String?
    /// The token and account already sent in this launch.
    private var sent: String?
    /// Opened from a notification before the app was ready.
    private var openFriends = false

    /// At launch: the delegate first, so a notification that started the app is not missed.
    func launched() {
        UNUserNotificationCenter.current().delegate = self
    }

    func start(_ model: AppModel) {
        self.model = model
        if openFriends { open() }
        guard Showcase.screen == nil else { return }
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .authorized || status == .provisional || status == .ephemeral {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// In Friends: whether you want to hear about friends who accept. iOS asks only the first time.
    func ask() {
        guard Showcase.screen == nil else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            switch await center.notificationSettings().authorizationStatus {
            case .notDetermined:
                guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
            case .denied:
                return
            default:
                break
            }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func registered(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        sync()
    }

    /// The token to the server: once per account in a launch, again after signing in.
    func sync() {
        guard let token, let model, let account = model.account.token, let name = model.account.name else { return }
        let key = token + "/" + name.lowercased()
        guard sent != key else { return }
        sent = key
        Task {
            do {
                try await Server.addDevice(token: token, platform: "ios", account: account)
            } catch {
                if sent == key { sent = nil }
            }
        }
    }

    private func open() {
        guard let model else {
            openFriends = true
            return
        }
        openFriends = false
        model.tab = .friends
        Task { await model.friendList.refresh() }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// In the app: the banner shows anyway, and the list has the new friend.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            if let model { await model.friendList.refresh() }
        }
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.open() }
        completionHandler()
    }
}

/// Only for what SwiftUI has no way for: the token Apple gives for notifications.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        PushNotifications.shared.launched()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotifications.shared.registered(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // A build without the push entitlement (Feather's): no notifications, the rest works.
        print("push:", error.localizedDescription)
    }
}
