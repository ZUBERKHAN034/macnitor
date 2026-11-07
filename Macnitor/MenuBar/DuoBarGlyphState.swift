import Foundation

enum DuoBarWiFiSignal: Equatable {
    case strong, medium, weak, disconnected, unavailable

    static func resolve(isAvailable: Bool, isConnected: Bool, rssi: Int?) -> Self {
        guard isAvailable else { return .unavailable }
        guard isConnected else { return .disconnected }
        guard let rssi, rssi < 0 else { return .medium }
        if rssi >= -67 { return .strong }
        if rssi >= -75 { return .medium }
        return .weak
    }
}

enum DuoBarBluetoothState: Equatable {
    case on, off, unavailable
}

struct DuoBarGlyphState: Equatable {
    let batteryProgress: Double?
    let isCharging: Bool
    let wifi: DuoBarWiFiSignal
    let bluetooth: DuoBarBluetoothState

    init(batteryPercentage: Int?, isCharging: Bool, wifi: DuoBarWiFiSignal, bluetooth: DuoBarBluetoothState) {
        batteryProgress = batteryPercentage.map { min(max(Double($0) / 100, 0), 1) }
        self.isCharging = isCharging && batteryPercentage.map { $0 < 100 } == true
        self.wifi = wifi
        self.bluetooth = bluetooth
    }

    var bluetoothDotCount: Int {
        switch bluetooth { case .on: 4; case .off: 0; case .unavailable: 1 }
    }

    var wifiSymbol: String {
        switch wifi {
        case .strong: "wifi"
        case .medium: "wifi"
        case .weak: "wifi"
        case .disconnected, .unavailable: "wifi.slash"
        }
    }
}
