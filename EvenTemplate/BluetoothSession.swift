import Combine
import Foundation

/// The app's single Bluetooth entry point: wraps the MentraBluetoothSDK facade,
/// republishes its state for SwiftUI, and fans out input/mic events to whoever
/// needs them (input log, notification viewer, mic meter).
@MainActor
final class BluetoothSession: ObservableObject {
    let sdk = MentraBluetoothSDK()

    @Published private(set) var glasses: GlassesRuntimeState
    @Published private(set) var scan: BluetoothScanState
    @Published private(set) var defaultDevice: Device?
    @Published private(set) var lastError: BluetoothSdkError?

    let events = PassthroughSubject<BluetoothEvent, Never>()
    let micPcm = PassthroughSubject<MicPcmEvent, Never>()

    init() {
        glasses = sdk.glasses
        scan = sdk.scanState
        defaultDevice = sdk.defaultDevice
        sdk.delegate = self
    }

    // MARK: - Actions

    func startScan(_ model: DeviceModel) {
        lastError = nil
        do { try sdk.startScan(model: model) } catch { fail(error) }
    }

    func stopScan() {
        sdk.stopScan()
    }

    func connect(_ device: Device) {
        lastError = nil
        sdk.stopScan()
        do { try sdk.connect(to: device) } catch { fail(error) }
    }

    func connectDefault() {
        lastError = nil
        do { try sdk.connectDefault() } catch { fail(error) }
    }

    func disconnect() {
        sdk.disconnect()
    }

    func clearDefaultDevice() {
        sdk.clearDefaultDevice()
    }

    private func fail(_ error: Error) {
        lastError = error as? BluetoothSdkError
            ?? BluetoothSdkError(code: "error", message: String(describing: error))
    }
}

extension BluetoothSession: MentraBluetoothSDKDelegate {
    func mentraBluetoothSDK(_: MentraBluetoothSDK, didUpdateGlasses glasses: GlassesRuntimeState) {
        self.glasses = glasses
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didUpdateScan scan: BluetoothScanState) {
        self.scan = scan
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didChangeDefaultDevice device: Device?) {
        defaultDevice = device
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didReceive event: BluetoothEvent) {
        events.send(event)
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didReceiveMicPcm event: MicPcmEvent) {
        micPcm.send(event)
    }

    func mentraBluetoothSDK(_: MentraBluetoothSDK, didFail error: BluetoothSdkError) {
        lastError = error
    }
}
