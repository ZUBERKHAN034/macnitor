@preconcurrency import CoreLocation
@preconcurrency import CoreWLAN
import Foundation
import IOBluetooth
import IOKit
import Network

struct DuoBarSystemState: Equatable {
    var wifi: DuoBarWiFiSignal = .unavailable
    var networkName: String?
    var bluetooth: DuoBarBluetoothState = .unavailable
    var wifiPoweredOn: Bool?
}

struct DuoBarWiFiNetwork: Identifiable, Equatable {
    let ssid: String
    let rssi: Int
    let isSecured: Bool

    var id: String { ssid }

    var signalBars: Int {
        switch rssi {
        case ..<(-85): return 1
        case -85..<(-75): return 2
        case -75..<(-67): return 3
        default: return 4
        }
    }
}

@MainActor
final class DuoBarSystemMonitor: NSObject, @preconcurrency CLLocationManagerDelegate {
    var onChange: ((DuoBarSystemState) -> Void)?
    private let location = CLLocationManager()
    private let path = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.macnitor.duobar-network", qos: .utility)
    private var bluetoothObservers: [NSObjectProtocol] = []
    private var state = DuoBarSystemState()
    private var didRequestLocation = false
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        location.delegate = self
        path.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.updateNetwork(isConnected: path.status == .satisfied) }
        }
        path.start(queue: queue)
        let center = NotificationCenter.default
        bluetoothObservers = [
            .IOBluetoothHostControllerPoweredOn,
            .IOBluetoothHostControllerPoweredOff
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateBluetooth() }
            }
        }
        updateBluetooth()
        updateNetwork(isConnected: path.currentPath.status == .satisfied)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        path.cancel()
        bluetoothObservers.forEach(NotificationCenter.default.removeObserver)
        bluetoothObservers.removeAll()
        location.delegate = nil
    }

    /// Called only when the details popover opens. Location is requested at most once.
    func requestDetails() {
        if location.authorizationStatus == .notDetermined, !didRequestLocation {
            didRequestLocation = true
            location.requestWhenInUseAuthorization()
        }
        updateNetwork(isConnected: path.currentPath.status == .satisfied, readSSID: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized else {
            state.networkName = nil
            publish()
            return
        }
        updateNetwork(isConnected: path.currentPath.status == .satisfied, readSSID: true)
    }

    private func updateNetwork(isConnected: Bool, readSSID: Bool = false) {
        let interface = CWWiFiClient.shared().interface()
        state.wifiPoweredOn = interface?.powerOn()
        let isWiFiPath = path.currentPath.usesInterfaceType(.wifi)
        state.wifi = DuoBarWiFiSignal.resolve(
            isAvailable: interface != nil,
            isConnected: isConnected && isWiFiPath && interface?.powerOn() == true,
            rssi: interface?.rssiValue()
        )
        if readSSID && (location.authorizationStatus == .authorizedAlways || location.authorizationStatus == .authorized) {
            state.networkName = interface?.ssid()
        }
        publish()
    }

    private func updateBluetooth() {
        guard let controller = IOBluetoothHostController.default() else {
            state.bluetooth = .unavailable
            publish()
            return
        }
        state.bluetooth = controller.powerState == kBluetoothHCIPowerStateON ? .on : .off
        publish()
    }

    func scanWiFiNetworks() async -> [DuoBarWiFiNetwork] {
        guard let interface = CWWiFiClient.shared().interface() else { return [] }
        return await Task.detached(priority: .userInitiated) {
            guard let networks = try? interface.scanForNetworks(withSSID: nil) else { return [] }
            var seen = Set<String>()
            return networks
                .compactMap { network -> DuoBarWiFiNetwork? in
                    guard let ssid = network.ssid, !ssid.isEmpty, seen.insert(ssid).inserted else { return nil }
                    return DuoBarWiFiNetwork(
                        ssid: ssid,
                        rssi: network.rssiValue,
                        isSecured: network.supportsSecurity(.wpa2Personal)
                            || network.supportsSecurity(.wpa3Personal)
                            || network.supportsSecurity(.wpa2Enterprise)
                            || network.supportsSecurity(.wpa3Enterprise)
                    )
                }
                .sorted { $0.rssi > $1.rssi }
        }.value
    }

    func joinWiFi(ssid: String, password: String?) async -> Bool {
        guard let interface = CWWiFiClient.shared().interface() else { return false }
        return await Task.detached(priority: .userInitiated) {
            guard let data = ssid.data(using: .utf8),
                  let networks = try? interface.scanForNetworks(withSSID: data),
                  let target = networks.first(where: { $0.ssid == ssid }) else { return false }
            do {
                try interface.associate(to: target, password: password)
                return true
            } catch {
                return false
            }
        }.value
    }

    private func publish() { onChange?(state) }
}
