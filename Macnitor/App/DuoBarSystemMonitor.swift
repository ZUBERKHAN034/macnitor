import AppKit
@preconcurrency import CoreLocation
@preconcurrency import CoreWLAN
import Foundation
import IOBluetooth
import IOKit
import Network

@_silgen_name("IOBluetoothPreferenceSetControllerPowerState")
private func setBluetoothControllerPowerState(_ state: Int32)

struct DuoBarSystemState: Equatable {
    var wifi: DuoBarWiFiSignal = .unavailable
    var networkName: String?
    var networkNameAvailability: DuoBarNetworkNameAvailability = .notRequested
    var bluetooth: DuoBarBluetoothState = .unavailable
    var bluetoothDevices: [DuoBarBluetoothDevice] = []
    var wifiPoweredOn: Bool?
}

struct DuoBarBluetoothDevice: Equatable, Identifiable, Sendable {
    let name: String
    let address: String
    let isConnected: Bool
    let isPaired: Bool
    let majorClass: UInt32
    let minorClass: UInt32

    var id: String { address }

    var iconSymbol: String {
        let normalizedName = name.lowercased()
        if normalizedName.contains("airpods max") { return "airpodsmax" }
        if normalizedName.contains("airpods pro") { return "airpodspro" }
        if normalizedName.contains("airpods") { return "airpods" }
        if normalizedName.contains("beats") { return "headphones" }
        if normalizedName.contains("mouse") { return "magicmouse" }
        if normalizedName.contains("trackpad") { return "trackpad" }
        if normalizedName.contains("keyboard") { return "keyboard" }
        if normalizedName.contains("watch") { return "applewatch" }
        if normalizedName.contains("phone") || normalizedName.contains("iphone") { return "iphone" }
        if normalizedName.contains("ipad") { return "ipad" }
        if majorClass == 4 { return "headphones" }
        if majorClass == 5 { return "computermouse" }
        return "wave.3.backward.circle"
    }
}

