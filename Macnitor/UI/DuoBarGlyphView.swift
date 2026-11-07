import SwiftUI

/// Compact DuoBar-inspired status mark: battery ring, network center, and live volume dots.
struct DuoBarGlyphView: View {
    let batteryLevel: Double?
    let isCharging: Bool
    let volumeLevel: Double?
    let isMuted: Bool
    let networkAvailable: Bool
    let wifiSignal: DuoBarWiFiSignal
    let bluetoothState: DuoBarBluetoothState
    let healthSymbol: String?

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.16, to: 0.84)
                .stroke(.primary.opacity(0.24), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                .rotationEffect(.degrees(90))
            if let batteryLevel {
                Circle()
                    .trim(from: 0.16, to: 0.16 + 0.68 * min(max(batteryLevel, 0), 1))
                    .stroke(.primary, style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
                    .rotationEffect(.degrees(90))
            }
            Image(systemName: wifiSignal == .disconnected || wifiSignal == .unavailable ? "wifi.slash" : "wifi")
                .font(.system(size: 10, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .opacity(wifiSignal == .weak ? 0.62 : wifiSignal == .medium ? 0.82 : 1)
                .offset(y: -1)
            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 6, weight: .bold))
                    .offset(x: 7, y: -8)
            }
            HStack(spacing: 1.7) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(.primary.opacity(bluetoothDotOpacity(index)))
                        .frame(width: 2.4, height: 2.4)
                }
            }
            .offset(y: 8)
            if let healthSymbol {
                Image(systemName: healthSymbol)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(1.5)
                    .background(.black.opacity(0.72), in: Circle())
                    .offset(x: 9, y: -8)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private func bluetoothDotOpacity(_ index: Int) -> Double {
        switch bluetoothState {
        case .on: return 1
        case .off: return 0.22
        case .unavailable: return index == 0 ? 0.68 : 0.16
        }
    }
}
