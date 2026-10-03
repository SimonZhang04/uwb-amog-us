import XCTest
import simd
@testable import UWBDistance

final class UWBDistanceTests: XCTestCase {
    // MARK: transport
    func testInviteTiebreakEightPlayersExactlyOneInviterPerPair() {
        let ids = (0..<8).map { "p\($0)-\(String(format: "%04X", $0 * 977))" }
        for a in ids { for b in ids where a != b {
            XCTAssertNotEqual(PeerConnection.shouldInvite(local: a, remote: b),
                              PeerConnection.shouldInvite(local: b, remote: a))
        } }
    }

    func testPlayerCap() {
        XCTAssertTrue(PeerConnection.canAccept(connectedPeers: 6, maxPlayers: 8))
        XCTAssertFalse(PeerConnection.canAccept(connectedPeers: 7, maxPlayers: 8))
    }

    func testMessageRoundTrip() {
        let msgs: [WireMessage] = [.token(Data([1, 2, 3])), .distances(["a": 1.5, "b": 2]), .status(suspended: true)]
        for m in msgs { XCTAssertEqual(WireMessage.decode(m.encoded()!), m) }
    }

    func testShortName() {
        XCTAssertEqual("Simon-AB12".playerShortName, "Simon")
        XCTAssertEqual("iPhone".playerShortName, "iPhone")
    }

    // MARK: arrow
    func testArrowAngle() {
        XCTAssertEqual(RangeMath.arrowAngle(for: SIMD3<Float>(0, 0, -1)), 0, accuracy: 0.001)
        XCTAssertEqual(RangeMath.arrowAngle(for: SIMD3<Float>(1, 0, 0)), .pi / 2, accuracy: 0.001)
    }

    // MARK: dot status
    func testDotStatus() {
        let now = Date()
        var r = PeerRange(id: "a")
        XCTAssertEqual(r.dotStatus(now: now), .searching)
        r.distance = 1; r.lastUpdate = now; r.state = .ranging
        XCTAssertEqual(r.dotStatus(now: now), .ranging)
        XCTAssertEqual(r.dotStatus(now: now.addingTimeInterval(5)), .stale)
        r.state = .lost
        XCTAssertEqual(r.dotStatus(now: now), .lost)
        r.connected = false
        XCTAssertEqual(r.dotStatus(now: now), .disconnected)
    }

    // MARK: mesh
    func testMeshAveragesBothEndsAndExpires() {
        var m = MeshModel()
        let t = Date()
        m.update(from: "a", distances: ["b": 1.0], at: t)
        m.update(from: "b", distances: ["a": 1.2, "c": 3], at: t)
        let e = m.edges(now: t, maxAge: 3)
        XCTAssertEqual(e.count, 2)
        XCTAssertEqual(e[0], MeshEdge(a: "a", b: "b", distance: 1.1))
        XCTAssertEqual(e[1], MeshEdge(a: "b", b: "c", distance: 3))
        XCTAssertTrue(m.edges(now: t.addingTimeInterval(10), maxAge: 3).isEmpty)
        m.remove("b")
        XCTAssertTrue(m.edges(now: t, maxAge: 3).isEmpty)
    }

    // MARK: layout
    func testLayoutRecoversSquare() {
        let ids = ["me", "b", "c", "d"]
        let s: Float = 2, dg: Float = 2 * Float(2).squareRoot()
        let edges = [MeshEdge(a: "b", b: "c", distance: s), MeshEdge(a: "b", b: "d", distance: dg),
                     MeshEdge(a: "b", b: "me", distance: s), MeshEdge(a: "c", b: "d", distance: s),
                     MeshEdge(a: "c", b: "me", distance: dg), MeshEdge(a: "d", b: "me", distance: s)]
        let pos = RadarLayout.layout(me: "me", players: ids, edges: edges, previous: [:], iterations: 400)
        XCTAssertEqual(pos["me"]!, CGPoint.zero)
        for e in edges {
            let a = pos[e.a]!, b = pos[e.b]!
            XCTAssertEqual(Float(hypot(a.x - b.x, a.y - b.y)), e.distance, accuracy: 0.15, "\(e.a)-\(e.b)")
        }
    }

    func testPolarAheadAndRight() {
        let ahead = RadarLayout.polar(distance: 2, azimuth: 0)
        XCTAssertEqual(ahead.x, 0, accuracy: 0.001); XCTAssertEqual(ahead.y, -2, accuracy: 0.001)
        let right = RadarLayout.polar(distance: 2, azimuth: .pi / 2)
        XCTAssertEqual(right.x, 2, accuracy: 0.001); XCTAssertEqual(right.y, 0, accuracy: 0.001)
    }

    func testAnchoredPeerStaysPinnedAndOthersFollow() {
        let edges = [MeshEdge(a: "b", b: "me", distance: 2), MeshEdge(a: "c", b: "me", distance: 2), MeshEdge(a: "b", b: "c", distance: 2)]
        let anchor = CGPoint(x: -2, y: 0)   // b is to my left
        let pos = RadarLayout.layout(me: "me", players: ["me", "b", "c"], edges: edges, previous: [:], anchors: ["b": anchor])
        XCTAssertEqual(pos["b"]!.x, -2, accuracy: 0.001)
        XCTAssertEqual(Float(hypot(pos["c"]!.x - pos["b"]!.x, pos["c"]!.y - pos["b"]!.y)), 2, accuracy: 0.15)
    }

    func testAzimuthUprightAndFlat() {
        let upright = SIMD3<Float>(0, -1, 0)   // gravity when held upright
        let flat = SIMD3<Float>(0, 0, -1)      // gravity when lying screen-up
        XCTAssertEqual(RangeMath.azimuth(direction: SIMD3(0, 0, -1), gravity: upright)!, 0, accuracy: 0.01)
        XCTAssertEqual(RangeMath.azimuth(direction: SIMD3(1, 0, 0), gravity: upright)!, .pi / 2, accuracy: 0.01)
        XCTAssertEqual(RangeMath.azimuth(direction: SIMD3(0, 1, 0), gravity: flat)!, 0, accuracy: 0.01)
        XCTAssertEqual(RangeMath.azimuth(direction: SIMD3(1, 0, 0), gravity: flat)!, .pi / 2, accuracy: 0.01)
        XCTAssertEqual(RangeMath.azimuth(direction: SIMD3(-1, 0, 0), gravity: flat)!, -.pi / 2, accuracy: 0.01)
        // a flat phone with a vector tilted down toward the table must NOT collapse to "strictly right"
        XCTAssertEqual(RangeMath.azimuth(direction: SIMD3(0.1, 0.9, -0.4), gravity: flat)!, atan2(0.1, 0.9), accuracy: 0.01)
        XCTAssertNil(RangeMath.azimuth(direction: SIMD3(0, 0, 1), gravity: flat))
    }

    func testSinglePeerWithoutBearingStartsAhead() {
        let pos = RadarLayout.layout(me: "me", players: ["me", "b"], edges: [MeshEdge(a: "b", b: "me", distance: 2)], previous: [:])
        XCTAssertEqual(pos["b"]!.x, 0, accuracy: 0.05)
        XCTAssertEqual(pos["b"]!.y, -2, accuracy: 0.05)
    }
}
