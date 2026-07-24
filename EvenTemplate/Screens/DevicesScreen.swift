import SwiftUI

struct DevicesScreen: View {
    @EnvironmentObject private var session: BluetoothSession

    @State private var heyEvenEnabled = false
    @State private var hideBuiltinMenuApps = true
    @State private var splashSeconds = 2
    @State private var dashboardAutoClose = -1
    @State private var brightness = 50.0
    @State private var autoBrightness = true
    @State private var displayDistance = 2
    @State private var displayHeight = 4
    @State private var headUpAngle = 30

    /// Dashboard auto-close choices. -1 leaves the glasses' own value alone,
    /// 0 is the firmware's "never close" sentinel, and 240s is the longest
    /// timer the firmware accepts.
    private static let autoCloseOptions: [(seconds: Int, label: String)] = [
        (-1, "Glasses default"),
        (0, "Never"),
        (5, "5s"),
        (10, "10s"),
        (15, "15s"),
        (30, "30s"),
        (60, "1m"),
        (120, "2m"),
        (240, "4m"),
    ]

    private static let supportedModels: [(model: DeviceModel, label: String, note: String)] = [
        (.g1, "Even Realities G1", "Glasses pair as two BLE devices (left + right arm)."),
        (.g2, "Even Realities G2", "Glasses pair as two BLE devices (left + right arm)."),
        (.r1, "Even Realities R1 ring", "Input ring. Pair the G2 first — the ring is linked to the glasses."),
    ]

    var body: some View {
        Form {
            Section("Scan") {
                ForEach(Self.supportedModels, id: \.model) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Scan for \(entry.label)") {
                            session.startScan(entry.model)
                        }
                        Text(entry.note)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                if session.scan.active {
                    HStack {
                        ProgressView()
                        Text("Scanning…")
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Stop") {
                            session.stopScan()
                        }
                    }
                }
            }

