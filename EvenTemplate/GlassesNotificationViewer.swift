import Combine
import Foundation

/// Renders the notification inbox on the glasses and drives it from device
/// input. Runs independently of which phone tab is open while the app is in
/// the foreground.
///
/// Gestures (glasses touchpad and R1 ring):
///   swipe_down / single_tap -> next notification
///   swipe_up                -> previous notification
///   double_tap              -> dismiss the current notification
///
/// With "head-up only" enabled, the display is blank until the wearer looks
/// up (uses the glasses' head_up event).
@MainActor
final class GlassesNotificationViewer: ObservableObject {
    @Published private(set) var active = false
    @Published var headUpOnly = false {
        didSet {
            guard headUpOnly != oldValue, active else { return }
            render()
        }
    }
    @Published private(set) var index = 0
    @Published private(set) var headUp = false

    private let session: BluetoothSession
    private let store: NotificationStore
    private var subscriptions = Set<AnyCancellable>()

    init(session: BluetoothSession, store: NotificationStore) {
        self.session = session
        self.store = store
    }

    var current: AppNotification? {
        let notifications = store.notifications
        guard index < notifications.count else { return nil }
        return notifications[index]
    }

    func start() {
        guard !active else { return }
        active = true
        index = 0
        session.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &subscriptions)
        // @Published emits on willSet; defer to the next runloop tick so the
        // store's array is updated by the time we re-render.
        store.$notifications
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleInboxChange() }
            .store(in: &subscriptions)
        render()
    }

    func stop() {
        guard active else { return }
        subscriptions.removeAll()
        active = false
        clearDisplay()
    }

    func next() {
        move(1)
    }

    func previous() {
        move(-1)
    }

    func dismissCurrent() {
        if let current {
            store.remove(id: current.id)
        }
    }

    private func handle(_ event: BluetoothEvent) {
        switch event {
        case let .touch(touch):
            switch touch.gestureName {
            case "swipe_down", "single_tap":
                next()
            case "swipe_up":
                previous()
            case "double_tap":
                dismissCurrent()
            default:
                break
            }
        case let .raw(name, values):
            if name == "head_up", let up = values["up"] as? Bool {
                handleHeadUp(up)
            }
        default:
            break
        }
    }

    private func handleHeadUp(_ up: Bool) {
        headUp = up
        guard active, headUpOnly else { return }
        if up {
            render()
        } else {
            clearDisplay()
        }
    }

    private func handleInboxChange() {
        let count = store.notifications.count
        if index >= count {
            index = max(0, count - 1)
        }
        render()
    }

    private func move(_ delta: Int) {
        let count = store.notifications.count
        guard count > 0 else { return }
        index = ((index + delta) % count + count) % count
        render()
    }

    private func render() {
        guard active else { return }
        if headUpOnly, !headUp { return }
        let text = formatCurrent()
        let sdk = session.sdk
        Task { try? await sdk.displayText(text) }
    }

    private func clearDisplay() {
        let sdk = session.sdk
        Task { try? await sdk.clearDisplay() }
    }

    private func formatCurrent() -> String {
        let notifications = store.notifications
        guard !notifications.isEmpty else { return "No notifications" }
        let notification = notifications[min(index, notifications.count - 1)]
        let position = "\(index + 1)/\(notifications.count)"
        let time = notification.timestamp.formatted(date: .omitted, time: .shortened)
        // Keep it plain text: G1 renders a limited Latin glyph set and both
        // models wrap long lines themselves.
        return "[\(position)] \(notification.title) (\(time))\n\(notification.body)"
    }
}
