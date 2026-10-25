import Foundation
import UserNotifications

/// macOS Notification Center notifications with real answer buttons (the same actions the in-app
/// toast offers). Handlers live here until the notification is answered or the oldest ones expire.
@MainActor
final class SystemNotificationActions {
    static let shared = SystemNotificationActions()

    private static let keepLast = 20
    private static let categoryPrefix = "intermezzo.actions."

    private var handlers: [String: [String: @MainActor () -> Void]] = [:]
    private var order: [String] = []
    private var categories: [String: UNNotificationCategory] = [:]

    func send(title: String, body: String, actions: [ToastAction]) {
        let requestID = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if !actions.isEmpty {
            var byID: [String: @MainActor () -> Void] = [:]
            let unActions = actions.enumerated().map { index, action -> UNNotificationAction in
                let id = "\(index)"
                byID[id] = action.handler
                return UNNotificationAction(identifier: id, title: action.title, options: [])
            }
            let categoryID = Self.categoryPrefix + requestID
            categories[categoryID] = UNNotificationCategory(identifier: categoryID, actions: unActions,
                                                            intentIdentifiers: [], options: [])
            handlers[requestID] = byID
            order.append(requestID)
            trim()
            UNUserNotificationCenter.current().setNotificationCategories(Set(categories.values))
            content.categoryIdentifier = categoryID
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: requestID, content: content, trigger: nil))
    }

    /// Runs the handler of the pressed button; the default click (action id of the banner itself) does nothing.
    func handle(requestID: String, actionID: String) {
        handlers[requestID]?[actionID]?()
        forget(requestID)
    }

    private func trim() {
        while order.count > Self.keepLast { forget(order[0]) }
    }

    private func forget(_ requestID: String) {
        handlers[requestID] = nil
        categories[Self.categoryPrefix + requestID] = nil
        order.removeAll { $0 == requestID }
    }
}
