import Foundation

/// What clicking a module's menu bar item opens.
///
/// The raw values are persisted and must never change.
enum ModuleClickBehavior: String, CaseIterable, Identifiable {
    /// The clicked module's own detail popover — the behavior Mectrics has always had.
    case ownDetail
    /// The Dashboard, anchored to the clicked item. It shows every watched module as a
    /// card, so a hidden Dashboard icon still leaves every reading one click away.
    case dashboard

    var id: String { rawValue }

    /// Whether a click on a module item presents the Dashboard rather than the item's
    /// own detail. Read at click time — never baked into a status item — so changing it
    /// never rebuilds the menu bar.
    var opensDashboard: Bool { self == .dashboard }

    var localizedName: String {
        switch self {
        case .ownDetail:
            return String(
                localized: "builder.clickBehavior.ownDetail",
                defaultValue: "Its own detail"
            )
        case .dashboard:
            return String(
                localized: "builder.clickBehavior.dashboard",
                defaultValue: "The Dashboard"
            )
        }
    }
}
