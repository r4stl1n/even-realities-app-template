import Foundation

@MainActor
protocol ControllerManager {
    // MARK: - hard coded device properties:

    var type: String { get set }
    var hasMic: Bool { get }

    // MARK: - Audio Control

    func setMicEnabled(_ enabled: Bool)
    func sortMicRanking(list: [String]) -> [String]

    // MARK: - Messaging

    func sendJson(_ jsonOriginal: [String: Any], wakeUp: Bool, requireAck: Bool)

    // MARK: - Camera & Media

    // MARK: - Button Settings

    // MARK: - Display Control

    func setBrightness(_ level: Int, autoMode: Bool)
    func clearDisplay()
    func sendTextWall(_ text: String)
    func sendDoubleTextWall(_ top: String, _ bottom: String)
    func displayBitmap(base64ImageData: String, x: Int32?, y: Int32?, width: Int32?, height: Int32?) async -> Bool
    func showDashboard()
    func setDashboardPosition(_ height: Int, _ depth: Int)

    // MARK: - Device Control

    func setHeadUpAngle(_ angle: Int)
    func getBatteryStatus()
    func setSilentMode(_ enabled: Bool)
    func exit()
    func sendShutdown()
    func sendReboot()
    // MARK: - Connection Management

    func disconnect()
    func forget()
    func findCompatibleDevices()
    func stopScan()
    func connectById(_ id: String)
    func getConnectedBluetoothName() -> String?
    func cleanup()
    func ping()

    // MARK: - Network Management

    func sendOtaStart(otaVersionUrl: String?)
    func sendOtaQueryStatus()

    // MARK: - User Context (for crash reporting)

    func sendUserEmailToGlasses(_ email: String)

    // MARK: - Gallery

    // MARK: - Version Info

    func requestVersionInfo()
}

/// doesn't seem to work for concurrency reasons :(
/// we can make read-only getters for convienence though:
extension ControllerManager {
    // MARK: - Default DeviceStore-backed property implementations

    var fullyBooted: Bool {
        DeviceStore.shared.get("glasses", "fullyBooted") as? Bool ?? false
    }

    var connected: Bool {
        DeviceStore.shared.get("glasses", "connected") as? Bool ?? false
    }

    var appVersion: String {
        DeviceStore.shared.get("glasses", "appVersion") as? String ?? ""
    }

    var buildNumber: String {
        DeviceStore.shared.get("glasses", "buildNumber") as? String ?? ""
    }

    var deviceModel: String {
        DeviceStore.shared.get("glasses", "deviceModel") as? String ?? ""
    }

    var androidVersion: String {
        DeviceStore.shared.get("glasses", "androidVersion") as? String ?? ""
    }

    var otaVersionUrl: String {
        DeviceStore.shared.get("glasses", "otaVersionUrl") as? String ?? ""
    }

    var firmwareVersion: String {
        DeviceStore.shared.get("glasses", "firmwareVersion") as? String ?? ""
    }

    var bluetoothMacAddress: String {
        DeviceStore.shared.get("glasses", "bluetoothMacAddress") as? String ?? ""
    }

    var serialNumber: String {
        DeviceStore.shared.get("glasses", "serialNumber") as? String ?? ""
    }

    var style: String {
        DeviceStore.shared.get("glasses", "style") as? String ?? ""
    }

    var color: String {
        DeviceStore.shared.get("glasses", "color") as? String ?? ""
    }

    var micEnabled: Bool {
        DeviceStore.shared.get("glasses", "micEnabled") as? Bool ?? false
    }

    var voiceActivityDetectionEnabled: Bool {
        DeviceStore.shared.get("glasses", "voiceActivityDetectionEnabled") as? Bool
            ?? BluetoothSdkDefaults.voiceActivityDetectionEnabled
    }

    var batteryLevel: Int {
        DeviceStore.shared.get("glasses", "batteryLevel") as? Int ?? -1
    }

    var headUp: Bool {
        DeviceStore.shared.get("glasses", "headUp") as? Bool ?? false
    }

    var charging: Bool {
        DeviceStore.shared.get("glasses", "charging") as? Bool ?? false
    }

    var caseOpen: Bool {
        DeviceStore.shared.get("glasses", "caseOpen") as? Bool ?? true
    }

    var caseRemoved: Bool {
        DeviceStore.shared.get("glasses", "caseRemoved") as? Bool ?? true
    }

    var caseCharging: Bool {
        DeviceStore.shared.get("glasses", "caseCharging") as? Bool ?? false
    }

    var caseBatteryLevel: Int {
        DeviceStore.shared.get("glasses", "caseBatteryLevel") as? Int ?? -1
    }
}
