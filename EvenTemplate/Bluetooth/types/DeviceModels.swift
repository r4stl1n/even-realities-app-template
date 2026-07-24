import Foundation

public struct MentraBluetoothSDKConfiguration {
    public static let `default` = MentraBluetoothSDKConfiguration()

    public init() {}
}

public enum DeviceModel: String {
    case g1
    case g2
    case simulated
    case r1

    public var deviceType: String {
        switch self {
        case .g1:
            DeviceTypes.G1
        case .g2:
            DeviceTypes.G2
        case .simulated:
            DeviceTypes.SIMULATED
        case .r1:
            ControllerTypes.R1
        }
    }

    public static func fromDeviceType(_ deviceType: String?) -> DeviceModel {
        switch deviceType {
        case DeviceTypes.G1:
            .g1
        case DeviceTypes.G2:
            .g2
        case DeviceTypes.SIMULATED:
            .simulated
        case ControllerTypes.R1:
            .r1
        default:
            // Unknown/absent device type falls back to the template's primary
            // target (was Mentra Live before the non-Even drivers were removed).
            .g2
        }
    }
}

public struct Device: Identifiable, Equatable, CustomStringConvertible {
    public let model: DeviceModel
    public let name: String
    /// CoreBluetooth identifier when available.
    public let identifier: String?
    public let rssi: Int?
    /// Stable app-facing scan-result key. Do not parse; use typed fields instead.
    public let id: String

    public init(
        model: DeviceModel,
        name: String,
        identifier: String? = nil,
        rssi: Int? = nil,
        id: String? = nil
    ) {
        self.model = model
        self.name = name
        self.identifier = identifier
        self.rssi = rssi
        self.id = id ?? identifier.flatMap { $0.isEmpty ? nil : $0 } ?? "\(model.deviceType):\(name)"
    }

    public var description: String {
        "Device(model: \(model), name: \(name))"
    }

    var dictionary: [String: Any] {
        var values: [String: Any] = [
            "id": id,
            "model": model.deviceType,
            "name": name,
        ]
        if let identifier, !identifier.isEmpty {
            values["address"] = identifier
        }
        if let rssi {
            values["rssi"] = rssi
        }
        return values
    }

    init?(values: [String: Any]) {
        guard let model = stringValue(values, "model") else { return nil }
        guard let name = stringValue(values, "name") else { return nil }
        let identifier = stringValue(values, "address").flatMap { $0.isEmpty ? nil : $0 }
        let rssi = intValue(values["rssi"])
        self.init(
            model: DeviceModel.fromDeviceType(model),
            name: name,
            identifier: identifier,
            rssi: rssi,
            id: stringValue(values, "id")
        )
    }
}

public struct ConnectOptions {
    public let saveAsDefault: Bool
    public let cancelExistingConnectionAttempt: Bool

    public init(saveAsDefault: Bool = true, cancelExistingConnectionAttempt: Bool = true) {
        self.saveAsDefault = saveAsDefault
        self.cancelExistingConnectionAttempt = cancelExistingConnectionAttempt
    }
}
