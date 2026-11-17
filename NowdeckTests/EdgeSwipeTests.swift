import XCTest
@testable import Nowdeck

/// Next / previous by dragging in from the screen edges (2026-11-17).
final class EdgeSwipeTests: XCTestCase {
    private let width: CGFloat = 896

    func testOnlyTouchesNextToAnEdgeStartASwipe() {
        XCTAssertNil(EdgeSwipe(startX: 300, currentX: 500, screenWidth: width))
        XCTAssertEqual(EdgeSwipe(startX: 10, currentX: 60, screenWidth: width)?.edge, .left)
        XCTAssertEqual(EdgeSwipe(startX: 890, currentX: 800, screenWidth: width)?.edge, .right)
        XCTAssertNil(EdgeSwipe(startX: EdgeSwipe.edgeZone + 1, currentX: 400, screenWidth: width))
    }

    func testDistanceOnlyCountsMovementAwayFromTheEdge() throws {
        let backwards = try XCTUnwrap(EdgeSwipe(startX: 20, currentX: 5, screenWidth: width))
        XCTAssertEqual(backwards.distance, 0)
        let right = try XCTUnwrap(EdgeSwipe(startX: 880, currentX: 830, screenWidth: width))
        XCTAssertEqual(right.distance, 50)
        XCTAssertEqual(right.progress, 50 / EdgeSwipe.commitDistance, accuracy: 0.001)
        XCTAssertFalse(right.isCommitted)
    }

    func testCommitsPastTheThresholdOrWithAFlick() throws {
        let far = try XCTUnwrap(EdgeSwipe(startX: 10, currentX: 10 + EdgeSwipe.commitDistance,
                                          screenWidth: width))
        XCTAssertTrue(far.isCommitted)
        XCTAssertEqual(far.progress, 1)
        XCTAssertTrue(far.commitsOnRelease(predictedX: 10, startX: 10))

        let short = try XCTUnwrap(EdgeSwipe(startX: 886, currentX: 846, screenWidth: width))
        XCTAssertFalse(short.commitsOnRelease(predictedX: 800, startX: 886), "A slow, short drag")
        XCTAssertTrue(short.commitsOnRelease(predictedX: 886 - EdgeSwipe.flickDistance, startX: 886),
                      "A flick toward the center")
    }

    func testTinyScreensHaveNoEdgeZones() {
        XCTAssertNil(EdgeSwipe(startX: 5, currentX: 50, screenWidth: 60))
    }
}
