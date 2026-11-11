import AppKit
import SwiftUI
import MetricsKit

/// DuoBar controls arranged in compact status rows while retaining Macnitor's selected
/// Dashboard surface and material.
struct DuoBarPopoverView: View {
    @Bindable var model: AppModel

    private var battery: MetricSample? { model.latest[.battery] }
    private var batteryPercent: Int? { battery.map { Int(($0.normalized * 100).rounded()) } }
    private var isNetworkConnected: Bool { NetworkInfo.primaryIPv4() != nil }
    private var isBatteryConnected: Bool { model.isOnBattery == false }
    private var isBatteryCharging: Bool { (battery?.detail["charging"] ?? 0) > 0 }
    private var isChargeLimitHolding: Bool { (battery?.detail["systemChargeLimitReached"] ?? 0) > 0 }
    private var isFullyCharged: Bool { (battery?.detail["fullyCharged"] ?? 0) > 0 }

    @State private var wifiNetworks: [DuoBarWiFiNetwork] = []
    @State private var isScanningWiFi = false
    @State private var wifiPasswordTarget: DuoBarWiFiNetwork?
    @State private var wifiPassword = ""
    @State private var isJoiningWiFi = false
    @State private var wifiJoinFailed = false
    @State private var isWiFiExpanded = false

    @State private var isBatteryExpanded = false
    @State private var lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var isUpdatingLowPowerMode = false
    @State private var lowPowerModeError: String?
    @State private var isBluetoothExpanded = false
    @State private var connectingBluetoothAddress: String?
    @State private var hoveredBluetoothAddress: String?

