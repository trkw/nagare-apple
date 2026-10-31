import NagareKit
import SwiftUI
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// APNs registration and notification taps. Which feeds notify is set per feed on the server.
@MainActor
final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()

    weak var model: AppModel?
    private let enabledKey = "nagare.push.enabled"
    private let tokenKey = "nagare.push.token"

    var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    func configure(model: AppModel) {
        self.model = model
        UNUserNotificationCenter.current().delegate = self
        // Device tokens can change, so register again on every launch once the user opted in.
        if enabled && model.client != nil { registerWithSystem() }
    }

    /// Asks for permission and registers. Returns false when the user declined.
    func enable() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return false }
        UserDefaults.standard.set(true, forKey: enabledKey)
        registerWithSystem()
        return true
    }

    func disable() async {
        UserDefaults.standard.set(false, forKey: enabledKey)
        if let token = UserDefaults.standard.string(forKey: tokenKey) {
            try? await model?.client?.unregisterPush(token: token)
        }
        #if os(iOS)
        UIApplication.shared.unregisterForRemoteNotifications()
        #else
        NSApplication.shared.unregisterForRemoteNotifications()
        #endif
    }

    private func registerWithSystem() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #else
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func didRegister(deviceToken: Data) {
        let token = PushToken.hex(deviceToken)
        UserDefaults.standard.set(token, forKey: tokenKey)
        guard let client = model?.client else { return }
        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif
        Task {
            do {
                try await client.registerPush(apnsToken: token, name: Self.deviceName, sandbox: sandbox)
            } catch {
                model?.report(error)
            }
        }
    }

    func didFailToRegister(_ error: Error) {
        model?.error = "通知の登録に失敗しました: \(error.localizedDescription)"
    }

    private static var deviceName: String {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let entryId = (info["entry_id"] as? Int) ?? (info["entry_id"] as? NSNumber)?.intValue
        let url = (info["url"] as? String).flatMap(URL.init(string:))
        await MainActor.run {
            if let entryId {
                Task { await self.model?.openEntry(id: entryId) }
            } else if let url {
                #if os(iOS)
                UIApplication.shared.open(url)
                #else
                NSWorkspace.shared.open(url)
                #endif
            }
        }
    }
}

#if os(iOS)
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.didFailToRegister(error)
    }
}
#else
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.didFailToRegister(error)
    }
}
#endif
