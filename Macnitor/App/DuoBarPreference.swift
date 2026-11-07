import Foundation

enum DuoBarPreference {
    static let key = "usesDuoBarDashboard"
    static let defaultValue = false

    static func value(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
