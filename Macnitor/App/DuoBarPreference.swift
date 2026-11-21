import Foundation

enum DuoBarPreference {
    static let key = "usesDuoBarDashboard"
    static let batteryColorCodingKey = "duoBarBatteryColorCoding"
    static let defaultValue = false

    static func value(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    static func batteryColorCoding(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: batteryColorCodingKey) as? Bool ?? false
    }
}
