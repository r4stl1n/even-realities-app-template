import SwiftUI

struct NotificationsScreen: View {
    @EnvironmentObject private var store: NotificationStore
    @EnvironmentObject private var viewer: GlassesNotificationViewer

    @State private var title = ""
    @State private var body_ = ""

    private static let demoNotifications: [(String, String)] = [
        ("Calendar", "Standup in 15 minutes"),
        ("Messages", "Sam: running 5 late, order me a coffee?"),
        ("Reminder", "Water the plants"),
    ]

    var body: some View {
        Form {
            Section("Glasses viewer") {
                Text("Shows the inbox on connected G1/G2 glasses. Browse with the glasses touchpad or the R1 ring: swipe down or tap = next, swipe up = previous, double-tap = dismiss.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Toggle("Viewer active", isOn: Binding(
                    get: { viewer.active },
                    set: { $0 ? viewer.start() : viewer.stop() }
                ))
                Toggle("Show only on head-up", isOn: $viewer.headUpOnly)
                if viewer.active {
                    Text(viewerStatus)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    HStack {
                        Button("◀ Prev") { viewer.previous() }
                        Spacer()
                        Button("Dismiss") { viewer.dismissCurrent() }
                        Spacer()
                        Button("Next ▶") { viewer.next() }
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("System notifications") {
                Text("The glasses receive system notifications directly from the phone via ANCS: pair the glasses, then enable \"Share System Notifications\" for them in Settings → Bluetooth. No app involvement.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section("New notification") {
                TextField("Title", text: $title)
                TextField("Body", text: $body_)
                Button("Add notification") {
                    addNotification()
                }
                Button("Add demo notifications") {
                    for (demoTitle, demoBody) in Self.demoNotifications {
                        store.add(title: demoTitle, body: demoBody)
                    }
                }
            }

            Section("Inbox (\(store.notifications.count))") {
                if store.notifications.isEmpty {
                    Text("No notifications. Add one above.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                ForEach(Array(store.notifications.enumerated()), id: \.element.id) { index, notification in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewer.active && index == viewer.index ? "▶ " : "")\(notification.title)")
                            Text(notification.body)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("✕") {
                            store.remove(id: notification.id)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if !store.notifications.isEmpty {
                    Button("Clear all", role: .destructive) {
                        store.clear()
                    }
                }
            }
        }
    }

    private var viewerStatus: String {
        let count = store.notifications.count
        var status = "Showing \(count == 0 ? "empty state" : "\(viewer.index + 1) of \(count)")"
        if viewer.headUpOnly {
            status += " · head \(viewer.headUp ? "up" : "down")"
        }
        return status
    }

    private func addNotification() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedBody = body_.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty || !trimmedBody.isEmpty else { return }
        store.add(title: title, body: body_)
        title = ""
        body_ = ""
    }
}
