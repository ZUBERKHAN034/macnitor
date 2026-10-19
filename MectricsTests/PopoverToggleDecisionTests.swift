import XCTest
@testable import Mectrics

/// A status-item click during the popover's close animation must reopen it rather
/// than issue a second close request against the outgoing presentation.
final class PopoverToggleDecisionTests: XCTestCase {
    func testClickOnVisibleCurrentPopoverClosesIt() {
        XCTAssertTrue(PopoverToggleDecision.shouldCloseCurrentPopover(
            isShown: true,
            isClosing: false,
            matchesCurrentKind: true
        ))
    }

    func testClickDuringCloseAnimationPresentsInsteadOfClosingAgain() {
        XCTAssertFalse(PopoverToggleDecision.shouldCloseCurrentPopover(
            isShown: true,
            isClosing: true,
            matchesCurrentKind: true
        ))
    }

    func testHiddenOrDifferentPopoverIsNotToggledClosed() {
        XCTAssertFalse(PopoverToggleDecision.shouldCloseCurrentPopover(
            isShown: false,
            isClosing: false,
            matchesCurrentKind: true
        ))
        XCTAssertFalse(PopoverToggleDecision.shouldCloseCurrentPopover(
            isShown: true,
            isClosing: false,
            matchesCurrentKind: false
        ))
    }
}
