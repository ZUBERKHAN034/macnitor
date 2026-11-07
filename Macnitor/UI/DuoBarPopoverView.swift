import SwiftUI
import MetricsKit

/// DuoBar controls arranged in compact status rows while retaining Macnitor's selected
/// Dashboard surface and material.
struct DuoBarPopoverView: View {
    @Bindable var model: AppModel

    private var battery: MetricSample? { model.latest[.battery] }
    private var network: MetricSample? { model.latest[.network] }
    private var batteryPercent: Int? { battery.map { Int(($0.normalized * 100).rounded()) } }
    private var isNetworkConnected: Bool { NetworkInfo.primaryIPv4() != nil }
    private var isBatteryConnected: Bool { model.isOnBattery == false }
    private var isBatteryCharging: Bool { (battery?.detail["charging"] ?? 0) > 0 }
    private var isChargeLimitHolding: Bool { (battery?.detail["systemChargeLimitReached"] ?? 0) > 0 }
    private var isFullyCharged: Bool { (battery?.detail["fullyCharged"] ?? 0) > 0 }

    var body: some View {
        VStack(spacing: ExperienceSpacing.small) {
            networkRow
            nearbyNetworksRow
            volumeRow
            batteryRow
            bluetoothRow
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
        .padding(12)
        .frame(width: DashboardPopoverView.width)
        .onAppear { model.onDuoBarPopoverOpened?() }
    }

    private var networkRow: some View {
        HStack(spacing: 9) {
            Image(systemName: networkSymbol, variableValue: wifiStrengthVariable)
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityValue(wifiStatusText)

            VStack(alignment: .leading, spacing: 2) {
                Text("Network")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(networkDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(networkSpeedText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

    private var nearbyNetworksRow: some View {
        Button {
            model.onOpenWiFiSettings?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                Text(String(localized: "duobar.nearbyNetworks", defaultValue: "Nearby Networks"))
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(controlSurface(cornerRadius: 12))
        .accessibilityHint(String(
            localized: "duobar.nearbyNetworks.hint",
            defaultValue: "Open Wi-Fi settings to view nearby networks"
        ))
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
        Button(action: openBatterySettings) {
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

                Spacer(minLength: 4)

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

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(controlSurface(cornerRadius: 12))
        .accessibilityHint("Open Battery settings")
    }

    private var bluetoothRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "bluetooth")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18)
            Text("Bluetooth")
                .font(.caption.weight(.medium))
            Spacer()
            Text(bluetoothStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(controlSurface(cornerRadius: 12))
        .accessibilityElement(children: .combine)
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
        if isNetworkConnected { return "Connected" }
        return wifiStatusText
    }

    private var networkSpeedText: String {
        guard let network else { return "↓— ↑—" }
        return "↓\(DashboardFormat.rate(network.detail["down"] ?? 0)) ↑\(DashboardFormat.rate(network.detail["up"] ?? 0))"
    }

    private var batteryIcon: some View {
        Image(systemName: battery == nil ? "battery.0percent" : "battery.100percent")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery")
        .accessibilityValue(batteryStatusText)
    }

    private var batteryStatusText: String {
        if isChargeLimitHolding {
            return String(localized: "battery.chargingOnHold", defaultValue: "Charging On Hold")
        }
        if isBatteryCharging { return BatteryPowerStatus.charging.localizedName }
        if model.isOnBattery == true { return BatteryPowerStatus.onBattery.localizedName }
        if isFullyCharged { return BatteryPowerStatus.pluggedIn.localizedName }
        return BatteryPowerStatus.pluggedIn.localizedName
    }

    private var batteryPowerSourceText: String? {
        if isBatteryConnected { return String(localized: "battery.usingAdapter", defaultValue: "Using Adapter") }
        guard let minutes = battery?.detail["timeToEmpty"], minutes > 0 else { return nil }
        return DashboardFormat.duration(minutes: minutes)
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

    private var bluetoothStatusText: String {
        switch model.duoBarBluetooth {
        case .on: "On"
        case .off: "Off"
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
}
