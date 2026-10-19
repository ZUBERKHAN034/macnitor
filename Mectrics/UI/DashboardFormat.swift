import Foundation
import MetricsKit

/// The dashboard's and the module detail's readings as text, kept out of the views so
/// they can be tested and so both surfaces say the same thing the same way.
///
/// Percentages, rates, temperatures, and RPM are numeric and symbolic, so like the
/// menu bar's they are not localized (AGENTS.md §2). Durations are words ("1d 12h"),
/// so they follow the locale's own unit abbreviations.
enum DashboardFormat {
    /// Shown where a reading does not exist — never a fabricated zero.
    static let missingValue = "–"

    /// A module's large reading, or `missingValue` without a sample.
    static func primaryValue(for id: MetricID, sample: MetricSample?) -> String {
        guard let sample else { return missingValue }
        switch id {
        case .cpu, .memory, .disk, .gpu:
            return MetricFormat.percent(sample.value, decimals: 1)
        case .battery:
            return "\(Int((sample.value * 100).rounded()))%"
        case .network:
            // The card shows each direction on its own line; this is their sum.
            return MetricFormat.bytesPerSecond(sample.value)
        case .fans:
            guard let rpm = sample.detail["maxRpm"] else { return missingValue }
            return "\(Int(rpm.rounded())) RPM"
        case .sensors:
            return temperature(sample.value)
        }
    }

    /// A transfer rate, or `missingValue` when the direction was not reported.
    static func rate(_ bytesPerSecond: Double?) -> String {
        bytesPerSecond.map(MetricFormat.bytesPerSecond) ?? missingValue
    }

    /// "13.6 / 16.0 GB", naming the unit once when both sides share it.
    ///
    /// The spaces inside "13.6 /" and "16.0 GB" do not break, so a narrow card wraps
    /// the line after the slash rather than stranding the unit on a line of its own.
    static func usedOfTotal(used: Double, total: Double) -> String {
        usedOfTotal(used: MetricFormat.bytes(used), total: MetricFormat.bytes(total))
    }

    /// Storage capacity in the decimal units macOS uses for disk sizes.
    static func storageUsedOfTotal(used: Double, total: Double) -> String {
        usedOfTotal(
            used: MetricFormat.storageBytes(used),
            total: MetricFormat.storageBytes(total)
        )
    }

    /// Active swap in decimal megabytes, using larger units as needed.
    static func memorySwapUsed(_ bytes: Double) -> String {
        let units = ["MB", "GB", "TB"]
        var value = max(bytes, 0) / 1_000_000
        var unitIndex = 0
        while value >= 1_000 && unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }
        return String(format: "%.2f %@", value, units[unitIndex])
    }

    private static func usedOfTotal(used: String, total: String) -> String {
        let used = split(used)
        let total = split(total)
        let totalText = "\(total.number)\u{00A0}\(total.unit)"
        guard used.unit != total.unit else {
            return "\(used.number)\u{00A0}/ \(totalText)"
        }
        return "\(used.number)\u{00A0}\(used.unit)\u{00A0}/ \(totalText)"
    }

    /// "174.0 KB/s" → ("174.0", "KB/s"), so the number can be set larger than its
    /// unit. A value without a unit comes back whole with an empty unit.
    static func split(_ value: String) -> (number: String, unit: String) {
        guard let space = value.lastIndex(of: " ") else { return (value, "") }
        return (
            String(value[..<space]),
            String(value[value.index(after: space)...])
        )
    }

    /// "26.0" or "26.0.1": the patch is left out when it is zero, as About This Mac
    /// does.
    static func systemVersion(_ version: OperatingSystemVersion) -> String {
        let release = "\(version.majorVersion).\(version.minorVersion)"
        guard version.patchVersion != 0 else { return release }
        return "\(release).\(version.patchVersion)"
    }

    /// "1d 12h 21m", "3h 5m", "12m" in English; each language's own unit
    /// abbreviations elsewhere. A unit that is zero is left out.
    static func uptime(_ seconds: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        format(seconds: seconds, units: [.days, .hours, .minutes], locale: locale)
    }

    /// Minutes → "2h 15m" / "45m", for battery estimates.
    static func duration(minutes: Double, locale: Locale = .autoupdatingCurrent) -> String {
        format(seconds: minutes * 60, units: [.hours, .minutes], locale: locale)
    }

    static func temperature(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°C"
    }

    /// Battery power is negative while the battery supplies the Mac, and zero on
    /// adapter power. Unknown power-source state or absent hardware readings stay nil.
    static func batteryPowerWatts(
        sample: MetricSample,
        isOnBattery: Bool?
    ) -> Double? {
        guard let isOnBattery else { return nil }
        guard isOnBattery else { return 0 }
        guard let watts = sample.detail["powerWatts"] else { return nil }
        return -abs(watts)
    }

    static func batteryPowerText(_ watts: Double) -> String {
        String(format: "%.2f W", watts)
    }

    /// Scale the recent draw history to the greatest observed draw so the chart
    /// shows changing usage while the signed watt value remains the exact reading.
    static func batteryPowerHistory(readings: [Double]) -> [Double] {
        let validReadings = readings.filter { $0.isFinite && $0 >= 0 }
        let peak = validReadings.max() ?? 0
        guard peak > 0 else { return validReadings.map { _ in 0 } }
        return validReadings.map { $0 / peak }
    }

    /// Spoken facts as one list, joined by the catalog's separator ("%1$@, %2$@";
    /// Chinese uses a full-width comma) rather than a hardcoded ", ".
    static func spokenList(_ parts: [String]) -> String {
        guard var list = parts.first else { return "" }
        for part in parts.dropFirst() {
            list = String(
                localized: "metric.accessibility.valueAndState",
                defaultValue: "\(list), \(part)"
            )
        }
        return list
    }

    /// Whole units only, rounded down as a clock is: 12 minutes 50 seconds is "12m".
    private static func format(
        seconds: TimeInterval,
        units: Set<Duration.UnitsFormatStyle.Unit>,
        locale: Locale
    ) -> String {
        Duration.seconds(max(seconds, 0)).formatted(
            .units(
                allowed: units,
                width: .narrow,
                maximumUnitCount: units.count,
                fractionalPart: .hide(rounded: .down)
            )
            .locale(locale)
        )
    }
}

