# Even Template — smart glasses + ring template

A native iOS (SwiftUI) template app for building against:

- **Even Realities G1** smart glasses
- **Even Realities G2** smart glasses
- **Even Realities R1** smart ring

The Bluetooth stack is **first-party code** in this repo at `EvenTemplate/Bluetooth/`
(originally derived from the MIT-licensed
[MentraOS](https://github.com/Mentra-Community/MentraOS) bluetooth-sdk and now
maintained here). All BLE protocol handling — scanning, dual-arm pairing,
display rendering, LC3 mic audio, ring gestures — is implemented in Swift, with
the LC3 codec compiled from C in `EvenTemplate/LC3/`.

The device drivers, if you want to read or modify the protocols directly:

- G1: `EvenTemplate/Bluetooth/sgcs/G1.swift`
- G2: `EvenTemplate/Bluetooth/sgcs/G2.swift`
- R1 ring: `EvenTemplate/Bluetooth/controllers/R1.swift`

## What the app demonstrates

| Tab | Feature |
| --- | --- |
| Devices | Scan for G1 / G2 / R1, connect, disconnect, forget; connection state, battery, firmware, signal |
| Notifs | Notification viewer: an in-app inbox rendered on the glasses. Browse with the touchpad or R1 ring (swipe down / tap = next, swipe up = previous, double-tap = dismiss), optionally shown only when the wearer looks up (head-up detection) |
| Display | Send a text wall to the glasses display; clear the display |
| Input | Live log of touchpad gestures (glasses), ring gestures (tap / double-tap / hold / swipe), button presses, head-up, battery events |
| Mic | Toggle the glasses or phone microphone and watch 16 kHz PCM frames arrive with a live level meter |

The notification viewer (`EvenTemplate/GlassesNotificationViewer.swift`) is the
pattern to copy for new "apps": an `ObservableObject` that subscribes to the
session's device events (gestures, head-up) and renders with `displayText`,
plus a phone screen bound to it.

**OS notifications** are handled by the platform, not the app: paired glasses
receive notifications directly from iOS via ANCS once the user enables
"Share System Notifications" for the device in Settings → Bluetooth.
Third-party apps cannot read other apps' notifications on iOS, so the in-app
inbox is manual/programmatic only.

## Requirements

- Xcode 16+
- A **physical** iPhone (iOS 15.1+) — BLE does not work in the simulator

## Getting started

```sh
open EvenTemplate.xcodeproj
```

Select your device and run. Or from the command line:

```sh
xcodebuild -project EvenTemplate.xcodeproj -scheme "Even Template" -destination "generic/platform=iOS Simulator" build
```

Debug builds include a **"Connect simulated glasses"** button on the Devices
tab that drives the `Simulated` driver (`EvenTemplate/Bluetooth/sgcs/Simulated.swift`)
so you can exercise the display/viewer logic without hardware.

## Pairing notes per device

### Even Realities G1 and G2 (glasses)

- Both models pair as **two BLE peripherals** — the left and right arms are
  separate devices (advertised names contain `_L_` and `_R_`). The stack
  handles discovering, ordering, and bonding both arms; you just connect the
  scan result.
- If the glasses are already paired to the official Even Realities app,
  disconnect them there first — they only hold one BLE connection.
- G1 uses a Nordic-UART-based protocol; G2 uses the EvenHub protocol
  (576×288 display canvas). Both are abstracted behind the same
  `displayText` / `clearDisplay` / `setMicState` API.

### Even Realities R1 (ring)

- The ring is an **input controller**, not standalone glasses: it has no
  display or microphone, and it is designed to be linked with G2 glasses.
- **Pair the G2 first, then the ring.** When both are connected the stack
  exchanges the link handshake (it tells the ring the glasses' MAC address and
  tells the glasses about the ring) automatically.
- Ring gestures arrive as touch events with `gestureName` of `single_tap`,
  `double_tap`, `hold`, `swipe_up`, or `swipe_down`.

## Key API surface used by this template

The entry point is the `MentraBluetoothSDK` facade
(`EvenTemplate/Bluetooth/MentraBluetoothSDK.swift`), wrapped for SwiftUI by
`EvenTemplate/BluetoothSession.swift`:

```swift
let sdk = MentraBluetoothSDK()
sdk.delegate = self // MentraBluetoothSDKDelegate

// Scan + connect (same API for glasses and the ring)
try sdk.startScan(model: .g2)
// devices arrive via delegate didUpdateScan / didDiscover
try sdk.connect(to: device)

// Display (G1/G2 only)
try await sdk.displayText("Hello")
try await sdk.clearDisplay()

// Microphone (glasses mic = LC3 over BLE, decoded to PCM natively)
sdk.setMicState(enabled: true, useGlassesMic: true)

// Events (delegate)
func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didReceive event: BluetoothEvent) {
    if case let .touch(touch) = event { print(touch.gestureName ?? "", touch.deviceModel ?? "") }
}
func mentraBluetoothSDK(_ sdk: MentraBluetoothSDK, didReceiveMicPcm event: MicPcmEvent) {
    // event.pcm: Data, 16 kHz s16le mono
}
```

Lower-level access: `DeviceManager.shared` owns the active glasses driver
(`sgc`) and ring controller; `DeviceStore.shared` is the observable state
store behind the runtime-state structs.

## Permissions

Declared in `EvenTemplate/Info.plist`:

- `NSBluetoothAlwaysUsageDescription` (CoreBluetooth prompts on first use)
- `NSMicrophoneUsageDescription` for the phone-mic path
- `UIBackgroundModes: [bluetooth-central, audio]` to keep the BLE link alive
  in the background

## Going further

- **Even devices only.** The G1, G2, and R1 are the supported hardware; the
  drivers for other vendors' glasses (Mentra Live, Nimo, Brilliant Frame) and
  their supporting code have been removed.
- **No camera, WiFi, or streaming.** No Even device has a camera or WiFi radio,
  so the photo/video/gallery/RGB-LED, WiFi/hotspot, and RTMP-streaming surfaces
  were removed entirely rather than left as no-op stubs. If camera-capable
  hardware ever lands, pull those types back from git history (they were
  `camera/CameraModels.swift`, `streaming/StreamModels.swift`, and
  `status/WifiHotspotStatus.swift`) along with their `SGCManager` members.
- The upstream [MentraOS repo](https://github.com/Mentra-Community/MentraOS)
  (`mobile/modules/bluetooth-sdk`) remains useful as a reference for protocol
  fixes, though this codebase has diverged and syncs are manual.
- Removed relative to upstream: the Expo/React Native bridge, Android/Kotlin
  code, on-device STT/TTS (SherpaOnnx), and all non-Even device drivers.
- **This app is local-only.** All telemetry and remote-server code was removed:
  no analytics, no OTA manifest fetch, no incident-log upload. The app makes no
  network requests except to devices on your local network.

## Project layout

```
EvenTemplate.xcodeproj             Xcode project (scheme: "Even Template")
EvenTemplate/
  EvenTemplateApp.swift            App entry: tab shell + shared objects
  BluetoothSession.swift    SwiftUI-facing wrapper around MentraBluetoothSDK
  NotificationStore.swift   In-app notification inbox
  GlassesNotificationViewer.swift  Renders the inbox on the glasses, driven by gestures
  Screens/                  One SwiftUI view per tab
  Bluetooth/                First-party BLE stack (facade, DeviceManager, drivers)
    sgcs/                   Glasses drivers (G1, G2, Simulated) + SGCManager protocol
    controllers/            Ring drivers (R1) + controller manager
    events/, types/, status/  Public event/state types
  LC3/                      LC3 audio codec (C) + PcmConverter (ObjC)
  Info.plist                Permissions + background modes
```
