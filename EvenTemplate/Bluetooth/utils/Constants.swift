struct DeviceTypes {
    static let SIMULATED = "Simulated Glasses"
    static let G1 = "Even Realities G1"
    static let G2 = "Even Realities G2"

    static let ALL = [
        SIMULATED,
        G1,
        G2,
    ]

    /// Private init to prevent instantiation
    private init() {}
}

struct ControllerTypes {
    static let R1 = "Even Realities R1"

    static let ALL = [
        R1,
    ]

    /// Private init to prevent instantiation
    private init() {}
}

struct ConnTypes {
    static let CONNECTING = "CONNECTING"
    static let CONNECTED = "CONNECTED"
    static let DISCONNECTED = "DISCONNECTED"
    static let SCANNING = "SCANNING"
    static let BONDING = "BONDING"

    /// Private init to prevent instantiation
    private init() {}
}

struct MicTypes {
    static let PHONE_INTERNAL = "phone"
    static let GLASSES_CUSTOM = "glasses"
    static let BLUETOOTH_CLASSIC = "bluetoothClassic"
    static let BLUETOOTH = "bluetooth"

    static let ALL = [
        PHONE_INTERNAL,
        GLASSES_CUSTOM,
        BLUETOOTH_CLASSIC,
        BLUETOOTH,
    ]

    /// Private init to prevent instantiation
    private init() {}
}

enum MicMap {
    static var map: [String: [String]] = [
        "auto": [
            MicTypes.GLASSES_CUSTOM, MicTypes.PHONE_INTERNAL, MicTypes.BLUETOOTH, MicTypes.BLUETOOTH_CLASSIC,
        ],
        "glasses": [MicTypes.GLASSES_CUSTOM],
        "phone": [MicTypes.PHONE_INTERNAL, MicTypes.GLASSES_CUSTOM],
        "bluetooth": [MicTypes.BLUETOOTH, MicTypes.BLUETOOTH_CLASSIC, MicTypes.PHONE_INTERNAL, MicTypes.GLASSES_CUSTOM],
    ]
}
