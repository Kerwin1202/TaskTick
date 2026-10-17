import AppKit
import Foundation
import SwiftData
import UserNotifications
import TaskTickCore

enum TaskResultNotificationStyle: String {
    case system, bottom

    static let settingKey = "taskResultNotificationStyle"

    static func current(_ defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: settingKey).flatMap(Self.init(rawValue:)) ?? .system
    }
}

/// Manages task result notifications and other system notifications.
final class NotificationManager: NSObject, @unchecked Sendable {

    static let shared = NotificationManager()

    /// userInfo flag: tapping this banner should bring the main window back.
    static let openMainWindowKey = "tasktick.openMainWindow"

    /// userInfo value (UUID string): tapping this banner should open the main
    /// window with that task selected.
    static let taskIdKey = "tasktick.taskId"

    /// userInfo for a banner about one task.
    static func userInfo(taskId: UUID) -> [String: Any] {
        [taskIdKey: taskId.uuidString]
    }

    /// Inverse of `userInfo(taskId:)`, for the tap handler.
    static func taskId(from userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo[taskIdKey] as? String).flatMap(UUID.init(uuidString:))
    }

    private var isAvailable = false

    private override init() { super.init() }

    @MainActor
    func sendTaskResult(title: String, body: String, taskId: UUID, succeeded: Bool) {
        if let toast = Self.taskResultToast(title: title, body: body, succeeded: succeeded) {
            ToastCenter.shared.show(toast) {
                Self.selectInMainWindow(taskId: taskId)
                AppDelegate.bringMainWindowForward()
            }
        } else {
            sendNotification(title: title, body: body, userInfo: Self.userInfo(taskId: taskId))
        }
    }

    /// Nil keeps the existing system notification path, including for older users.
    static func taskResultToast(
        title: String,
        body: String,
        succeeded: Bool,
        defaults: UserDefaults = .standard
    ) -> ToastDescriptor? {
        guard TaskResultNotificationStyle.current(defaults) == .bottom else { return nil }
        return ToastDescriptor(message: body, icon: succeeded ? .success : .error, duration: 5, title: title)
    }

    func requestPermission() {
        // UNUserNotificationCenter requires a valid app bundle with bundle identifier.
        // When running via `swift run`, no bundle exists and this will crash.
        guard Bundle.main.bundleIdentifier != nil else {
            print("[NotificationManager] No bundle identifier — notifications disabled.")
            return
        }

        isAvailable = true
        // Without a delegate, macOS silently drops notifications submitted while the
        // app is in the foreground — which is exactly when users test "Run Now". Set
        // ourselves as the delegate so the willPresent hook below can ask the system
        // to show the banner regardless of foreground state.
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("[NotificationManager] Permission error: \(error)")
            }
        }
    }

    /// `userInfo` rides along so the tap handler below knows what the banner was
    /// about — `openMainWindowKey` (hide-to-menu-bar notice) or `taskIdKey`
    /// (anything about a single task).
    func sendNotification(title: String, body: String, userInfo: [String: Any] = [:]) {
        guard isAvailable else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                NSLog("⚠️ Notification add failed: \(error.localizedDescription)")
            }
            self?.checkPermissionAndPromptIfNeeded()
        }
    }

    /// Check authorization status; if the user has explicitly denied notifications,
    /// surface an NSAlert that deep-links into System Settings. macOS does not let
    /// apps re-trigger the system permission dialog after a denial, so a custom
    /// prompt with a settings link is the only recovery path.
    private func checkPermissionAndPromptIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .denied else { return }
            DispatchQueue.main.async {
                Self.presentDeniedAlert()
            }
        }
    }

    @MainActor
    private static func presentDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("notification.denied.title")
        alert.informativeText = L10n.tr("notification.denied.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("notification.denied.open_settings"))
        alert.addButton(withTitle: L10n.tr("notification.denied.later"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Deep link directly to the per-app notification pane. Bundle ID is
            // appended so System Settings opens at the right row instead of the
            // root notifications list.
            let bundleID = Bundle.main.bundleIdentifier ?? ""
            let urlString = "x-apple.systempreferences:com.apple.preference.notifications?id=\(bundleID)"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show banner + play sound even when the app is foregrounded; otherwise macOS
    /// suppresses the visual entirely and the user only sees the entry in Notification
    /// Center after the fact.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// A banner that says "TaskTick is still running" is only useful if tapping it
    /// gets the user back to the window; one about a task should land on that task.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let taskId = Self.taskId(from: userInfo)
        let wantsMainWindow = userInfo[Self.openMainWindowKey] as? Bool ?? false
        if taskId != nil || wantsMainWindow,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            DispatchQueue.main.async {
                if let taskId { Self.selectInMainWindow(taskId: taskId) }
                AppDelegate.bringMainWindowForward()
            }
        }
        completionHandler()
    }

    /// Same rendezvous the Quick Launcher's ⌘O uses: the main window picks the
    /// task up on appear (fresh window) or on change (already open). A task
    /// deleted since the banner fired finds nothing — the window still opens.
    @MainActor
    private static func selectInMainWindow(taskId: UUID) {
        let context = TaskTickApp._sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<ScheduledTask>(predicate: #Predicate { $0.id == taskId })
        guard let task = try? context.fetch(descriptor).first else { return }
        MainWindowSelection.shared.taskToReveal = task
    }
}
