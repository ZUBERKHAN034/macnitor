import AppKit
import SwiftUI

/// Compact live mark using DuoBar's measured ring, Wi-Fi, and volume-dot geometry.
struct DuoBarGlyphView: View {
    let batteryLevel: Double?
    let showsChargingBolt: Bool
    let batteryColor: DuoBarBatteryColor
    let volumeLevel: Double?
    let isMuted: Bool
    let networkAvailable: Bool
    let wifiSignal: DuoBarWiFiSignal
    let healthSymbol: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedBatteryProgress: CGFloat = 0
    @State private var hasAppeared = false
    @State private var displayedWiFiSignal: DuoBarWiFiSignal = .unavailable
    @State private var animatedWiFiLevel: CGFloat = 0
    @State private var wifiMarkOpacity: CGFloat = 0
    @State private var offlineMarkOpacity: CGFloat = 1
    @State private var wifiTransitionTask: Task<Void, Never>?

    private let iconSize: CGFloat = 24
    private let designScale: CGFloat = 24 / 32
    private let ringDiameter: CGFloat = 26.5
    private let ringYOffset: CGFloat = -0.8
    private let referenceStrokeRatio: CGFloat = 0.076378

    private var resolvedWiFiSignal: DuoBarWiFiSignal {
        networkAvailable ? wifiSignal : .disconnected
    }

    private var batteryPercentageText: String? {
        guard let batteryLevel else { return nil }
        return "\(Int((min(max(batteryLevel, 0), 1) * 100).rounded()))"
    }

    private var batteryPercentageFontSize: CGFloat {
        switch batteryPercentageText?.count ?? 0 {
        case 1: return 7
        case 2: return 6.5
        default: return 5.8
        }
    }

    /// Calculate the opening from the displayed digits so the number clears the arc.
    private var batteryPercentageGapHalfAngle: Double {
        guard let batteryPercentageText else { return 0 }
        let textWidth = CGFloat(batteryPercentageText.count) * batteryPercentageFontSize * 0.62
        let clearance = textWidth / 2 + arcLineWidth / 2 + 0.6
        return Double(atan2(clearance, arcPathDiameter / 2) * 180 / .pi)
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawRing(in: &context, size: size)
            }

            volumeDotRow

            Canvas { context, size in
                drawWiFi(in: &context, size: size, signal: displayedWiFiSignal, activeLevel: animatedWiFiLevel)
            }
            .opacity(wifiMarkOpacity)

