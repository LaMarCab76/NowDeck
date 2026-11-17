import XCTest
@testable import Nowdeck

/// Milestone 8: the marquee that keeps cut names readable (docs/06, "Metadatos").
final class MarqueeMotionTests: XCTestCase {
    func testTextThatFitsDoesNotScroll() {
        XCTAssertFalse(MarqueeMotion(textWidth: 200, availableWidth: 300).needsScrolling)
        XCTAssertFalse(MarqueeMotion(textWidth: 300, availableWidth: 300).needsScrolling)
        // Layout rounding is not a cut.
        XCTAssertFalse(MarqueeMotion(textWidth: 300.4, availableWidth: 300).needsScrolling)
    }

    func testTextWiderThanItsRoomScrolls() {
        XCTAssertTrue(MarqueeMotion(textWidth: 301, availableWidth: 300).needsScrolling)
    }

    func testNothingScrollsBeforeTheLayoutIsMeasured() {
        XCTAssertFalse(MarqueeMotion(textWidth: 400, availableWidth: 0).needsScrolling)
    }

    func testOnePassMovesTheCopyIntoPlace() {
        let motion = MarqueeMotion(textWidth: 552, availableWidth: 300)
        XCTAssertEqual(motion.distance, 552 + MarqueeMotion.gap)
        XCTAssertEqual(motion.duration, Double(motion.distance / MarqueeMotion.speed), accuracy: 0.001)
        XCTAssertEqual(motion.duration, 20, accuracy: 0.001, "600 pt at 30 pt/s")
    }

    func testWrappedTextIsCutOnlyWhenItNeedsMoreLines() {
        XCTAssertFalse(MarqueeMotion.isCut(fullHeight: 92, limitedHeight: 92))
        XCTAssertFalse(MarqueeMotion.isCut(fullHeight: 46, limitedHeight: 46))
        XCTAssertTrue(MarqueeMotion.isCut(fullHeight: 138, limitedHeight: 92))
    }
}
