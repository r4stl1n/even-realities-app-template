import CoreBluetooth
import Foundation

@MainActor
private final class ActiveScanSession {
    let model: DeviceModel
    let onResults: ([Device]) -> Void
    let onComplete: ([Device]) -> Void
    var latestResults: [Device] = []
    var timeoutTask: Task<Void, Never>?
    weak var publicSession: ScanSession?

    init(
        model: DeviceModel,
        onResults: @escaping ([Device]) -> Void,
        onComplete: @escaping ([Device]) -> Void
    ) {
        self.model = model
        self.onResults = onResults
        self.onComplete = onComplete
    }
}

@MainActor
private final class PendingResponse<T> {
    private let operation: String
    private var continuation: CheckedContinuation<T, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var result: Result<T, Error>?
    private var completed = false

    init(operation: String) {
        self.operation = operation
    }

    func resolve(_ value: T) {
        guard !completed else { return }
        completed = true
        result = .success(value)
        timeoutTask?.cancel()
        continuation?.resume(returning: value)
        continuation = nil
    }

    func reject(_ error: Error) {
        guard !completed else { return }
        completed = true
        result = .failure(error)
        timeoutTask?.cancel()
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func wait(timeoutMs: Int = 15_000) async throws -> T {
        if let result {
            return try result.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                } catch {
                    return
                }
                self?.reject(
                    BluetoothSdkError(
                        code: "request_timeout",
                        message: "\(self?.operation ?? "Request") timed out waiting for glasses response."
                    )
                )
            }
        }
    }
}

@MainActor
public final class MentraBluetoothSDK {
    // A photo response is terminal only after capture, encoding, transport, and upload.
    // Max-quality BLE fallback can legitimately exceed the generic command deadline.
    private static let photoRequestTimeoutMs = 30_000
    private static let defaultStreamKeepAliveIntervalSeconds = 5

    public weak var delegate: MentraBluetoothSDKDelegate?

    private let configuration: MentraBluetoothSDKConfiguration
    private var discoveredDeviceNames = Set<String>()
    private var bluetoothAvailabilityListenerId: UUID?
    private var shouldRestoreGlassesOnBluetoothRestore = false
    private var shouldRestoreControllerOnBluetoothRestore = false
    private var bridgeEventSinkId: String?
    private var storeListenerId: String?
    private let defaultDeviceKeys: Set<String> = ["default_wearable", "device_name", "device_address"]
    private var suppressDefaultDeviceEvents = false
    private var defaultDeviceApplyGeneration = 0
    private var activeScanSessions: [UUID: ActiveScanSession] = [:]
    private var pendingSettingsRequests: [String: PendingResponse<SettingsAckEvent>] = [:]
    private var pendingOtaQuery: PendingResponse<OtaQueryResult>?
    private var pendingOtaStart: PendingResponse<OtaStartAckEvent>?
    private var pendingVersionInfo: PendingResponse<VersionInfoResult>?

