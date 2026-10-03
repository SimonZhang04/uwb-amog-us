import XCTest
import simd
@testable import UWBDistance

final class UWBDistanceTests: XCTestCase {
    func testInviteTiebreakIsExclusive() {
        XCTAssertTrue(PeerConnection.shouldInvite(local: "a", remote: "b"))
        XCTAssertFalse(PeerConnection.shouldInvite(local: "b", remote: "a"))
    }

    func testArrowAngleAhead() {
        XCTAssertEqual(RangeMath.arrowAngle(for: SIMD3<Float>(0, 0, -1)), 0, accuracy: 0.001)
    }

    func testArrowAngleRight() {
        XCTAssertEqual(RangeMath.arrowAngle(for: SIMD3<Float>(1, 0, 0)), .pi / 2, accuracy: 0.001)
    }
}