enum DuoBarNetworkNameAvailability: Equatable {
    case notRequested
    case requestingPermission
    case permissionRequired
    case unavailable
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
    private var latestPath: NWPath?
    private var detailRefreshTimer: Timer?
    private var bluetoothObservers: [NSObjectProtocol] = []
    private var bluetoothConnectNotification: IOBluetoothUserNotification?
    private var bluetoothRefreshTimer: Timer?
    private var isBluetoothRefreshInProgress = false
    private var bluetoothRefreshGeneration: UInt64 = 0
    private var lastBluetoothState: DuoBarBluetoothState?
    private var lastBluetoothDevices: [DuoBarBluetoothDevice]?
    private var activationObserver: NSObjectProtocol?
    private var state = DuoBarSystemState()
    private var didRequestLocation = false
    private var isWaitingForActivation = false
    private var isSSIDReadingEnabled = false
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        location.delegate = self
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.requestLocationWhenActive() }
        }
        path.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.latestPath = path
                self?.updateNetwork(path: path)
            }
        }
        path.start(queue: queue)
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateNetwork() }
        }
        detailRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        let center = NotificationCenter.default
        bluetoothObservers = [
            .IOBluetoothHostControllerPoweredOn,
            .IOBluetoothHostControllerPoweredOff
        ].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateBluetooth() }
            }
        }
        bluetoothConnectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceDidConnect(_:device:))
        )
        let bluetoothTimer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateBluetooth() }
        }
        bluetoothRefreshTimer = bluetoothTimer
        RunLoop.main.add(bluetoothTimer, forMode: .common)
        updateBluetooth()
        updateNetwork()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        path.cancel()
        detailRefreshTimer?.invalidate()
        detailRefreshTimer = nil
        isSSIDReadingEnabled = false
        isWaitingForActivation = false
        bluetoothObservers.forEach(NotificationCenter.default.removeObserver)
        bluetoothObservers.removeAll()
        bluetoothConnectNotification?.unregister()
        bluetoothConnectNotification = nil
        bluetoothRefreshTimer?.invalidate()
        bluetoothRefreshTimer = nil
        bluetoothRefreshGeneration &+= 1
        isBluetoothRefreshInProgress = false
        lastBluetoothState = nil
        lastBluetoothDevices = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        location.delegate = nil
    }

    /// Called only when the details popover opens. Location is requested at most once.
    func requestDetails() {
        isSSIDReadingEnabled = true
        if location.authorizationStatus == .notDetermined, !didRequestLocation {
            isWaitingForActivation = true
            state.networkNameAvailability = .requestingPermission
            publish()
            requestLocationWhenActive()
        }
        updateNetwork(readSSID: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized else {
            state.networkName = nil
            if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                isWaitingForActivation = false
            }
            state.networkNameAvailability = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
                ? .permissionRequired
                : (didRequestLocation ? .requestingPermission : .notRequested)
            publish()
            return
        }
        isWaitingForActivation = false
        updateNetwork(readSSID: true)
    }

    private func requestLocationWhenActive() {
        guard isWaitingForActivation,
              !didRequestLocation,
              location.authorizationStatus == .notDetermined,
              NSApp.isActive else { return }
        isWaitingForActivation = false
        didRequestLocation = true
        location.requestWhenInUseAuthorization()
        updateNetwork(readSSID: true)
    }

    private func updateNetwork(path observedPath: NWPath? = nil, readSSID: Bool = false) {
        let currentPath = observedPath ?? latestPath ?? path.currentPath
        let isConnected = currentPath.status == .satisfied
        latestPath = currentPath
        let activeWiFiInterface = currentPath.availableInterfaces.first {
            $0.type == .wifi && currentPath.usesInterfaceType(.wifi)
        }
        let client = CWWiFiClient.shared()
        let interface = activeWiFiInterface.flatMap { client.interface(withName: $0.name) } ?? client.interface()
        state.wifiPoweredOn = interface?.powerOn()
        let isWiFiPath = currentPath.usesInterfaceType(.wifi)
        let isWiFiConnected = isConnected && isWiFiPath && interface?.powerOn() == true
        state.wifi = DuoBarWiFiSignal.resolve(
            isAvailable: interface != nil,
            isConnected: isWiFiConnected,
            rssi: interface?.rssiValue()
        )

        if readSSID || isSSIDReadingEnabled {
            if isWiFiConnected {
                let name = interface?.ssid()?.trimmingCharacters(in: .whitespacesAndNewlines)
                state.networkName = name?.isEmpty == false ? name : nil
            } else {
                state.networkName = nil
            }

            if state.networkName != nil {
                state.networkNameAvailability = .notRequested
            } else {
                switch location.authorizationStatus {
                case .authorizedAlways, .authorized:
                    state.networkNameAvailability = .unavailable
                case .denied, .restricted:
                    state.networkNameAvailability = .permissionRequired
                case .notDetermined:
                    state.networkNameAvailability = didRequestLocation ? .requestingPermission : .notRequested
                @unknown default:
                    state.networkNameAvailability = .unavailable
                }
            }
        } else if !isWiFiConnected {
            state.networkName = nil
            state.networkNameAvailability = .notRequested
        }
        publish()
    }

    private func updateBluetooth() {
        guard isStarted, !isBluetoothRefreshInProgress else { return }
        isBluetoothRefreshInProgress = true
        let generation = bluetoothRefreshGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status: (DuoBarBluetoothState, [DuoBarBluetoothDevice])
            if let controller = IOBluetoothHostController.default() {
                let isPoweredOn = controller.powerState == kBluetoothHCIPowerStateON
                let devices: [DuoBarBluetoothDevice]
                if isPoweredOn, let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] {
                    devices = pairedDevices.compactMap { device in
                        guard let address = device.addressString, !address.isEmpty else { return nil }
                        return DuoBarBluetoothDevice(
                            name: device.nameOrAddress ?? device.name ?? address,
                            address: address,
                            isConnected: device.isConnected(),
                            isPaired: device.isPaired(),
                            majorClass: UInt32(device.deviceClassMajor),
                            minorClass: UInt32(device.deviceClassMinor)
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.isConnected != rhs.isConnected { return lhs.isConnected }
                        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                    }
                } else {
                    devices = []
                }
                status = (isPoweredOn ? .on : .off, devices)
            } else {
                status = (.unavailable, [])
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.bluetoothRefreshGeneration == generation else { return }
                self.isBluetoothRefreshInProgress = false
                guard self.isStarted else { return }
                guard self.lastBluetoothState != status.0 || self.lastBluetoothDevices != status.1 else { return }
                self.lastBluetoothState = status.0
                self.lastBluetoothDevices = status.1
                self.state.bluetooth = status.0
                self.state.bluetoothDevices = status.1
                self.publish()
            }
        }
    }

    @objc private func bluetoothDeviceDidConnect(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        updateBluetooth()
    }

    func refreshBluetooth() {
        updateBluetooth()
    }

    func setBluetoothPower(_ enabled: Bool) {
        setBluetoothControllerPowerState(enabled ? 1 : 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateBluetooth()
        }
    }

    func setBluetoothDeviceConnection(address: String, connected: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let device = IOBluetoothDevice(addressString: address) else {
                    continuation.resume(returning: false)
                    return
                }
                let result = connected ? device.openConnection() : device.closeConnection()
                let succeeded = connected
                    ? result == kIOReturnSuccess || device.isConnected()
                    : result == kIOReturnSuccess || !device.isConnected()
                DispatchQueue.main.asyncAfter(deadline: .now() + (connected ? 1.0 : 0.8)) {
                    self?.updateBluetooth()
                }
                continuation.resume(returning: succeeded)
            }
        }
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