    public init(configuration: MentraBluetoothSDKConfiguration = .default) {
        self.configuration = configuration
        bluetoothAvailabilityListenerId = BluetoothAvailability.shared.addStateListener { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleBluetoothAvailability(state)
            }
        }
        bridgeEventSinkId = Bridge.addEventSink { [weak self] eventName, data in
            // Bridge.dispatchEvent always invokes sinks on the main thread, in the
            // FIFO order events were dispatched (correlated WiFi-scan chunks rely
            // on that order). A fresh Task per event can reach the MainActor out
            // of creation order and reorder chunks, so consume synchronously
            // while still on main.
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.dispatchBridgeEvent(eventName, data)
                }
            } else {
                // Defensive fallback only — Bridge.dispatchEvent should never take
                // this path. A serial main-queue hop still preserves FIFO order,
                // unlike an unstructured Task.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.dispatchBridgeEvent(eventName, data)
                    }
                }
            }
        }
        storeListenerId = DeviceStore.shared.store.addListener { [weak self] category, changes in
            Task { @MainActor [weak self] in
                self?.dispatchStoreUpdate(category, changes)
            }
        }
    }

    public var state: MentraBluetoothState {
        MentraBluetoothState(glassesStatus: glassesStatus, bluetoothStatus: bluetoothStatus)
    }

    public var glasses: GlassesRuntimeState {
        state.glasses
    }

    public var sdkState: PhoneSdkRuntimeState {
        state.sdk
    }

    public var scanState: BluetoothScanState {
        state.scan
    }

    var glassesStatus: GlassesStatus {
        GlassesStatus(values: DeviceStore.shared.store.getCategory("glasses"))
    }

    var bluetoothStatus: BluetoothStatus {
        BluetoothStatus(values: DeviceStore.shared.store.getCategory(ObservableStore.bluetoothCategory))
    }

    public var defaultDevice: Device? {
        currentDefaultDevice()
    }

    private func requireGlassesConnected(operation: String) throws {
        guard glassesStatus.connected else {
            throw BluetoothSdkError(
                code: "glasses_not_connected",
                message: "Cannot \(operation) because glasses are not connected."
            )
        }
    }

    public func getDefaultDevice() -> Device? {
        currentDefaultDevice()
    }

    public func setDefaultDevice(_ device: Device?) {
        guard let device else {
            clearDefaultDevice()
            return
        }
        defaultDeviceApplyGeneration += 1
        let generation = defaultDeviceApplyGeneration
        suppressDefaultDeviceEvents = true
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "default_wearable", device.model.deviceType)
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "device_name", device.name)
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "device_address", device.identifier ?? "")
        finishDefaultDeviceApply(generation: generation)
    }

    public func clearDefaultDevice() {
        defaultDeviceApplyGeneration += 1
        let generation = defaultDeviceApplyGeneration
        suppressDefaultDeviceEvents = true
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "default_wearable", "")
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "device_name", "")
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "device_address", "")
        finishDefaultDeviceApply(generation: generation)
    }

    public func startScan(model: DeviceModel) throws {
        if model != .simulated {
            try BluetoothAvailability.shared.requirePoweredOn(operation: "scan for glasses")
        }
        discoveredDeviceNames.removeAll()
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "searching", true)
        DeviceManager.shared.findCompatibleDevices(model.deviceType)
    }

    public func stopScan() {
        stopScan(reason: .cancelled)
    }

    private func stopScan(reason: ScanStopReason) {
        DeviceManager.shared.stopScan()
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "searching", false)
        delegate?.mentraBluetoothSDK(self, didStopScan: reason)
    }

    @discardableResult
    public func scan(
        model: DeviceModel,
        timeout: TimeInterval = 15,
        onResults: @escaping ([Device]) -> Void,
        onComplete: @escaping ([Device]) -> Void = { _ in }
    ) throws -> ScanSession {
        let normalizedTimeout = timeout > 0 && timeout.isFinite ? timeout : 15
        let id = UUID()
        let activeSession = ActiveScanSession(
            model: model,
            onResults: onResults,
            onComplete: onComplete
        )
        let publicSession = ScanSession { [weak self] in
            self?.finishScanSession(id, reason: .cancelled, shouldStopScan: true)
        }
        activeSession.publicSession = publicSession
        activeScanSessions[id] = activeSession

        do {
            emitScanResults([], forSession: id)
            try startScan(model: model)
            emitScanResults(bluetoothStatus.searchResults.filter { $0.model == model }, forSession: id)
            activeSession.timeoutTask = Task { [weak self] in
                let nanoseconds = UInt64(normalizedTimeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                await self?.finishScanSession(id, reason: .completed, shouldStopScan: true)
            }
            return publicSession
        } catch {
            activeScanSessions[id] = nil
            publicSession.markStopped()
            throw error
        }
    }

    public func connect(to device: Device, options: ConnectOptions = ConnectOptions()) throws {
        clearBluetoothRestoreIntent()
        if device.model != .simulated {
            try BluetoothAvailability.shared.requirePoweredOn(operation: "connect to glasses")
        }
        let isController = ControllerTypes.ALL.contains(device.model.deviceType)
        if options.cancelExistingConnectionAttempt {
            if isController {
                DeviceManager.shared.disconnectController()
            } else {
                cancelConnectionAttempt()
            }
        }
        if options.saveAsDefault && !isController {
            setDefaultDevice(device)
        }
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "pending_wearable", device.model.deviceType)
        DeviceManager.shared.connectByName(device.name)
    }

    public func connectDefault(options: ConnectOptions = ConnectOptions()) throws {
        clearBluetoothRestoreIntent()
        guard let device = currentDefaultDevice() else {
            throw BluetoothSdkError(
                code: "default_device_missing",
                message: "Set a default glasses device before calling connectDefault."
            )
        }
        if device.model != .simulated {
            try BluetoothAvailability.shared.requirePoweredOn(operation: "connect to glasses")
        }
        if options.cancelExistingConnectionAttempt {
            cancelConnectionAttempt()
        }
        DeviceManager.shared.connectDefault()
    }

    public func cancelConnectionAttempt() {
        clearBluetoothRestoreIntent()
        DeviceManager.shared.disconnect()
    }

    func connectSimulated() {
        clearBluetoothRestoreIntent()
        DeviceManager.shared.connectSimulated()
    }

    public func disconnect() {
        clearBluetoothRestoreIntent()
        DeviceManager.shared.disconnect()
    }

    public func forget() {
        clearBluetoothRestoreIntent()
        DeviceManager.shared.forget()
    }

    public func displayText(_ text: String, x: Int = 0, y: Int = 0, size: Int = 24) async throws {
        try await displayText(DisplayTextRequest(text: text, x: x, y: y, size: size))
    }

    public func displayText(_ request: DisplayTextRequest) async throws {
        DeviceManager.shared.displayText(request.dictionary)
    }

    func displayEvent(_ request: DisplayEventRequest) async throws {
        DeviceManager.shared.displayEvent(request.values)
    }

    public func clearDisplay() async throws {
        DeviceManager.shared.sgc?.clearDisplay()
    }

    public func showDashboard() {
        DeviceManager.shared.showDashboard()
    }

    public func showNotificationsPanel() {
        DeviceManager.shared.showNotificationsPanel()
    }

    func setBrightness(_ level: Int, autoMode: Bool? = nil) async throws {
        if let autoMode {
            DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "auto_brightness", autoMode)
        }
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "brightness", level)
    }

    func setAutoBrightness(enabled: Bool) async throws {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "auto_brightness", enabled)
    }

    public func setDashboardPosition(height: Int, depth: Int) async throws {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "dashboard_height", height)
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "dashboard_depth", depth)
    }

    public func setDashboardPosition(_ request: DashboardPositionRequest) async throws {
        try await setDashboardPosition(height: request.height, depth: request.depth)
    }

    /// Whether the "Hey Even" voice wakeword is enabled on the glasses (G2).
    public var heyEvenEnabled: Bool {
        DeviceStore.shared.get(ObservableStore.bluetoothCategory, "hey_even_enabled") as? Bool
            ?? false
    }

    /// Enable/disable the "Hey Even" voice wakeword. Applies immediately when
    /// connected and is re-applied on every reconnect.
    public func setHeyEvenEnabled(_ enabled: Bool) {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "hey_even_enabled", enabled)
    }

    /// Whether the firmware's built-in menu entries (Even AI, Teleprompt,
    /// Translate, Navigate, Conversate) are hidden on the glasses (G2).
    public var builtinMenuAppsHidden: Bool {
        DeviceStore.shared.get(ObservableStore.bluetoothCategory, "hide_builtin_menu_apps")
            as? Bool ?? true
    }

    /// Hide/show the firmware's built-in menu entries. Hiding applies
    /// immediately; showing them again takes effect on the next reconnect.
    public func setBuiltinMenuAppsHidden(_ hidden: Bool) {
        DeviceStore.shared.apply(
            ObservableStore.bluetoothCategory, "hide_builtin_menu_apps", hidden
        )
    }

    /// How long the dashboard stays up before the glasses close it and blank the
    /// lens. `-1` means "leave the glasses' own value alone", `0` means never.
    public var dashboardAutoCloseSeconds: Int {
        DeviceStore.shared.get(ObservableStore.bluetoothCategory, "dashboard_auto_close_seconds")
            as? Int ?? -1
    }

    /// Set the dashboard auto-close timer. `0` means never close; `-1` leaves the
    /// glasses' existing value untouched. Applies immediately when connected and
    /// is re-applied on every reconnect.
    public func setDashboardAutoCloseSeconds(_ seconds: Int) {
        DeviceStore.shared.apply(
            ObservableStore.bluetoothCategory, "dashboard_auto_close_seconds", seconds
        )
    }

    /// How long the boot splash holds on the glasses, in seconds. 0 disables it.
    public var splashDurationSeconds: Int {
        DeviceStore.shared.get(ObservableStore.bluetoothCategory, "splash_duration_seconds")
            as? Int ?? 2
    }

    /// Set the boot splash hold, in seconds. 0 skips the splash entirely.
    /// Takes effect on the next connect, which is when the splash runs.
    public func setSplashDurationSeconds(_ seconds: Int) {
        DeviceStore.shared.apply(
            ObservableStore.bluetoothCategory, "splash_duration_seconds", max(seconds, 0)
        )
    }

    func setDashboardMenu(_ items: [DashboardMenuItem]) async throws {
        DeviceStore.shared.apply(
            ObservableStore.bluetoothCategory,
            "menu_apps",
            items.map(\.dictionary)
        )
    }

    func setCalendarEvents(_ events: [CalendarEvent]) async throws {
        DeviceStore.shared.apply(
            ObservableStore.bluetoothCategory,
            "calendar_events",
            events.map(\.dictionary)
        )
    }

    public func setHeadUpAngle(_ angleDegrees: Int) async throws {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "head_up_angle", angleDegrees)
    }

    public func setScreenDisabled(_ disabled: Bool) async throws {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "screen_disabled", disabled)
    }

    private func performSettingsCommand(
        setting: String,
        updateStore: (SettingsAckEvent) -> Void,
        send: (String) throws -> Void
    ) async throws -> SettingsAckEvent {
        let requestId = "settings-\(setting)-\(UUID().uuidString)"
        let pending = PendingResponse<SettingsAckEvent>(operation: "set \(setting)")
        pendingSettingsRequests[requestId] = pending
        do {
            try send(requestId)
            let ack = try await pending.wait()
            updateStore(ack)
            pendingSettingsRequests.removeValue(forKey: requestId)
            return ack
        } catch {
            pendingSettingsRequests.removeValue(forKey: requestId)
            throw error
        }
    }

    public func setVoiceActivityDetectionEnabled(_ enabled: Bool) async throws {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "voice_activity_detection_enabled", enabled)
    }

    public func setMicState(
        enabled: Bool,
        useGlassesMic: Bool = true,
        sendTranscript: Bool = false,
        sendLc3Data: Bool = false
    ) {
        if enabled {
            DeviceStore.shared.apply(
                ObservableStore.bluetoothCategory,
                "preferred_mic",
                useGlassesMic ? MicPreference.glasses.rawValue : MicPreference.phone.rawValue
            )
        }
        applyMicState(
            sendPcmData: enabled,
            sendTranscript: enabled && sendTranscript,
            sendLc3Data: enabled && sendLc3Data
        )
    }

    private func applyMicState(
        sendPcmData: Bool,
        sendTranscript: Bool,
        sendLc3Data: Bool
    ) {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "should_send_pcm", sendPcmData)
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "should_send_lc3", sendLc3Data)
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "should_send_transcript", sendTranscript)
        DeviceManager.shared.setMicState()
    }

    public func setPreferredMic(_ preferredMic: MicPreference) {
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "preferred_mic", preferredMic.rawValue)
    }

    public func setOwnAppAudioPlaying(_ playing: Bool) {
        PhoneAudioMonitor.getInstance().setOwnAppAudioPlaying(playing)
    }

    func setSystemTime(timestampMs: Int64) {
        DeviceManager.shared.setSystemTime(timestampMs)
    }

    public func requestVersionInfo() async throws -> VersionInfoResult {
        guard pendingVersionInfo == nil else {
            throw BluetoothSdkError(
                code: "request_in_flight",
                message: "A version info request is already waiting for a glasses response."
            )
        }
        let pending = PendingResponse<VersionInfoResult>(operation: "version info request")
        pendingVersionInfo = pending
        DeviceManager.shared.requestVersionInfo()
        do {
            let status = try await pending.wait()
            if pendingVersionInfo === pending {
                pendingVersionInfo = nil
            }
            return status
        } catch {
            if pendingVersionInfo === pending {
                pendingVersionInfo = nil
            }
            throw error
        }
    }

    /// Ask connected Mentra Live glasses to report the current OTA install/session status.
    private func queryOtaStatus() async throws -> OtaQueryResult {
        try await performOtaQuery(operation: "OTA status query") {
            DeviceManager.shared.sendOtaQueryStatus()
        }
    }

    private func performOtaQuery(
        operation: String,
        sendRequest: () -> Void
    ) async throws -> OtaQueryResult {
        if pendingOtaQuery != nil {
            throw BluetoothSdkError(
                code: "request_in_flight",
                message: "An OTA status query is already waiting for a glasses response."
            )
        }
        let pending = PendingResponse<OtaQueryResult>(operation: operation)
        pendingOtaQuery = pending
        sendRequest()
        do {
            let result = try await pending.wait()
            if pendingOtaQuery === pending {
                pendingOtaQuery = nil
            }
            return result
        } catch {
            if pendingOtaQuery === pending {
                pendingOtaQuery = nil
            }
            throw error
        }
    }

    private func startOtaCommand(otaVersionUrl: String) async throws -> OtaStartAckEvent {
        if pendingOtaStart != nil {
            throw BluetoothSdkError(
                code: "request_in_flight",
                message: "An OTA start command is already waiting for a glasses response."
            )
        }
        let pending = PendingResponse<OtaStartAckEvent>(operation: "OTA start command")
        pendingOtaStart = pending
        DeviceManager.shared.sendOtaStart(otaVersionUrl: otaVersionUrl)
        do {
            let event = try await pending.wait()
            if pendingOtaStart === pending {
                pendingOtaStart = nil
            }
            return event
        } catch {
            if pendingOtaStart === pending {
                pendingOtaStart = nil
            }
            throw error
        }
    }

    func startOtaUpdate(otaVersionUrl: String) async throws -> OtaStartAckEvent {
        try await startOtaCommand(otaVersionUrl: otaVersionUrl)
    }

    func sendOtaQueryStatus() async throws -> OtaQueryResult { try await queryOtaStatus() }

    func sendShutdown() {
        DeviceManager.shared.sendShutdown()
    }

    func sendReboot() {
        DeviceManager.shared.sendReboot()
    }

    public func invalidate() {
        if let bluetoothAvailabilityListenerId {
            BluetoothAvailability.shared.removeStateListener(bluetoothAvailabilityListenerId)
            self.bluetoothAvailabilityListenerId = nil
        }
        if let bridgeEventSinkId {
            Bridge.removeEventSink(bridgeEventSinkId)
            self.bridgeEventSinkId = nil
        }
        if let storeListenerId {
            DeviceStore.shared.store.removeListener(storeListenerId)
            self.storeListenerId = nil
        }
        delegate = nil
    }

    private func handleBluetoothAvailability(_ state: CBManagerState) {
        switch state {
        case .poweredOff, .resetting, .unauthorized, .unsupported:
            handleBluetoothUnavailable()
        case .poweredOn:
            handleBluetoothRestored()
        case .unknown:
            break
        @unknown default:
            handleBluetoothUnavailable()
        }
    }

    private func handleBluetoothUnavailable() {
        cancelActiveScanSessions(reason: .cancelled)
        clearBluetoothDiscoveryState()
        disconnectActiveConnections()
    }

    private func disconnectActiveConnections() {
        if glassesStatus.controllerConnected {
            DeviceManager.shared.disconnectController()
            shouldRestoreControllerOnBluetoothRestore = true
        }
        if glassesStatus.deviceModel == DeviceTypes.SIMULATED
            || DeviceManager.shared.sgc?.type.contains(DeviceTypes.SIMULATED) == true
        {
            return
        }
        if glassesStatus.connected || glassesStatus.connectionState != .disconnected {
            DeviceManager.shared.disconnect()
            shouldRestoreGlassesOnBluetoothRestore = true
        }
    }

    /// Reconnect only what `handleBluetoothUnavailable` tore down, never a
    /// connection the user closed themselves (explicit connect/disconnect
    /// calls clear the restore intent).
    private func handleBluetoothRestored() {
        let restoreGlasses = shouldRestoreGlassesOnBluetoothRestore
        let restoreController = shouldRestoreControllerOnBluetoothRestore
        clearBluetoothRestoreIntent()

        if restoreGlasses, !glassesStatus.connected, glassesStatus.connectionState == .disconnected {
            DeviceManager.shared.connectDefault() // also restores the controller
        } else if restoreController, !glassesStatus.controllerConnected {
            DeviceManager.shared.connectDefaultController()
        }
    }

    private func clearBluetoothRestoreIntent() {
        shouldRestoreGlassesOnBluetoothRestore = false
        shouldRestoreControllerOnBluetoothRestore = false
    }

    private func clearBluetoothDiscoveryState() {
        discoveredDeviceNames.removeAll()
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "searching", false)
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "searchingController", false)
        DeviceStore.shared.apply(ObservableStore.bluetoothCategory, "searchResults", [] as [[String: Any]])
    }

    private func cancelActiveScanSessions(reason: ScanStopReason) {
        let ids = Array(activeScanSessions.keys)
        guard !ids.isEmpty else {
            if bluetoothStatus.searching || bluetoothStatus.searchingController {
                stopScan(reason: reason)
            }
            return
        }
        for (index, id) in ids.enumerated() {
            // Stop the underlying scan once (first session); the rest only
            // complete their callbacks.
            finishScanSession(id, reason: reason, shouldStopScan: index == 0)
        }
    }

    private func handleSettingsAckForRequests(_ event: SettingsAckEvent) {
        guard let pending = pendingSettingsRequests[event.requestId] else { return }
        if isFailureStatus(event.status) {
            let fallbackSetting = event.setting.isEmpty ? event.requestId : event.setting
            pending.reject(
                BluetoothSdkError(
                    code: event.errorCode ?? "\(event.setting.isEmpty ? "settings" : event.setting)_failed",
                    message: event.errorMessage ?? "Settings command \(fallbackSetting) failed."
                )
            )
        } else {
            pending.resolve(event)
        }
    }

    private func isFailureStatus(_ status: String) -> Bool {
        ["error", "failed", "failure", "rejected"].contains(status.lowercased())
    }

    private func dispatchStoreUpdate(_ category: String, _ changes: [String: Any]) {
        switch ObservableStore.normalizeCategory(category) {
        case "glasses":
            let nextState = state
            delegate?.mentraBluetoothSDK(self, didUpdate: nextState)
            delegate?.mentraBluetoothSDK(self, didUpdateGlasses: nextState.glasses)
        case ObservableStore.bluetoothCategory:
            let nextState = state
            delegate?.mentraBluetoothSDK(self, didUpdate: nextState)
            delegate?.mentraBluetoothSDK(self, didUpdateSdkState: nextState.sdk)
            delegate?.mentraBluetoothSDK(self, didUpdateScan: nextState.scan)
            if !suppressDefaultDeviceEvents && changes.keys.contains(where: { defaultDeviceKeys.contains($0) }) {
                dispatchDefaultDeviceChanged()
            }
            dispatchDiscoveredDevices(changes["searchResults"])
            dispatchScanResults(changes["searchResults"])
        default:
            break
        }
    }

    private func dispatchDefaultDeviceChanged() {
        delegate?.mentraBluetoothSDK(self, didChangeDefaultDevice: currentDefaultDevice())
    }

    private func finishDefaultDeviceApply(generation: Int) {
        Task { @MainActor [weak self] in
            guard let self, generation == self.defaultDeviceApplyGeneration else { return }
            self.suppressDefaultDeviceEvents = false
            self.dispatchDefaultDeviceChanged()
        }
    }

    private func currentDefaultDevice() -> Device? {
        let core = DeviceStore.shared.store.getCategory(ObservableStore.bluetoothCategory)
        guard let model = core["default_wearable"] as? String, !model.isEmpty else { return nil }
        guard let name = core["device_name"] as? String, !name.isEmpty else { return nil }
        let identifier = (core["device_address"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Device(
            model: DeviceModel.fromDeviceType(model),
            name: name,
            identifier: identifier
        )
    }

    private func dispatchDiscoveredDevices(_ rawSearchResults: Any?) {
        guard let results = rawSearchResults as? [[String: Any]] else { return }
        for result in results {
            guard let name = result["name"] as? String else { continue }
            guard discoveredDeviceNames.insert(name).inserted else { continue }
            guard let device = Device(values: result) else { continue }
            delegate?.mentraBluetoothSDK(self, didDiscover: device)
        }
    }

    private func dispatchScanResults(_ rawSearchResults: Any?) {
        guard let results = rawSearchResults as? [[String: Any]] else { return }
        let devices = results.compactMap(Device.init(values:))
        for id in Array(activeScanSessions.keys) {
            guard let activeSession = activeScanSessions[id] else { continue }
            emitScanResults(devices.filter { $0.model == activeSession.model }, forSession: id)
        }
    }

    private func emitScanResults(_ devices: [Device], forSession id: UUID) {
        guard let activeSession = activeScanSessions[id] else { return }
        activeSession.latestResults = devices
        activeSession.onResults(devices)
    }

    private func finishScanSession(_ id: UUID, reason: ScanStopReason, shouldStopScan: Bool) {
        guard let activeSession = activeScanSessions.removeValue(forKey: id) else { return }
        activeSession.timeoutTask?.cancel()
        activeSession.publicSession?.markStopped()
        if shouldStopScan {
            stopScan(reason: reason)
        }
        activeSession.onComplete(activeSession.latestResults)
    }

    private func dispatchBridgeEvent(_ eventName: String, _ data: [String: Any]) {
        switch eventName {
        case "log":
            delegate?.mentraBluetoothSDK(self, didLog: data["message"] as? String ?? data.description)
        case "button_press":
            let event = ButtonPressEvent(
                buttonId: data["buttonId"] as? String ?? "",
                pressType: data["pressType"] as? String ?? "",
                timestamp: intValue(data["timestamp"])
            )
            delegate?.mentraBluetoothSDK(self, didReceive: .buttonPress(event))
        case "touch_event":
            delegate?.mentraBluetoothSDK(self, didReceive: .touch(TouchEvent(values: data)))
        case "mic_pcm":
            let event = MicPcmEvent(values: data)
            if !event.pcm.isEmpty {
                delegate?.mentraBluetoothSDK(self, didReceiveMicPcm: event)
            }
        case "mic_lc3":
            let event = MicLc3Event(values: data)
            if !event.lc3.isEmpty {
                delegate?.mentraBluetoothSDK(self, didReceiveMicLc3: event)
            }
        case "local_transcription":
            let event = LocalTranscriptionEvent(
                text: data["text"] as? String ?? "",
                isFinal: data["isFinal"] as? Bool ?? false,
                values: data
            )
            delegate?.mentraBluetoothSDK(self, didReceive: .localTranscription(event))
        case "voice_activity_detection_status":
            delegate?.mentraBluetoothSDK(
                self,
                didReceive: .voiceActivityDetectionStatus(VoiceActivityDetectionStatusEvent(values: data))
            )
        case "speaking_status":
            delegate?.mentraBluetoothSDK(
                self,
                didReceive: .speakingStatus(SpeakingStatusEvent(values: data))
            )
        case "ota_start_ack":
            var values = data
            values["type"] = "ota_start_ack"
            let event = OtaStartAckEvent(values: values)
            pendingOtaStart?.resolve(event)
            delegate?.mentraBluetoothSDK(self, didReceive: .otaStartAck(event))
        case "ota_status":
            var resultValues = data
            resultValues["type"] = "ota_status"
            pendingOtaQuery?.resolve(OtaQueryResult(values: resultValues))
            delegate?.mentraBluetoothSDK(self, didReceive: .otaStatus(OtaStatusEvent(values: resultValues)))
        case "settings_ack":
            let event = SettingsAckEvent(values: data)
            handleSettingsAckForRequests(event)
            delegate?.mentraBluetoothSDK(self, didReceive: .settingsAck(event))
        case "version_info":
            let event = VersionInfoResult(values: data)
            pendingVersionInfo?.resolve(event)
            delegate?.mentraBluetoothSDK(self, didReceive: .versionInfo(event))
        case "compatible_glasses_search_stop":
            delegate?.mentraBluetoothSDK(self, didStopScan: .completed)
        case "pair_failure":
            delegate?.mentraBluetoothSDK(
                self,
                didFail: BluetoothSdkError(
                    code: "pair_failure",
                    message: data["error"] as? String ?? data.description
                )
            )
        default:
            delegate?.mentraBluetoothSDK(self, didReceive: .raw(name: eventName, values: data))
        }
    }
}
