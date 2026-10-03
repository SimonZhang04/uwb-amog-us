import Foundation
import NearbyInteraction

/// One NISession ranging exactly one peer.
final class PeerSession: NSObject, NISessionDelegate {
    private(set) var niSession = NISession()
    private var peerToken: NIDiscoveryToken?

    var onUpdate: ((PeerRange) -> Void)?
    /// Called when the local token changed (session recreated) and must be re-sent to the peer.
    var onNeedsTokenResend: (() -> Void)?

    private(set) var range: PeerRange

    init(peerName: String) {
        range = PeerRange(id: peerName)
        super.init()
        niSession.delegate = self
    }

    var localTokenData: Data? {
        guard let token = niSession.discoveryToken else { return nil }
        return TokenCoding.encode(token)
    }

    func receive(peerTokenData: Data) {
        guard let token = TokenCoding.decode(peerTokenData) else { return }
        peerToken = token
        niSession.run(NINearbyPeerConfiguration(peerToken: token))
        publish { $0.state = .searching }
    }

    func invalidate() { niSession.invalidate() }

    private func publish(_ change: (inout PeerRange) -> Void) {
        change(&range)
        onUpdate?(range)
    }

    // MARK: NISessionDelegate
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let obj = nearbyObjects.first else { return }
        publish {
            $0.distance = obj.distance
            $0.direction = obj.direction
            $0.state = obj.distance == nil ? .searching : .ranging
            $0.errorMessage = nil
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        if reason == .timeout, let peerToken {
            session.run(NINearbyPeerConfiguration(peerToken: peerToken))
            publish { $0.state = .searching; $0.distance = nil; $0.direction = nil }
        } else {
            publish { $0.state = .lost; $0.distance = nil; $0.direction = nil }
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        publish { $0.state = .searching }
    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let peerToken { session.run(NINearbyPeerConfiguration(peerToken: peerToken)) }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        // Recreate with a fresh token and ask the peer to re-pair.
        peerToken = nil
        niSession = NISession()
        niSession.delegate = self
        publish { $0.state = .error; $0.distance = nil; $0.direction = nil; $0.errorMessage = error.localizedDescription }
        onNeedsTokenResend?()
    }
}

enum TokenCoding {
    static func encode(_ token: NIDiscoveryToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }
    static func decode(_ data: Data) -> NIDiscoveryToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
    }
}
