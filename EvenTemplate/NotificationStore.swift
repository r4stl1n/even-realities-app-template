import Foundation

struct AppNotification: Identifiable, Equatable {
    let id: Int
    let title: String
    let body: String
    let timestamp: Date
}

/// In-app notification inbox. Notifications are added from the phone UI (or
/// programmatically via `add`) and browsed on the glasses through
/// GlassesNotificationViewer. Real OS notifications reach paired glasses
/// directly via ANCS, not through this app.
@MainActor
final class NotificationStore: ObservableObject {
    @Published private(set) var notifications: [AppNotification] = []
    private var nextId = 1

    @discardableResult
    func add(title: String, body: String) -> AppNotification {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notification = AppNotification(
            id: nextId,
            title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle,
            body: body.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: Date()
        )
        nextId += 1
        notifications.insert(notification, at: 0)
        return notification
    }

    func remove(id: Int) {
        notifications.removeAll { $0.id == id }
    }

    func clear() {
        notifications.removeAll()
    }
}
