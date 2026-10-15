import XCTest
@testable import Mectrics

/// The popover must survive the activation changes caused by a native menu, then
/// resume its ordinary resign-active dismissal behavior once menu tracking ends.
final class PopoverMenuTrackingTests: XCTestCase {
    func testOpeningMenuSuppressesPopoverResignDismissal() {
        var state = PopoverMenuTrackingState()

        XCTAssertFalse(state.isTrackingMenu)
        state.beginTracking()

        XCTAssertTrue(state.isTrackingMenu)
        XCTAssertFalse(state.shouldDismissPopover(
            isShown: true,
            isClosing: false,
            applicationIsActive: false
        ))
    }

    func testDismissalResumesAfterMenuTrackingEnds() {
        var state = PopoverMenuTrackingState()
        state.beginTracking()
        state.endTracking()

        XCTAssertFalse(state.isTrackingMenu)
        XCTAssertTrue(state.shouldDismissPopover(
            isShown: true,
            isClosing: false,
            applicationIsActive: false
        ))
    }

    func testNestedMenusKeepTrackingUntilEveryMenuEnds() {
        var state = PopoverMenuTrackingState()
        state.beginTracking()
        state.beginTracking()

        state.endTracking()
        XCTAssertTrue(state.isTrackingMenu)

        state.endTracking()
        XCTAssertFalse(state.isTrackingMenu)
    }

    func testActiveApplicationOrAlreadyClosedPopoverIsNotDismissedAgain() {
        let state = PopoverMenuTrackingState()

        XCTAssertFalse(state.shouldDismissPopover(
            isShown: true,
            isClosing: false,
            applicationIsActive: true
        ))
        XCTAssertFalse(state.shouldDismissPopover(
            isShown: false,
            isClosing: false,
            applicationIsActive: false
        ))
        XCTAssertFalse(state.shouldDismissPopover(
            isShown: true,
            isClosing: true,
            applicationIsActive: false
        ))
    }

    func testUnmatchedEndNotificationDoesNotCreateNegativeTracking() {
        var state = PopoverMenuTrackingState()
        state.endTracking()

        XCTAssertFalse(state.isTrackingMenu)
        XCTAssertEqual(state.activeMenuCount, 0)
    }
}
