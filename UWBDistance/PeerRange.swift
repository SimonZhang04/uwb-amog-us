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
    var errorMessage: String?
    var connected = true
    var remoteSuspended = false
    var lastUpdate: Date?
    var updateCount = 0
    var rate: Double = 0   // smoothed updates per second

    var hasDirection: Bool { direction != nil }

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
}