/// Where a battery Mac is drawing its power from — shared by the dashboard's Battery
/// card and the Battery detail, so the two never disagree.
enum BatteryPowerStatus: Equatable {
    case charging
    /// On the adapter without charging: held at a charge limit, or full.
    case pluggedIn
    case onBattery

    /// The charging flag alone cannot tell a Mac on its adapter from one on battery:
    /// held at a charge limit it is not charging either. `isOnBattery` is the system's
    /// providing power source (`AppModel.isOnBattery`); without it the flag is all
    /// there is to go on.
    static func resolve(
        _ detail: [String: Double],
        isOnBattery: Bool?
    ) -> BatteryPowerStatus {
        if (detail["charging"] ?? 0) > 0 { return .charging }
        return isOnBattery == false ? .pluggedIn : .onBattery
    }

    var localizedName: String {
        switch self {
        case .charging:
            return String(localized: "battery.charging", defaultValue: "Charging")
        case .pluggedIn:
            return String(localized: "dashboard.battery.pluggedIn", defaultValue: "Plugged in")
        case .onBattery:
            return String(localized: "battery.onBattery", defaultValue: "On battery")
        }
    }

    var symbolName: String? {
        switch self {
        case .charging: return "bolt.fill"
        case .pluggedIn: return "powerplug.fill"
        case .onBattery: return nil
        }
    }

    /// What the estimate counts down to; nil when plugged in, where there is nothing
    /// to estimate.
    var estimateLabel: String? {
        switch self {
        case .charging:
            return String(localized: "battery.timeToFull", defaultValue: "Time to full")
        case .onBattery:
            return String(localized: "battery.timeRemaining", defaultValue: "Time left")
        case .pluggedIn:
            return nil
        }
    }

    /// Minutes to full while charging or to empty on battery: the IOPS estimate first,
    /// AppleSmartBattery's as a fallback. macOS sometimes has none at all ("Calculating"),
    /// and a Mac held on the adapter has nothing to estimate; both are nil.
    func estimate(in detail: [String: Double]) -> Double? {
        let system: Double?
        switch self {
        case .charging: system = detail["timeToFull"]
        case .onBattery: system = detail["timeToEmpty"]
        case .pluggedIn: return nil
        }
        if let system, system > 0 { return system }
        guard let fallback = detail["smartTimeRemaining"], fallback > 0 else { return nil }
        return fallback
    }
}

/// Color state for the Battery card's bolt, based on macOS power-source status.
enum BatteryChargeIconState: Equatable {
    case disconnected
    case connected
    case fullyCharged

    static func resolve(
        isOnBattery: Bool?,
        isCharging: Bool,
        isFullyCharged: Bool,
        isSystemChargeLimitReached: Bool,
        isAtFullCapacity: Bool
    ) -> Self {
        // Power-source state wins over a stale charging flag during transitions.
        if isOnBattery == true { return .disconnected }
        if isOnBattery == false,
           isFullyCharged || isSystemChargeLimitReached || isAtFullCapacity {
            return .fullyCharged
        }
        guard isOnBattery == false || isCharging else { return .disconnected }
        return .connected
    }
}