    var body: some View {
        VStack(spacing: ExperienceSpacing.small) {
            networkRow
            if isWiFiExpanded {
                wifiNetworksSection
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
            }
            bluetoothHeader
            if isBluetoothExpanded {
                bluetoothSection
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
            }
            batteryRow
            if isBatteryExpanded {
                batteryDetailsSection
                    .transition(.opacity.animation(.easeInOut(duration: 0.18)))
            }
            volumeRow
            HStack(spacing: ExperienceSpacing.small) {
                audioDeviceMenu(
                    title: "Audio Output",
                    symbol: "hifispeaker",
                    devices: model.duoBarAudioOutputs,
                    selectedUID: model.duoBarSelectedOutputUID,
                    emptyMessage: "No output devices",
                    onSelect: { model.onDuoBarOutputSelected?($0) }
                )
                audioDeviceMenu(
                    title: "Audio Input",
                    symbol: "mic",
                    devices: model.duoBarAudioInputs,
                    selectedUID: model.duoBarSelectedInputUID,
                    emptyMessage: "No input devices",
                    onSelect: { model.onDuoBarInputSelected?($0) }
                )
            }
        }
        .padding(12)
        .frame(width: DashboardPopoverView.width)
        .onAppear {
            // Wait for the accessory app and popover to activate before asking for
            // Location access, as DuoBar does for its status popover.
            DispatchQueue.main.async { model.onDuoBarPopoverOpened?() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: model.duoBarWiFiPoweredOn) { _, poweredOn in
            guard poweredOn == true, isWiFiExpanded else { return }
            Task { await refreshWiFiNetworks() }
        }
    }

    private var networkRow: some View {
        HStack(spacing: 9) {
            Button(action: toggleWiFiSection) {
                HStack(spacing: 9) {
                    Image(systemName: networkSymbol, variableValue: wifiStrengthVariable)
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityValue(wifiStatusText)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wi-Fi")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(networkDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isWiFiExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Wi-Fi"))

            if let wifiPoweredOn = model.duoBarWiFiPoweredOn {
                Toggle("Wi-Fi", isOn: Binding(
                    get: { wifiPoweredOn },
                    set: { model.onDuoBarWiFiPowerChanged?($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel("Wi-Fi power")
                .help(wifiPoweredOn ? "Turn Wi-Fi off" : "Turn Wi-Fi on")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(controlSurface(cornerRadius: 12))
    }

    private func toggleWiFiSection() {
        isWiFiExpanded.toggle()
        guard isWiFiExpanded else { return }
        Task { await refreshWiFiNetworks() }
    }

    private var wifiNetworksSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "duobar.nearbyNetworks", defaultValue: "Nearby Networks"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isScanningWiFi {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Scanning…")
                } else {
                    Button {
                        Task { await refreshWiFiNetworks() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .disabled(model.duoBarWiFiPoweredOn == false)
                    .accessibilityLabel(Text("Refresh now"))
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            if model.duoBarNetworkNameAvailability == .permissionRequired
                || model.duoBarNetworkNameAvailability == .requestingPermission {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Location access is needed to show Wi-Fi names.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Location Settings…") {
                        model.onDuoBarOpenLocationSettings?()
                    }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            if model.duoBarWiFiPoweredOn == false {
                sectionMessage("Wi-Fi off")
            } else if isScanningWiFi && wifiNetworks.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Scanning…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if wifiNetworks.isEmpty {
                sectionMessage("No networks found")
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 2) {
                        ForEach(wifiNetworks) { network in
                            wifiNetworkRow(network)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 160)
            }

            Divider().padding(.vertical, 4)

            Button {
                model.onOpenWiFiSettings?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wifi").font(.system(size: 11))
                    Text("Wi-Fi Settings…").font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(controlSurface(cornerRadius: 12))
    }

    @ViewBuilder
    private func wifiNetworkRow(_ network: DuoBarWiFiNetwork) -> some View {
        let isCurrent = network.ssid == model.duoBarNetworkName
        VStack(spacing: 0) {
            Button {
                handleWiFiTap(network)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: wifiSignalSymbol(network))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(network.signalBars >= 3 ? Color.secondary : Color.orange)
                        .frame(width: 20)
                    Text(network.ssid)
                        .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if network.isSecured {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    if isCurrent && !isJoiningWiFi {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    } else if isJoiningWiFi && wifiPasswordTarget == network {
                        ProgressView().controlSize(.mini)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            if wifiPasswordTarget == network {
                wifiPasswordForm(network)
            }
        }
    }

    private func wifiPasswordForm(_ network: DuoBarWiFiNetwork) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                SecureField("Password", text: $wifiPassword)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit { joinNetwork(network) }
                Button("Join") { joinNetwork(network) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 11.5, weight: .semibold))
                    .disabled(wifiPassword.isEmpty)
            }
            if wifiJoinFailed {
                Text("Incorrect password")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 7)
    }

    private func handleWiFiTap(_ network: DuoBarWiFiNetwork) {
        wifiJoinFailed = false
        guard network.ssid != model.duoBarNetworkName else { return }
        if network.isSecured {
            wifiPasswordTarget = network
            wifiPassword = ""
        } else {
            Task { @MainActor in await join(network, password: nil) }
        }
    }

    private func joinNetwork(_ network: DuoBarWiFiNetwork) {
        Task { @MainActor in await join(network, password: wifiPassword.isEmpty ? nil : wifiPassword) }
    }

    private func join(_ network: DuoBarWiFiNetwork, password: String?) async {
        isJoiningWiFi = true
        wifiJoinFailed = false
        let success: Bool
        if let handler = model.onDuoBarJoinWiFi {
            success = await handler(network.ssid, password)
        } else {
            success = false
        }
        isJoiningWiFi = false
        if success {
            wifiPasswordTarget = nil
            wifiPassword = ""
            model.onDuoBarRequestDetails?()
        } else {
            wifiJoinFailed = true
        }
    }

    private func refreshWiFiNetworks() async {
        guard !isScanningWiFi else { return }
        isScanningWiFi = true
        if let handler = model.onDuoBarScanWiFi {
            wifiNetworks = await handler()
        } else {
            wifiNetworks = []
        }
        isScanningWiFi = false
    }

    private func wifiSignalSymbol(_ network: DuoBarWiFiNetwork) -> String {
        switch network.signalBars {
        case 4, 3: return "wifi"
        case 2, 1: return "wifi.exclamationmark"
        default: return "wifi.slash"
        }
    }

    private func sectionMessage(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private var volumeRow: some View {
        VStack(spacing: 5) {
            HStack(spacing: 9) {
                Button {
                    model.onDuoBarMuteChanged?(!model.duoBarMuted)
                } label: {
                    Image(systemName: model.duoBarMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!model.duoBarMuteSettable)
                .help(model.duoBarMuted ? "Unmute output" : "Mute output")

                Text("Volume")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(model.duoBarVolume.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { model.duoBarVolume ?? 0 },
                    set: { model.onDuoBarVolumeChanged?($0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            .disabled(!model.duoBarVolumeSettable || model.duoBarVolume == nil)
            .accessibilityLabel("Output volume")
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background(controlSurface(cornerRadius: 12))
    }

    private var batteryRow: some View {
        HStack(spacing: 9) {
            Button {
                isBatteryExpanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    batteryIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Battery")
                            .font(.subheadline.weight(.semibold))
                        Text(batteryStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(batteryPercent.map { "\($0)%" } ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let batteryPowerSourceText {
                            Text(batteryPowerSourceText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }

                    Image(systemName: isBatteryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: .constant(false))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .hidden()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(controlSurface(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Battery"))
        .accessibilityValue(isBatteryExpanded ? Text("Expanded") : Text("Collapsed"))
    }

    private var batteryDetailsSection: some View {
        VStack(spacing: 0) {
            if battery == nil {
                sectionMessage("No internal battery")
            } else {
                Toggle("Low Power Mode", isOn: Binding(
                    get: { lowPowerModeEnabled },
                    set: { setLowPowerMode($0) }
                ))
                .font(.caption)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(isUpdatingLowPowerMode)
                .padding(.vertical, 4)

                Divider().padding(.vertical, 6)

                batteryDetailRow(
                    String(localized: "battery.status", defaultValue: "Status"),
                    batteryStatusText
                )
                if let estimate = batteryEstimateText {
                    batteryDetailRow(batteryEstimateLabel, estimate)
                }
                if let health = battery?.detail["healthPercent"] {
                    batteryDetailRow(
                        String(localized: "battery.health", defaultValue: "Health"),
                        "\(Int(health.rounded()))%"
                    )
                }
                if let cycles = battery?.detail["cycleCount"] {
                    batteryDetailRow(
                        String(localized: "battery.cycles", defaultValue: "Charge cycles"),
                        "\(Int(cycles.rounded()))"
                    )
                }
                if let temperature = battery?.detail["temperature"] {
                    batteryDetailRow(
                        String(localized: "battery.temp", defaultValue: "Temperature"),
                        String(format: "%.1f°C", temperature)
                    )
                }
            }

            Divider().padding(.vertical, 6)

            Button("Battery Settings…", action: openBatterySettings)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(controlSurface(cornerRadius: 12))
        .alert("Couldn’t Change Low Power Mode", isPresented: Binding(
            get: { lowPowerModeError != nil },
            set: { if !$0 { lowPowerModeError = nil } }
        )) {
            Button("OK", role: .cancel) { lowPowerModeError = nil }
        } message: {
            Text(lowPowerModeError ?? "")
        }
    }

    private func batteryDetailRow(_ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
        .font(.caption)
        .padding(.vertical, 4)
    }

    private var batteryEstimateLabel: String {
        BatteryPowerStatus.resolve(battery?.detail ?? [:], isOnBattery: model.isOnBattery).estimateLabel
            ?? String(localized: "battery.timeRemaining", defaultValue: "Time left")
    }

    private var batteryEstimateText: String? {
        let status = BatteryPowerStatus.resolve(battery?.detail ?? [:], isOnBattery: model.isOnBattery)
        guard status.estimateLabel != nil else { return nil }
        guard let estimate = status.estimate(in: battery?.detail ?? [:]) else {
            return String(localized: "battery.calculating", defaultValue: "Calculating…")
        }
        return DashboardFormat.duration(minutes: estimate)
    }

    private var bluetoothSection: some View {
        VStack(spacing: 0) {
            if model.duoBarBluetooth == .off {
                sectionMessage(String(localized: "Bluetooth disabled"))
            } else if model.duoBarBluetooth == .unavailable {
                sectionMessage(String(localized: "Bluetooth unavailable"))
            } else if model.duoBarBluetoothDevices.isEmpty {
                sectionMessage(String(localized: "No devices found"))
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 2) {
                        ForEach(model.duoBarBluetoothDevices) { device in
                            bluetoothDeviceRow(device)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 160)
            }

            Divider().padding(.vertical, 4)

            Button {
                model.onDuoBarOpenBluetoothSettings?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape").font(.system(size: 11))
                    Text("Bluetooth Settings…").font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(controlSurface(cornerRadius: 12))
        .onAppear { model.onDuoBarBluetoothRefresh?() }
    }

    private var bluetoothHeader: some View {
        HStack(spacing: 9) {
            Button {
                isBluetoothExpanded.toggle()
                if isBluetoothExpanded { model.onDuoBarBluetoothRefresh?() }
            } label: {
                HStack(spacing: 9) {
                    bluetoothIcon

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bluetooth")
                            .font(.subheadline.weight(.semibold))
                        Text(bluetoothSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isBluetoothExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Bluetooth"))

            if model.duoBarBluetooth != .unavailable {
                Toggle("Bluetooth power", isOn: Binding(
                    get: { model.duoBarBluetooth == .on },
                    set: { model.onDuoBarBluetoothPowerChanged?($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityLabel(Text("Bluetooth power"))
                .help(String(localized: model.duoBarBluetooth == .on ? "Turn Bluetooth off" : "Turn Bluetooth on"))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(controlSurface(cornerRadius: 12))
    }

    private var bluetoothIcon: some View {
        Group {
            if let image = NSImage(named: NSImage.Name("NSBluetoothTemplate")) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 20)
            } else {
                Image(systemName: "bluetooth")
                    .font(.system(size: 18, weight: .medium))
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private var bluetoothSummary: String {
        switch model.duoBarBluetooth {
        case .off:
            return String(localized: "Bluetooth disabled", defaultValue: "Bluetooth disabled")
        case .unavailable:
            return String(localized: "Unavailable")
        case .on:
            let connectedDevices = model.duoBarBluetoothDevices.filter(\.isConnected)
            switch connectedDevices.count {
            case 0:
                return String(localized: "Not connected", defaultValue: "Not connected")
            case 1:
                return connectedDevices[0].name
            default:
                return String.localizedStringWithFormat(
                    String(localized: "%d devices", defaultValue: "%d devices"),
                    connectedDevices.count
                )
            }
        }
    }

    private func bluetoothDeviceRow(_ device: DuoBarBluetoothDevice) -> some View {
        let isBusy = connectingBluetoothAddress == device.address
        let isHovered = hoveredBluetoothAddress == device.address
        return Button {
            connectOrDisconnectBluetoothDevice(device)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: device.iconSymbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.subheadline.weight(device.isConnected ? .semibold : .regular))
                        .foregroundStyle(device.isConnected ? .primary : .secondary)
                        .lineLimit(1)
                    Text(String(localized: device.isConnected ? "Connected" : "Not connected"))
                        .font(.caption)
                        .foregroundStyle(device.isConnected ? Color.accentColor : Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 16, height: 16)
                } else if device.isConnected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                device.isConnected
                    ? Color.accentColor.opacity(isHovered ? 0.15 : 0.08)
                    : (isHovered ? Color.primary.opacity(0.05) : Color.clear),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hoveredBluetoothAddress = $0 ? device.address : nil }
    }

    private func connectOrDisconnectBluetoothDevice(_ device: DuoBarBluetoothDevice) {
        guard connectingBluetoothAddress == nil else { return }
        connectingBluetoothAddress = device.address
        Task { @MainActor in
            _ = await model.onDuoBarBluetoothDeviceConnectionChanged?(
                device.address,
                !device.isConnected
            )
            try? await Task.sleep(for: .milliseconds(600))
            model.onDuoBarBluetoothRefresh?()
            connectingBluetoothAddress = nil
        }
    }

    private func audioDeviceMenu(
        title: String,
        symbol: String,
        devices: [DuoBarAudioOutput],
        selectedUID: String?,
        emptyMessage: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Menu {
            if devices.isEmpty {
                Text(emptyMessage)
            } else {
                ForEach(devices) { device in
                    Button {
                        onSelect(device.uid)
                    } label: {
                        if device.uid == selectedUID {
                            Label(device.name, systemImage: "checkmark")
                        } else {
                            Text(device.name)
                        }
                    }
                }
            }
            Divider()
            Button("Sound Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(devices.first(where: { $0.uid == selectedUID })?.name ?? emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 10)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(controlSurface(cornerRadius: 12))
        .accessibilityLabel(title)
    }

    private var networkSymbol: String {
        if model.duoBarWiFiSignal == .disconnected || model.duoBarWiFiSignal == .unavailable {
            return isNetworkConnected ? "network" : "wifi.slash"
        }
        return "wifi"
    }

    private var wifiStrengthVariable: Double {
        switch model.duoBarWiFiSignal {
        case .strong: 1
        case .medium: 0.66
        case .weak: 0.33
        case .disconnected, .unavailable: 0
        }
    }

    private var networkDetail: String {
        if let name = model.duoBarNetworkName { return name }
        if model.duoBarWiFiSignal == .disconnected || model.duoBarWiFiSignal == .unavailable {
            return wifiStatusText
        }
        return switch model.duoBarNetworkNameAvailability {
        case .notRequested: String(localized: "Getting Wi-Fi name…")
        case .requestingPermission: String(localized: "Requesting Location Access…")
        case .permissionRequired: String(localized: "Location Access Required")
        case .unavailable: String(localized: "Wi-Fi name unavailable")
        }
    }

    private var batteryIcon: some View {
        Image(systemName: batterySymbol)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(batteryStatusText)
    }

    private var batteryStatusText: String {
        guard battery != nil else {
            return String(localized: "No internal battery", defaultValue: "No internal battery")
        }
        if isChargeLimitHolding {
            return String(localized: "battery.chargingOnHold", defaultValue: "Charging On Hold")
        }
        if isFullyCharged {
            return String(localized: "Fully charged", defaultValue: "Fully charged")
        }
        if isBatteryCharging { return BatteryPowerStatus.charging.localizedName }
        if model.isOnBattery == true { return BatteryPowerStatus.onBattery.localizedName }
        return BatteryPowerStatus.pluggedIn.localizedName
    }

    private var batteryPowerSourceText: String? {
        guard battery != nil else { return nil }
        if isBatteryConnected { return String(localized: "battery.usingAdapter", defaultValue: "Using Adapter") }
        return batteryEstimateText
    }

    private var batterySymbol: String {
        guard battery != nil else { return "battery.0percent" }
        if isFullyCharged { return "battery.100percent" }
        if isBatteryCharging { return "battery.100percent.bolt" }
        switch batteryPercent ?? 0 {
        case 76...100: return "battery.100percent"
        case 51...75: return "battery.75percent"
        case 26...50: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    private var wifiStatusText: String {
        switch model.duoBarWiFiSignal {
        case .strong: "Strong signal"
        case .medium: "Medium signal"
        case .weak: "Weak signal"
        case .disconnected: "Not connected"
        case .unavailable: "Unavailable"
        }
    }

    private func controlSurface(cornerRadius: CGFloat) -> DashboardCardBackground {
        DashboardCardBackground(
            fillOpacity: ExperienceSurface.subtleFillOpacity,
            appearance: model.dashboardAppearance,
            cornerRadius: cornerRadius
        )
    }

    private func openBatterySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func setLowPowerMode(_ enabled: Bool) {
        guard enabled != lowPowerModeEnabled, !isUpdatingLowPowerMode else { return }
        lowPowerModeEnabled = enabled
        isUpdatingLowPowerMode = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (succeeded: Bool, error: String) in
                var authorizationError: NSError?
                let succeeded = DuoBarPowerAuthorization.shared().setLowPowerModeEnabled(
                    enabled,
                    error: &authorizationError
                )
                return (succeeded, authorizationError?.localizedDescription ?? "")
            }.value

            if result.succeeded {
                for _ in 0..<20 {
                    if ProcessInfo.processInfo.isLowPowerModeEnabled == enabled { break }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }

            isUpdatingLowPowerMode = false
            lowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
            if !result.succeeded || lowPowerModeEnabled != enabled {
                let message = result.error.isEmpty
                    ? String(localized: "Low Power Mode could not be changed. You can change it in Battery Settings.")
                    : result.error
                lowPowerModeError = message
            }
        }
    }
}