            Image(systemName: "network.slash")
                .font(.system(size: 12.4 * designScale, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(
                    width: 12.4 * designScale * 1.65,
                    height: 12.4 * designScale * 1.4
                )
                .offset(y: -1.25 * designScale)
                .opacity(offlineMarkOpacity)
                .accessibilityHidden(true)

            if showsChargingBolt {
                Image(systemName: "bolt.fill")
                    .font(.system(size: scaledRingDiameter * (50 / 1.16 / 230), weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
                    .position(chargingBoltPosition)
                    .transition(.scale(scale: 0.76).combined(with: .opacity))
            }

            if let batteryPercentageText, !showsChargingBolt {
                Text(batteryPercentageText)
                    .font(.system(size: batteryPercentageFontSize, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                    .position(chargingBoltPosition)
                    .transition(.opacity)
            }

            if let healthSymbol {
                Image(systemName: healthSymbol)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(1.5)
                    .background(.black.opacity(0.72), in: Circle())
                    .offset(x: 9, y: -8)
                    .transition(.scale(scale: 0.75).combined(with: .opacity))
            }
        }
        .frame(width: iconSize, height: iconSize)
        .offset(y: 1)
        .onAppear {
            animatedBatteryProgress = CGFloat(batteryLevel ?? 0)
            hasAppeared = true
            displayedWiFiSignal = resolvedWiFiSignal
            animatedWiFiLevel = level(for: resolvedWiFiSignal)
            let isOffline = resolvedWiFiSignal == .disconnected || resolvedWiFiSignal == .unavailable
            wifiMarkOpacity = isOffline ? 0 : 1
            offlineMarkOpacity = isOffline ? 1 : 0
        }
        .onChange(of: resolvedWiFiSignal) { signal in
            wifiTransitionTask?.cancel()
            let isOffline = signal == .disconnected || signal == .unavailable
            if isOffline {
                withAnimation(.easeInOut(duration: 0.24)) {
                    wifiMarkOpacity = 0
                    offlineMarkOpacity = 1
                    animatedWiFiLevel = 0
                }
                wifiTransitionTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(240))
                    guard !Task.isCancelled else { return }
                    displayedWiFiSignal = signal
                }
            } else {
                displayedWiFiSignal = signal
                withAnimation(.easeInOut(duration: 0.24)) {
                    wifiMarkOpacity = 1
                    offlineMarkOpacity = 0
                    animatedWiFiLevel = level(for: signal)
                }
            }
        }
        .onChange(of: batteryLevel) { level in
            let target = CGFloat(level ?? 0)
            guard !reduceMotion else {
                animatedBatteryProgress = target
                return
            }
            withAnimation(.easeInOut(duration: 0.14)) {
                animatedBatteryProgress = target
            }
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: healthSymbol)
        .animation(.easeOut(duration: 0.12), value: showsChargingBolt)
        .onDisappear { wifiTransitionTask?.cancel() }
        .accessibilityHidden(true)
    }

    private var activeVolumeDotCount: Int? {
        guard let volumeLevel else { return nil }
        let percentage = Int((min(max(volumeLevel, 0), 1) * 100).rounded())
        if isMuted || percentage == 0 { return 0 }
        switch percentage {
        case 1...25: return 1
        case 26...50: return 2
        case 51...75: return 3
        default: return 4
        }
    }

    private var volumeDotRow: some View {
        let radius = scaledRingDiameter * 0.455450
        let dotDiameter = scaledRingDiameter * 0.096502
        let angles: [Double] = [-32.273, -10.813, 10.813, 32.273]
        return ZStack {
            ForEach(0..<4, id: \.self) { index in
                let radians = angles[index] * .pi / 180
                Circle()
                    .frame(width: dotDiameter, height: dotDiameter)
                    .opacity(dotOpacity(at: index))
                    .offset(
                        x: CGFloat(sin(radians)) * radius,
                        y: CGFloat(cos(radians)) * radius
                    )
            }
        }
        .frame(width: scaledRingDiameter, height: scaledRingDiameter)
        .offset(y: ringOffset)
        .foregroundStyle(.primary)
        .animation(.easeInOut(duration: 0.2), value: activeVolumeDotCount)
    }

    private func dotOpacity(at index: Int) -> Double {
        guard let activeVolumeDotCount else { return 0.30 }
        return index < activeVolumeDotCount ? 1 : 0.30
    }

    private func level(for signal: DuoBarWiFiSignal) -> CGFloat {
        switch signal {
        case .strong: return 3
        case .medium: return 2
        case .weak: return 1
        case .disconnected, .unavailable: return 0
        }
    }

    private var batteryArcColor: Color {
        switch batteryColor {
        case .charging: return Color(nsColor: .systemGreen)
        case .lowPowerMode: return Color(nsColor: .systemYellow)
        case .lowBattery: return Color(nsColor: .systemRed)
        case .monochrome: return .primary
        }
    }

    private var scaledRingDiameter: CGFloat { ringDiameter * designScale }
    private var arcLineWidth: CGFloat { ringDiameter * referenceStrokeRatio * designScale }
    private var arcPathDiameter: CGFloat { scaledRingDiameter - arcLineWidth }
    private var ringOffset: CGFloat { ringYOffset * designScale }
    private var chargingBoltPosition: CGPoint {
        let radialOffset = scaledRingDiameter * (-3.5 / 230)
        let midpoint = point(
            on: arcPathDiameter / 2 + radialOffset,
            degrees: 270,
            center: CGPoint(x: iconSize / 2, y: iconSize / 2 + ringOffset)
        )
        return CGPoint(x: midpoint.x + scaledRingDiameter * (-0.5 / 230), y: midpoint.y)
    }

    private func drawRing(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + ringOffset)
        let start = 150.11
        let end = 389.89
        let initialProgress = CGFloat(batteryLevel ?? 0)
        let progress = min(max(hasAppeared ? animatedBatteryProgress : initialProgress, 0), 1)
        let progressEnd = start + (end - start) * progress
        let radius = arcPathDiameter / 2
        let gapHalfAngle = showsChargingBolt ? 25 : batteryPercentageGapHalfAngle
        let track = arcPathWithGap(
            center: center,
            radius: radius,
            from: start,
            to: end,
            halfAngle: gapHalfAngle
        )
        context.stroke(track, with: .color(.primary.opacity(batteryLevel == nil ? 0.22 : 0.28)), style: StrokeStyle(lineWidth: arcLineWidth, lineCap: .round))

        guard batteryLevel != nil, progress > 0 else { return }
        let activeArc = arcPathWithGap(
            center: center,
            radius: radius,
            from: start,
            to: progressEnd,
            halfAngle: gapHalfAngle
        )
        context.stroke(activeArc, with: .color(batteryArcColor), style: StrokeStyle(lineWidth: arcLineWidth, lineCap: .round))
    }

    private func arcPathWithGap(
        center: CGPoint,
        radius: CGFloat,
        from start: Double,
        to end: Double,
        halfAngle: Double
    ) -> Path {
        guard halfAngle > 0 else { return arcPath(center: center, radius: radius, from: start, to: end) }
        return arcPathSkippingChargingBolt(
            center: center,
            radius: radius,
            from: start,
            to: end,
            gapHalfAngle: halfAngle
        )
    }

    private func arcPathSkippingChargingBolt(
        center: CGPoint,
        radius: CGFloat,
        from start: Double,
        to end: Double,
        gapHalfAngle: Double
    ) -> Path {
        let gapCenter = 270.0
        let lower = gapCenter - gapHalfAngle
        let upper = gapCenter + gapHalfAngle
        guard end > lower else { return arcPath(center: center, radius: radius, from: start, to: end) }
        var path = arcPath(center: center, radius: radius, from: start, to: min(end, lower))
        if end > upper {
            path.addPath(arcPath(center: center, radius: radius, from: upper, to: end))
        }
        return path
    }

    private func arcPath(center: CGPoint, radius: CGFloat, from start: Double, to end: Double) -> Path {
        var path = Path()
        guard end > start else { return path }
        let sampleCount = max(2, Int((end - start) / 4))
        for index in 0...sampleCount {
            let fraction = Double(index) / Double(sampleCount)
            let point = point(on: radius, degrees: start + (end - start) * fraction, center: center)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func drawWiFi(
        in context: inout GraphicsContext,
        size: CGSize,
        signal: DuoBarWiFiSignal,
        activeLevel: CGFloat
    ) {
        guard signal != .disconnected, signal != .unavailable else { return }
        let diameter = scaledRingDiameter
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + ringOffset)
        let apex = CGPoint(x: center.x, y: center.y + diameter * 0.128157)
        let lineWidth = diameter * 0.060540
        for (radiusRatio, threshold) in [(0.268964, 2), (0.155314, 1)] {
            let path = wifiArc(center: apex, radius: diameter * radiusRatio)
            let activation = min(max(Double(activeLevel) - Double(threshold), 0), 1)
            let opacity = 0.28 + (1 - 0.28) * activation
            context.stroke(path, with: .color(.primary.opacity(opacity)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }

        var core = Path()
        let coreRadius = diameter * 0.059620
        core.move(to: apex)
        for step in 0...24 {
            let angle = 210.0 + 120.0 * Double(step) / 24
            core.addLine(to: point(on: coreRadius, degrees: angle, center: apex))
        }
        core.closeSubpath()
        let coreOpacity = 0.28 + 0.72 * min(max(Double(activeLevel), 0), 1)
        context.fill(core, with: .color(.primary.opacity(coreOpacity)))
    }

    private func wifiArc(center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let start = 270.0 - 43.673
        let end = 270.0 + 43.673
        for step in 0...48 {
            let angle = start + (end - start) * Double(step) / 48
            let point = point(on: radius, degrees: angle, center: center)
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func point(on radius: CGFloat, degrees: Double, center: CGPoint) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }
}
