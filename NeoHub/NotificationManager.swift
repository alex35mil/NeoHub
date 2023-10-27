import UserNotifications

typealias NotificationMeta = [AnyHashable: Any]

protocol NotificationProtocol {
    static var id: String { get }

    static var title: String { get }
    static var body: String { get }

    static var actions: [NotificationAction.Type] { get }
    static var category: UNNotificationCategory { get }

    var meta: NotificationMeta? { get }

    func send()
}

extension NotificationProtocol {
    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: Self.id,
            actions: Self.actions.map { action in action.built },
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "",
            options: .customDismissAction
        )
    }
}

protocol NotificationAction {
    static var id: String { get }
    static var button: String { get }

    static var built: UNNotificationAction { get }

    var meta: NotificationMeta { get }

    init?(from meta: NotificationMeta)

    func run()
}

extension NotificationAction {
    static var built: UNNotificationAction {
        UNNotificationAction(
            identifier: Self.id,
            title: Self.button,
            options: []
        )
    }
}

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    override init() {
        Self.registerCategories()
        super.init()
    }

    static func registerCategories() {
        // Probably, I should have gone with a simple enum so the compiler could generate all cases for me
        let categories = Set([
            FailedToLaunchServerNotification.category,
            FailedToHandleRequestFromCLINotification.category,
            FailedToRunEditorProcessNotification.category,
            FailedToGetRunningEditorAppNotification.category,
            FailedToActivateEditorAppNotification.category
        ])

        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    private enum AuthStatus {
        case unknown
        case granted
        case rejected
    }

    private var status: AuthStatus = .unknown

    private func requestAuthorization(completion: @escaping (Bool) -> Void) {
        switch self.status {
            case .unknown:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    DispatchQueue.main.async {
                        switch (granted, error) {
                            case (true, nil):
                                log.info("Notification permission granted")
                                self.status = .granted
                                completion(true)
                            case (true, .some(let error)):
                                log.info("Notification permission granted")
                                log.notice("There was an error during notification authorization request. \(error)")
                                self.status = .granted
                                completion(true)
                            case (false, let error):
                                log.info("Notification permission not granted. Details: \(String(describing: error))")
                                self.status = .rejected
                                completion(false)
                        }
                    }
                }
            case .granted:
                completion(true)
            case .rejected:
                completion(false)
        }
    }

    fileprivate func sendNotification(notification: NotificationProtocol) {
        log.debug("Sending notification")

        self.requestAuthorization { granted in
            guard granted else {
                log.debug("Notifications are not authorized")
                return
            }

            let content = UNMutableNotificationContent()

            let Notification = type(of: notification)

            content.categoryIdentifier = Notification.id

            content.title = Notification.title
            content.body = Notification.body

            if let meta = notification.meta {
                content.userInfo = meta
            }

            log.debug("Notification content: \(content)")

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    log.error("Error scheduling notification: \(error)")
                } else {
                    log.debug("Notification scheduled")
                }
            }
        }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func registerDelegate() {
        UNUserNotificationCenter.current().delegate = self
        log.info("Notification manager delegate registered")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
            case ReportAction.id:
                let meta = response.notification.request.content.userInfo
                if let action = ReportAction(from: meta) {
                    DispatchQueue.global().async {
                        action.run()
                    }
                }
                break
            default:
                break
        }

        completionHandler()
    }
}

struct ReportAction: NotificationAction {
    static let id: String = "REPORT_ACTION"
    static let button: String = "Report"

    let title: String
    let error: String

    init(error: ReportableError) {
        self.title = error.message
        self.error = String(describing: error)
    }

    var meta: NotificationMeta {
        [
            "REPORT_TITLE": title,
            "REPORT_ERROR": error,
        ]
    }

    init?(from meta: NotificationMeta) {
        guard let title = meta["REPORT_TITLE"] as? String,
              let error = meta["REPORT_ERROR"] as? String else {
            log.warning("Failed to get metadata from notification. Meta: \(meta)")
            return nil
        }

        self.title = title
        self.error = error
    }

    func run() {
        BugReporter.report(
            title: self.title,
            error: self.error
        )
    }
}

struct FailedToLaunchServerNotification: NotificationProtocol {
    static let id = "FAILED_TO_LAUNCH_SERVER"

    static let title = "Failed to launch the NeoHub server"
    static let body = "NeoHub won't be able to function properly. Please, create an issue in the GitHub repo."

    static let actions: [NotificationAction.Type] = [ReportAction.self]

    var meta: NotificationMeta?

    init(error: ReportableError) {
        let action = ReportAction(error: error)
        self.meta = action.meta
    }

    func send() {
        NotificationManager.shared.sendNotification(notification: self)
    }
}

struct FailedToHandleRequestFromCLINotification: NotificationProtocol {
    static let id = "FAILED_TO_HANDLE_REQUEST_FROM_CLI"

    static let title = "Failed to open Neovide"
    static let body = "Please create an issue in the GitHub repo."

    static let actions: [NotificationAction.Type] = [ReportAction.self]

    var meta: NotificationMeta?

    init(error: ReportableError) {
        let action = ReportAction(error: error)
        self.meta = action.meta
    }

    func send() {
        NotificationManager.shared.sendNotification(notification: self)
    }
}

struct FailedToRunEditorProcessNotification: NotificationProtocol {
    static let id = "FAILED_TO_RUN_EDITOR_PROCESS"

    static let title = "Failed to open Neovide"
    static let body = "Please create an issue in the GitHub repo."

    static let actions: [NotificationAction.Type] = [ReportAction.self]

    var meta: NotificationMeta?

    init(error: ReportableError) {
        let action = ReportAction(error: error)
        self.meta = action.meta
    }

    func send() {
        NotificationManager.shared.sendNotification(notification: self)
    }
}

struct FailedToGetRunningEditorAppNotification: NotificationProtocol {
    static let id = "FAILED_TO_GET_RUNNING_EDITOR_APP"

    static let title = "Failed to activate Neovide"
    static let body = "Requested Neovide instance is not running."

    static let actions: [NotificationAction.Type] = [ReportAction.self]

    var meta: NotificationMeta?

    init(error: ReportableError) {
        let action = ReportAction(error: error)
        self.meta = action.meta
    }

    func send() {
        NotificationManager.shared.sendNotification(notification: self)
    }
}

struct FailedToActivateEditorAppNotification: NotificationProtocol {
    static let id = "FAILED_TO_ACTIVATE_EDITOR_APP"

    static let title = "Failed to activate Neovide"
    static let body = "Please create an issue in GitHub repo."

    static let actions: [NotificationAction.Type] = [ReportAction.self]

    var meta: NotificationMeta?

    init(error: ReportableError) {
        let action = ReportAction(error: error)
        self.meta = action.meta
    }

    func send() {
        NotificationManager.shared.sendNotification(notification: self)
    }
}
