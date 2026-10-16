import AppKit
import SwiftUI

/// Accent color used by sparklines and charts everywhere (menu bar, popovers, widgets).
/// `system` follows the user's macOS accent color.
enum AccentChoice: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, teal

    var id: String { rawValue }

    /// Concrete color, or nil for "follow the system accent".
    var nsColor: NSColor? {
        switch self {
        case .system: return nil
        case .blue:   return .systemBlue
        case .purple: return .systemPurple
        case .pink:   return .systemPink
        case .red:    return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green:  return .systemGreen
        case .teal:   return .systemTeal
        }
    }

    var localizedName: String {
        switch self {
        case .system: return String(localized: "accent.system", defaultValue: "System")
        case .blue:   return String(localized: "accent.blue", defaultValue: "Blue")
        case .purple: return String(localized: "accent.purple", defaultValue: "Purple")
        case .pink:   return String(localized: "accent.pink", defaultValue: "Pink")
        case .red:    return String(localized: "accent.red", defaultValue: "Red")
        case .orange: return String(localized: "accent.orange", defaultValue: "Orange")
        case .yellow: return String(localized: "accent.yellow", defaultValue: "Yellow")
        case .green:  return String(localized: "accent.green", defaultValue: "Green")
        case .teal:   return String(localized: "accent.teal", defaultValue: "Teal")
        }
    }
}

/// Presentation style for Dashboard cards only. Missing preferences intentionally
/// resolve to `.regular` so existing installs keep their current appearance.
enum DashboardAppearance: String, CaseIterable, Identifiable {
    static let defaultBackgroundOpacity = ExperienceSurface.subtleFillOpacity
    static let maximumBackgroundOpacity = 0.25

    case regular
    case liquidGlass
    case liquidGlassRefined

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .regular:
            return String(localized: "dashboard.appearance.regular", defaultValue: "Regular")
        case .liquidGlass:
            return String(
                localized: "dashboard.appearance.liquidGlass",
                defaultValue: "Liquid Glass — Regular"
            )
        case .liquidGlassRefined:
            return String(
                localized: "dashboard.appearance.liquidGlassRefined",
                defaultValue: "Liquid Glass — Clear"
            )
        }
    }
}
