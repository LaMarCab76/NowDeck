import XCTest
@testable import Nowdeck

final class PlaybackProgressTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_000_000)

    func testAdvancesWhilePlaying() {
        let position = PlaybackProgress.interpolatedMs(
            progressMs: 84_000, durationMs: 227_000, isPlaying: true,
            fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(2.5))
        XCTAssertEqual(position, 86_500)
    }

    func testStaysStillWhilePaused() {
        let position = PlaybackProgress.interpolatedMs(
            progressMs: 84_000, durationMs: 227_000, isPlaying: false,
            fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(30))
        XCTAssertEqual(position, 84_000)
    }

    func testNeverPassesTheDuration() {
        let position = PlaybackProgress.interpolatedMs(
            progressMs: 226_000, durationMs: 227_000, isPlaying: true,
            fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(10))
        XCTAssertEqual(position, 227_000)
    }

    func testClockGoingBackwardsDoesNotRewind() {
        let position = PlaybackProgress.interpolatedMs(
            progressMs: 84_000, durationMs: 227_000, isPlaying: true,
            fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(-5))
        XCTAssertEqual(position, 84_000)
    }

    func testUnknownDurationOnlyAvoidsNegatives() {
        XCTAssertEqual(PlaybackProgress.interpolatedMs(
            progressMs: -10, durationMs: 0, isPlaying: false, fetchedAt: fetchedAt, now: fetchedAt), 0)
        XCTAssertEqual(PlaybackProgress.fraction(positionMs: 5_000, durationMs: 0), 0)
    }

    func testFraction() {
        XCTAssertEqual(PlaybackProgress.fraction(positionMs: 84_000, durationMs: 227_000),
                       0.37, accuracy: 0.001)
        XCTAssertEqual(PlaybackProgress.fraction(positionMs: 300_000, durationMs: 227_000), 1)
    }

    func testFormatting() {
        XCTAssertEqual(PlaybackProgress.formatted(ms: 0), "0:00")
        XCTAssertEqual(PlaybackProgress.formatted(ms: 84_999), "1:24")
        XCTAssertEqual(PlaybackProgress.formatted(ms: 227_000), "3:47")
        XCTAssertEqual(PlaybackProgress.formatted(ms: 3_723_000), "1:02:03")
    }

    func testRemainingFormatting() {
        XCTAssertEqual(PlaybackProgress.remainingFormatted(positionMs: 84_000, durationMs: 227_000),
                       "\u{2212}2:23")
        XCTAssertEqual(PlaybackProgress.remainingFormatted(positionMs: 0, durationMs: 3_723_000),
                       "\u{2212}1:02:03")
        XCTAssertEqual(PlaybackProgress.remainingFormatted(positionMs: 300_000, durationMs: 227_000),
                       "\u{2212}0:00", "Never a negative time left")
    }
}

final class PollingPolicyTests: XCTestCase {
    private let policy = PollingPolicy()

    func testIntervalsFromTheDesign() {
        XCTAssertEqual(policy.delay(after: .playing), 3)
        XCTAssertEqual(policy.delay(after: .idle), 10)
    }

    func testQuotaSlowsDown() {
        XCTAssertGreaterThan(policy.delay(after: .playing, quotaLimited: true), 3)
        XCTAssertGreaterThan(policy.delay(after: .idle, quotaLimited: true), 10)
    }

    func testFailuresBackOffExponentiallyUpToTheLimit() {
        let delays = (1...7).map { policy.delay(after: .failed, consecutiveFailures: $0) }
        XCTAssertEqual(delays, [3, 6, 12, 24, 48, 60, 60])
    }

    func testRetryAfterIsRespectedWithJitter() {
        XCTAssertEqual(policy.delay(after: .rateLimited(retryAfter: 7), jitter: 0.4), 7.4)
        XCTAssertEqual(policy.delay(after: .rateLimited(retryAfter: 86_400)), policy.maxRetryAfter)
    }

    // MARK: Dragging the bar

    func testPositionUnderTheFinger() {
        XCTAssertEqual(PlaybackProgress.positionMs(atX: 0, width: 400, durationMs: 200_000), 0)
        XCTAssertEqual(PlaybackProgress.positionMs(atX: 100, width: 400, durationMs: 200_000), 50_000)
        XCTAssertEqual(PlaybackProgress.positionMs(atX: 400, width: 400, durationMs: 200_000), 200_000)
    }

    func testFingerOutsideTheBarStopsAtTheEdges() {
        XCTAssertEqual(PlaybackProgress.positionMs(atX: -30, width: 400, durationMs: 200_000), 0)
        XCTAssertEqual(PlaybackProgress.positionMs(atX: 450, width: 400, durationMs: 200_000), 200_000)
    }

    func testNoBarOrNoDurationGivesTheStart() {
        XCTAssertEqual(PlaybackProgress.positionMs(atX: 100, width: 0, durationMs: 200_000), 0)
        XCTAssertEqual(PlaybackProgress.positionMs(atX: 100, width: 400, durationMs: 0), 0)
    }
}
