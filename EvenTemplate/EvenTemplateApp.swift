import SwiftUI

/// Handles the CoreBluetooth state-restoration relaunch: when the app is
/// terminated by iOS with a glasses/ring connection alive, a BLE event makes
/// iOS relaunch it in the background with `.bluetoothCentrals` launch options.
/// Recreating the saved connections here rebuilds the centrals with their
/// restore identifiers, and the drivers adopt the still-open connections in
/// `willRestoreState`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if launchOptions?[.bluetoothCentrals] != nil {
            DeviceManager.shared.connectDefault()
        }
        return true
    }
}

@main
struct EvenTemplateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session: BluetoothSession
    @StateObject private var store: NotificationStore
    @StateObject private var viewer: GlassesNotificationViewer

    init() {
        let session = BluetoothSession()
        let store = NotificationStore()
        _session = StateObject(wrappedValue: session)
        _store = StateObject(wrappedValue: store)
        _viewer = StateObject(wrappedValue: GlassesNotificationViewer(session: session, store: store))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                DevicesScreen()
                    .tabItem { Label("Devices", systemImage: "eyeglasses") }
                NotificationsScreen()
                    .tabItem { Label("Notifs", systemImage: "bell") }
                DisplayScreen()
                    .tabItem { Label("Display", systemImage: "text.alignleft") }
                InputScreen()
                    .tabItem { Label("Input", systemImage: "hand.tap") }
                MicScreen()
                    .tabItem { Label("Mic", systemImage: "mic") }
            }
            .environmentObject(session)
            .environmentObject(store)
            .environmentObject(viewer)
        }
    }
}
