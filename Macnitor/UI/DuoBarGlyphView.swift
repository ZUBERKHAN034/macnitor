import SwiftUI

/// Compact live mark using DuoBar's measured ring, Wi-Fi, and lower-dot geometry.
struct DuoBarGlyphView: View {
    let batteryLevel: Double?
    let isCharging: Bool
    let volumeLevel: Double?
    let isMuted: Bool
    let networkAvailable: Bool
    let wifiSignal: DuoBarWiFiSignal
    let bluetoothState: DuoBarBluetoothState
    let healthSymbol: String?

    private let iconSize: CGFloat = 24
    private let designScale: CGFloat = 24 / 32
    private let ringDiameter: CGFloat = 26.5
    private let ringYOffset: CGFloat = -0.8
    private let referenceStrokeRatio: CGFloat = 0.076378

    var body: some View {
        ZStack {
            Canvas { context, size in
                drawRing(in: &context, size: size)
                drawWiFi(in: &context, size: size)
                drawBluetoothDots(in: &context, size: size)
            }

            if wifiSignal == .disconnected || wifiSignal == .unavailable {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 9, weight: .medium))
                    .symbolRenderingMode(.monochrome)
            }

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: ringDiameter * 0.75 * (50 / 1.16 / 230), weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
                    .position(chargingBoltPosition)
            }

            if let healthSymbol {
                Image(systemName: healthSymbol)
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(.orange)
                    .padding(1.5)
                    .background(.black.opacity(0.72), in: Circle())
                    .offset(x: 9, y: -8)
            }
        }
        .frame(width: iconSize, height: iconSize)
        .offset(y: 1)
        .accessibilityHidden(true)
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
        let progress = min(max(batteryLevel ?? 0, 0), 1)
        let progressEnd = start + (end - start) * progress
        let radius = arcPathDiameter / 2
        let track = arcPath(center: center, radius: radius, from: start, to: end)
        context.stroke(track, with: .color(.primary.opacity(batteryLevel == nil ? 0.22 : 0.28)), style: StrokeStyle(lineWidth: arcLineWidth, lineCap: .round))

        guard batteryLevel != nil, progress > 0 else { return }
        let activeArc: Path
        if isCharging {
            activeArc = arcPathSkippingChargingBolt(center: center, radius: radius, from: start, to: progressEnd)
        } else {
            activeArc = arcPath(center: center, radius: radius, from: start, to: progressEnd)
        }
        context.stroke(activeArc, with: .color(.primary), style: StrokeStyle(lineWidth: arcLineWidth, lineCap: .round))
    }

    private func arcPathSkippingChargingBolt(
        center: CGPoint,
        radius: CGFloat,
        from start: Double,
        to end: Double
    ) -> Path {
        let gapCenter = 270.0
        let halfGap = 11.0
        let lower = gapCenter - halfGap
        let upper = gapCenter + halfGap
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

    private func drawWiFi(in context: inout GraphicsContext, size: CGSize) {
        guard wifiSignal != .disconnected, wifiSignal != .unavailable else { return }
        let diameter = scaledRingDiameter
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + ringOffset)
        let apex = CGPoint(x: center.x, y: center.y + diameter * 0.128157)
        let lineWidth = diameter * 0.060540
        let levelCount: Int
        switch wifiSignal {
        case .strong: levelCount = 3
        case .medium: levelCount = 2
        case .weak: levelCount = 1
        case .disconnected, .unavailable: levelCount = 0
        }

        for (index, radiusRatio) in [0.268964, 0.155314].enumerated() {
            let path = wifiArc(center: apex, radius: diameter * radiusRatio)
            let opacity = index < levelCount ? 1.0 : 0.28
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
        context.fill(core, with: .color(.primary.opacity(levelCount > 0 ? 1 : 0.28)))
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

    private func drawBluetoothDots(in context: inout GraphicsContext, size: CGSize) {
        let diameter = scaledRingDiameter
        let center = CGPoint(x: size.width / 2, y: size.height / 2 + ringOffset)
        let radius = diameter * 0.455450
        let angles: [CGFloat] = [-32.273, -10.813, 10.813, 32.273]
        let dotDiameter = diameter * 0.096502

        for (index, angle) in angles.enumerated() {
            let radians = angle * .pi / 180
            let x = center.x + sin(radians) * radius
            let y = center.y + cos(radians) * radius
            let rect = CGRect(x: x - dotDiameter / 2, y: y - dotDiameter / 2, width: dotDiameter, height: dotDiameter)
            let opacity: Double
            switch bluetoothState {
            case .on: opacity = 1
            case .off: opacity = 0.30
            case .unavailable: opacity = index == 0 ? 0.68 : 0.16
            }
            context.fill(Path(ellipseIn: rect), with: .color(.primary.opacity(opacity)))
        }
    }

    private func point(on radius: CGFloat, degrees: Double, center: CGPoint) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }
}
