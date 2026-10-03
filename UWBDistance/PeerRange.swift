import Foundation
import simd

enum PeerState: String {
    case connecting, ranging, searching, lost, error
}

struct PeerRange: Identifiable, Equatable {
    let id: String          // peer display name
    var state: PeerState = .connecting
    var distance: Float?
    var direction: SIMD3<Float>?
    var errorMessage: String?
}

enum RangeMath {
    /// Angle in radians to rotate an up-pointing arrow so it points toward the peer
    /// (0 = straight ahead, positive = clockwise/right). Uses the device-frame direction vector.
    static func arrowAngle(for direction: SIMD3<Float>) -> Double {
        Double(atan2(direction.x, -direction.z))
    }
}
