import Foundation
import simd

enum PeerState: String {
    case connecting, searching, ranging, lost, error
}

/// What the radar shows for a peer's dot.
enum DotStatus: String {
    case ranging        // green: fresh UWB reading
    case stale          // yellow: readings stopped (or peer app backgrounded)
    case searching      // yellow: connected, no distance yet
    case lost           // red: Nearby Interaction lost the peer / errored
    case disconnected   // grey: Multipeer link gone (app closed, out of range)
}

struct PeerRange: Identifiable, Equatable {
    let id: String
    var state: PeerState = .connecting
    var distance: Float?
    var direction: SIMD3<Float>?
    /// Radians, 0 = straight ahead of the phone, positive = to the right. Nil if unknown.
    var azimuth: Float?
    var errorMessage: String?
    var connected = true
    var remoteSuspended = false
    var lastUpdate: Date?
    var updateCount = 0
    var rate: Double = 0   // smoothed updates per second

    var hasDirection: Bool { azimuth != nil }

    func dotStatus(now: Date, staleAfter: TimeInterval = 2) -> DotStatus {
        if !connected { return .disconnected }
        if state == .lost || state == .error { return .lost }
        if remoteSuspended { return .stale }
        guard distance != nil, let last = lastUpdate else { return .searching }
        return now.timeIntervalSince(last) > staleAfter ? .stale : .ranging
    }
}

enum RangeMath {
    /// Angle in radians (0 = straight ahead, positive = right) from a device-frame direction vector.
    static func arrowAngle(for direction: SIMD3<Float>) -> Double {
        Double(atan2(direction.x, -direction.z))
    }

    /// Bearing in radians (0 = ahead of the phone, positive = right) from a device-frame direction vector,
    /// using gravity so it works held upright OR flat. "Ahead" is the rear-camera axis when upright and the
    /// top edge when flat. Nil if the vector is (almost) vertical and has no horizontal part.
    static func azimuth(direction d: SIMD3<Float>, gravity g: SIMD3<Float>) -> Float? {
        let gl = simd_length(g)
        guard gl > 0.5 else { return nil }
        let up = -g / gl
        let forwardAxis: SIMD3<Float> = abs(up.z) < 0.7 ? SIMD3(0, 0, -1) : SIMD3(0, 1, 0)
        func horizontal(_ v: SIMD3<Float>) -> SIMD3<Float> { v - simd_dot(v, up) * up }
        let fh = horizontal(forwardAxis), dh = horizontal(d)
        guard simd_length(fh) > 1e-3, simd_length(dh) > 1e-3 else { return nil }
        let f = simd_normalize(fh)
        let right = simd_cross(f, up)
        return atan2(simd_dot(dh, right), simd_dot(dh, f))
    }
}
