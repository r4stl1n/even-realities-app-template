//
//  Simulated.swift
//  EvenTemplate
//
//  Created by Matthew Fosse on 10/7/25.
//

@MainActor
class Simulated: SGCManager {
    init() {
        DeviceStore.shared.apply("glasses", "fullyBooted", true)
        DeviceStore.shared.apply("glasses", "connected", true)
        DeviceStore.shared.apply("glasses", "connectionState", ConnTypes.CONNECTED)
        DeviceStore.shared.apply("glasses", "micEnabled", false)
        DeviceStore.shared.apply(
            "glasses",
            "voiceActivityDetectionEnabled",
            BluetoothSdkDefaults.voiceActivityDetectionEnabled
        )
        DeviceStore.shared.apply("glasses", "bluetoothClassicConnected", false)
    }

    // MARK: - Device Information

    var type: String = DeviceTypes.SIMULATED
    var ready: Bool = true
    var connectionState: String = ConnTypes.CONNECTED

    var appVersion: String = ""
    var buildNumber: String = ""
    var deviceModel: String = ""
    var androidVersion: String = ""
    var otaVersionUrl: String = ""
    var firmwareVersion: String = ""
    var bluetoothMacAddress: String = ""
    var serialNumber: String = ""
    var style: String = ""
    var color: String = ""

    // MARK: - Hardware Status

    var hasMic: Bool = false
    var batteryLevel: Int = 100
    var headUp: Bool = false
    var micEnabled: Bool = false

    // MARK: - Case Status

    var caseOpen: Bool = false
    var caseRemoved: Bool = false
    var caseCharging: Bool = false
    var caseBatteryLevel: Int = -1

    // MARK: - Network Status

    var wifiSsid: String = ""
    var wifiConnected: Bool = false
    var wifiLocalIp: String = ""
    var hotspotEnabled: Bool = false
    var hotspotSsid: String = ""
    var hotspotPassword: String = ""
    var hotspotGatewayIp: String = ""

    // MARK: - Audio Control

    func setMicEnabled(_: Bool) {
        Bridge.log("setMicEnabled")
    }

    func sortMicRanking(list: [String]) -> [String] {
        return list
    }

    // MARK: - Messaging

    func sendJson(_: [String: Any], wakeUp _: Bool, requireAck _: Bool) {
        Bridge.log("sendJson")
    }

    // MARK: - Camera & Media

    // MARK: - Button Settings

    // MARK: - Display Control

    func setBrightness(_: Int, autoMode _: Bool) {
        Bridge.log("setBrightness")
    }

    func clearDisplay() {
        Bridge.log("clearDisplay")
    }

    func sendText(_ text: String) async {
        await sendTextWall(text)
    }

    func sendTextWall(_: String) async {
        Bridge.log("sendTextWall")
    }

    func sendDoubleTextWall(_: String, _: String) async {
        Bridge.log("sendDoubleTextWall")
    }

    func displayBitmap(base64ImageData _: String, x _: Int32?, y _: Int32?, width _: Int32?, height _: Int32?) async -> Bool {
        Bridge.log("displayBitmap")
        return false
    }

    func showDashboard() {
        Bridge.log("showDashboard")
    }

    func setDashboardPosition(_: Int, _: Int) {
        Bridge.log("setDashboardPosition")
    }

    // MARK: - Device Control

    func setHeadUpAngle(_: Int) {
        Bridge.log("setHeadUpAngle")
    }

    func getBatteryStatus() {
        Bridge.log("getBatteryStatus")
    }

    func setSilentMode(_: Bool) {
        Bridge.log("setSilentMode")
    }

    func exit() {
        Bridge.log("exit")
    }

    func sendShutdown() {
        Bridge.log("sendShutdown - not supported on Simulated")
    }

    func sendReboot() {
        Bridge.log("sendReboot - not supported on Simulated")
    }

    // MARK: - Connection Management

    func disconnect() {
        Bridge.log("disconnect")
    }

    func forget() {
        Bridge.log("forget")
    }

    func findCompatibleDevices() {
        Bridge.log("findCompatibleDevices")
    }

    func stopScan() {
        Bridge.log("stopScan")
    }

    func connectById(_: String) {
        Bridge.log("connectById")
    }

    func getConnectedBluetoothName() -> String? {
        return nil
    }

    func cleanup() {
        Bridge.log("cleanup")
    }

    func ping() {
        Bridge.log("ping")
    }

    func dbg1() {}
    func dbg2() {}
    func connectController() {}
    func disconnectController() {}

    // MARK: - Network Management

    func sendUserEmailToGlasses(_ email: String) {
        Bridge.log("sendUserEmailToGlasses: \(email)")
    }

    func sendOtaStart(otaVersionUrl: String?) {
        Bridge.log("sendOtaStart")
    }

    func sendOtaQueryStatus() {
        Bridge.log("sendOtaQueryStatus")
    }

    // MARK: - Gallery

    // MARK: - Version Info

    func requestVersionInfo() {
        Bridge.log("requestVersionInfo - not supported on Simulated")
    }

}
