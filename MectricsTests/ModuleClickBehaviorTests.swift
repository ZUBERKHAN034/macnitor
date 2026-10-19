import XCTest
@testable import Mectrics

/// The click-behavior preference: which values are persisted, and what each means for
/// a click on a module's menu bar item.
final class ModuleClickBehaviorTests: XCTestCase {
    /// The raw values are persisted, so renaming a case would change what people see.
    func testRawValuesArePersistedAndNeverChange() {
        XCTAssertEqual(ModuleClickBehavior.ownDetail.rawValue, "ownDetail")
        XCTAssertEqual(ModuleClickBehavior.dashboard.rawValue, "dashboard")
        for behavior in ModuleClickBehavior.allCases {
            XCTAssertEqual(ModuleClickBehavior(rawValue: behavior.rawValue), behavior)
        }
    }

    /// Clicking a module item opens its own detail unless the Dashboard was chosen. The
    /// default is `.ownDetail`, so existing users see no change.
    func testOnlyTheDashboardChoiceOpensTheDashboard() {
        XCTAssertFalse(ModuleClickBehavior.ownDetail.opensDashboard)
        XCTAssertTrue(ModuleClickBehavior.dashboard.opensDashboard)
    }

    func testEveryBehaviorHasItsOwnName() {
        let names = ModuleClickBehavior.allCases.map(\.localizedName)
        XCTAssertFalse(names.contains { $0.isEmpty })
        XCTAssertEqual(Set(names).count, ModuleClickBehavior.allCases.count)
    }
}
