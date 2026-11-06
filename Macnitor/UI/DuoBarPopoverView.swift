import SwiftUI
import MetricsKit

/// DuoBar's compact control surface, presented instead of the card Dashboard when selected.
struct DuoBarPopoverView: View {
    @Bindable var model: AppModel

    private var battery: MetricSample? { model.latest[.battery] }
    private var network: MetricSample? { model.latest[.network] }
    private var batteryPercent: Int? { battery.map { Int(($0.normalized * 100).rounded()) } }
    private var isNetworkConnected: Bool { NetworkInfo.primaryIPv4() != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "battery.100percent")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Battery")
                        .font(.headline)
                    Text(batteryPercent.map { "\($0)%" } ?? "Unavailable")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                }
                Spacer()
                if battery?.detail["charging"] == 1 {
                    Label("Charging", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Output Volume", systemImage: model.duoBarMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    Spacer()
                    Text(model.duoBarVolume.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button {
                        model.onDuoBarMuteChanged?(!model.duoBarMuted)
                    } label: {
                        Image(systemName: model.duoBarMuted ? "speaker.wave.2" : "speaker.slash")
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.duoBarMuteSettable)
                    .help(model.duoBarMuted ? "Unmute output" : "Mute output")
                }
                Slider(
                    value: Binding(
                        get: { model.duoBarVolume ?? 0 },
                        set: { model.onDuoBarVolumeChanged?($0) }
                    ),
                    in: 0...1
                )
                .disabled(!model.duoBarVolumeSettable || model.duoBarVolume == nil)
                .accessibilityLabel("Output volume")
            }

            Menu {
                if model.duoBarAudioOutputs.isEmpty {
                    Text("No output devices")
                } else {
                    ForEach(model.duoBarAudioOutputs) { output in
                        Button {
                            model.onDuoBarOutputSelected?(output.uid)
                        } label: {
                            if output.uid == model.duoBarSelectedOutputUID {
                                Label(output.name, systemImage: "checkmark")
                            } else {
                                Text(output.name)
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
                    Image(systemName: "hifispeaker")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Output").font(.subheadline.weight(.medium))
                        Text(model.duoBarAudioOutputs.first(where: { $0.uid == model.duoBarSelectedOutputUID })?.name ?? "No output device")
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

            Menu {
                if model.duoBarAudioInputs.isEmpty {
                    Text("No input devices")
                } else {
                    ForEach(model.duoBarAudioInputs) { input in
                        Button {
                            model.onDuoBarInputSelected?(input.uid)
                        } label: {
                            if input.uid == model.duoBarSelectedInputUID {
                                Label(input.name, systemImage: "checkmark")
                            } else {
                                Text(input.name)
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
                    Image(systemName: "mic")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Input").font(.subheadline.weight(.medium))
                        Text(model.duoBarAudioInputs.first(where: { $0.uid == model.duoBarSelectedInputUID })?.name ?? "No input device")
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

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNetworkConnected ? "Network connected" : "Network disconnected")
                        .font(.subheadline.weight(.medium))
                    if let address = NetworkInfo.primaryIPv4()?.address {
                        Text(address).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let wifiPoweredOn = model.duoBarWiFiPoweredOn {
                    Toggle("Wi-Fi", isOn: Binding(
                        get: { wifiPoweredOn },
                        set: { model.onDuoBarWiFiPowerChanged?($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .accessibilityLabel("Wi-Fi power")
                    .help(wifiPoweredOn ? "Turn Wi-Fi off" : "Turn Wi-Fi on")
                } else {
                    Button("Wi-Fi Settings") { model.onOpenWiFiSettings?() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if let network {
                HStack(spacing: 14) {
                    Label("↓ \(DashboardFormat.rate(network.detail["down"] ?? 0))", systemImage: "arrow.down")
                    Label("↑ \(DashboardFormat.rate(network.detail["up"] ?? 0))", systemImage: "arrow.up")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Settings") { model.onOpenSettings?() }
                    .buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: DashboardPopoverView.width)
        .background {
            DashboardCardBackground(
                fillOpacity: model.dashboardBackgroundOpacity,
                appearance: model.dashboardAppearance,
                cornerRadius: ExperienceRadius.panel
            )
        }
        .clipped()
        .onAppear { model.onDuoBarPopoverOpened?() }
    }
}
