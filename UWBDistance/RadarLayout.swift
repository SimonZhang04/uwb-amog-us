import CoreGraphics
import Foundation

/// Turns a pairwise distance matrix into 2D positions (meters) with "me" pinned at the origin.
/// UWB gives distances only, so the result can be rotated/mirrored relative to the room.
enum RadarLayout {
    /// Screen-style coordinates: +x right, +y down, so "ahead of my phone" is -y.
    static func polar(distance: Float, azimuth: Float) -> CGPoint {
        CGPoint(x: CGFloat(distance * sin(azimuth)), y: CGFloat(-distance * cos(azimuth)))
    }

    /// `anchors` are positions known directly from UWB direction (peers I can see an angle to); they stay pinned.
    static func layout(me: String, players: [String], edges: [MeshEdge],
                       previous: [String: CGPoint], anchors: [String: CGPoint] = [:],
                       iterations: Int = 150) -> [String: CGPoint] {
        var pos = previous.filter { players.contains($0.key) }
        pos[me] = .zero
        let pinned = Set(anchors.keys.filter { players.contains($0) })
        for p in pinned { pos[p] = anchors[p] }
        let others = players.filter { $0 != me }
        for (i, p) in others.enumerated() where pos[p] == nil {
            let direct = edges.first { ($0.a == me && $0.b == p) || ($0.b == me && $0.a == p) }
            let r = CGFloat(direct?.distance ?? 1.5)
            let angle = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(max(others.count, 1))
            pos[p] = CGPoint(x: r * CGFloat(cos(angle)), y: r * CGFloat(sin(angle)))
        }

        let usable = edges.filter { pos[$0.a] != nil && pos[$0.b] != nil }
        for _ in 0..<iterations {
            for e in usable {
                guard let pa = pos[e.a], let pb = pos[e.b] else { continue }
                var vx = pb.x - pa.x, vy = pb.y - pa.y
                var len = hypot(vx, vy)
                if len < 1e-3 { vx = 1e-3; vy = 0; len = 1e-3 }
                let aPinned = pinned.contains(e.a) || e.a == me, bPinned = pinned.contains(e.b) || e.b == me
                if aPinned && bPinned { continue }
                let move = (len - CGFloat(e.distance)) / len
                let wa: CGFloat = aPinned ? 0 : (bPinned ? 0.5 : 0.25)
                let wb: CGFloat = bPinned ? 0 : (aPinned ? 0.5 : 0.25)
                pos[e.a] = CGPoint(x: pa.x + vx * move * wa, y: pa.y + vy * move * wa)
                pos[e.b] = CGPoint(x: pb.x - vx * move * wb, y: pb.y - vy * move * wb)
            }
        }

        let off = pos[me] ?? .zero
        return pos.mapValues { CGPoint(x: $0.x - off.x, y: $0.y - off.y) }
    }
}