            if !session.scan.devices.isEmpty {
                Section("Nearby devices") {
                    ForEach(session.scan.devices) { device in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name)
                                Text(deviceMeta(device))
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Connect") {
                                session.connect(device)
                            }
                        }
                    }
                }
            }

            Section("Status") {
                meta("Connection", session.glasses.connection.rawValue.lowercased())
                if session.glasses.connected {
                    meta("Ready", session.glasses.ready ? "yes" : "booting…")
                    meta("Model", session.glasses.device?.deviceModel?.rawValue ?? "unknown")
                    meta("Bluetooth name", session.glasses.device?.bluetoothName ?? "unknown")
                    meta("Battery", batteryText)
                    meta("Firmware", session.glasses.device?.firmwareVersion ?? session.glasses.firmware?.version ?? "unknown")
                    if let dbm = session.glasses.signal?.strengthDbm {
                        meta("Signal", "\(dbm) dBm")
                    }
                } else {
                    Text("Not connected. Scan and pick a device above, or reconnect the saved default below.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                if let defaultDevice = session.defaultDevice {
                    meta("Default device", defaultDevice.name)
                }
                if let error = session.lastError {
                    meta("Last error", error.message)
                }
            }

            Section("Display") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Auto brightness", isOn: $autoBrightness)
                    Text("Let the glasses set brightness from their ambient light sensor.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Brightness")
                        Spacer()
                        Text("\(Int(brightness))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $brightness, in: 0...100, step: 5)
                        .disabled(autoBrightness)
                    Text(autoBrightness
                         ? "Turn off auto brightness to set the level by hand."
                         : "Applies as you drag; the write is debounced so only the value you land on is sent.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Stepper("Distance: \(displayDistance)", value: $displayDistance, in: 0...2)
                    Text("How far the image sits from you (0 = nearest, 2 = furthest). Applies immediately while connected.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Stepper("Height: \(displayHeight)", value: $displayHeight, in: 0...12)
                    Text("Where the image sits vertically in the lens (0 = lowest, 12 = highest). Applies immediately while connected.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Stepper("Head-up angle: \(headUpAngle)\u{00B0}", value: $headUpAngle, in: 0...60, step: 5)
                    Text("How far you tilt your head back before the display raises. Lower triggers sooner.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("Glasses settings") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Dashboard auto-close", selection: $dashboardAutoClose) {
                        ForEach(Self.autoCloseOptions, id: \.seconds) { option in
                            Text(option.label).tag(option.seconds)
                        }
                    }
                    Text("How long the dashboard stays up before the glasses close it and blank the lens. \u{201C}Glasses default\u{201D} leaves whatever the glasses already have.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("\u{201C}Hey Even\u{201D} wake word", isOn: $heyEvenEnabled)
                    Text("Lets the glasses listen for \u{201C}Hey Even\u{201D} voice commands. Applies immediately when connected.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Stepper(
                        splashSeconds > 0
                            ? "Splash duration: \(splashSeconds)s"
                            : "Splash duration: off",
                        value: $splashSeconds,
                        in: 0...10
                    )
                    Text("How long \u{201C}-- template --\u{201D} holds on the glasses when they connect, before it clears and the dashboard takes over. Set to off to skip the splash. Applies on the next connect.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Hide built-in menu apps", isOn: $hideBuiltinMenuApps)
                    Text("Removes Even AI, Teleprompt, Translate, Navigate, and Conversate from the glasses menu, keeping Notification. Turning this off restores the stock menu on the next reconnect.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section("Actions") {
                Button("Reconnect default device") {
                    session.connectDefault()
                }
                Button("Disconnect") {
                    session.disconnect()
                }
                Button("Forget default device", role: .destructive) {
                    session.clearDefaultDevice()
                }
                #if DEBUG
                Button("Connect simulated glasses") {
                    session.sdk.connectSimulated()
                }
                #endif
            }
        }
        .onAppear {
            heyEvenEnabled = session.sdk.heyEvenEnabled
            hideBuiltinMenuApps = session.sdk.builtinMenuAppsHidden
            splashSeconds = session.sdk.splashDurationSeconds
            dashboardAutoClose = session.sdk.dashboardAutoCloseSeconds
            brightness = Double(session.sdk.brightness)
            autoBrightness = session.sdk.autoBrightness
            displayDistance = session.sdk.displayDistance
            displayHeight = session.sdk.displayHeight
            headUpAngle = session.sdk.headUpAngle
        }
        .onChange(of: brightness) { level in
            session.sdk.setBrightnessLevel(Int(level))
        }
        .onChange(of: autoBrightness) { enabled in
            session.sdk.setAutoBrightnessEnabled(enabled)
        }
        .onChange(of: displayDistance) { level in
            session.sdk.setDisplayDistance(level)
        }
        .onChange(of: displayHeight) { level in
            session.sdk.setDisplayHeight(level)
        }
        .onChange(of: headUpAngle) { degrees in
            session.sdk.setHeadUpAngleLevel(degrees)
        }
        .onChange(of: dashboardAutoClose) { seconds in
            session.sdk.setDashboardAutoCloseSeconds(seconds)
        }
        .onChange(of: splashSeconds) { seconds in
            session.sdk.setSplashDurationSeconds(seconds)
        }
        .onChange(of: heyEvenEnabled) { enabled in
            session.sdk.setHeyEvenEnabled(enabled)
        }
        .onChange(of: hideBuiltinMenuApps) { hidden in
            session.sdk.setBuiltinMenuAppsHidden(hidden)
        }
    }

    private var batteryText: String {
        guard let battery = session.glasses.battery, let level = battery.level else { return "unknown" }
        return "\(level)%\(battery.charging ? " (charging)" : "")"
    }

    private func deviceMeta(_ device: Device) -> String {
        var text = device.model.rawValue
        if let rssi = device.rssi {
            text += " · \(rssi) dBm"
        }
        return text
    }

    private func meta(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
