import Foundation
import NearbyInteraction

/// One NISession ranging exactly one peer.
final class PeerSession: NSObject, NISessionDelegate {
    private(set) var niSession = NISession()
    private var peerToken: NIDiscoveryToken?
    private var lastPeerTokenData: Data?
    private var stopped = false
    private let since = Date()
    private var lastResend: Date?

    var onLog: ((String) -> Void)?
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
        // A retry of a token we already ranged with is a no-op once we have distance.
        if peerTokenData == lastPeerTokenData, range.distance != nil { return }
        guard let token = TokenCoding.decode(peerTokenData) else {
            onLog?("\(range.id.playerShortName): bad token")
            return
        }
        lastPeerTokenData = peerTokenData
        peerToken = token
        niSession.run(NINearbyPeerConfiguration(peerToken: token))
        range.state = .searching
        onLog?("\(range.id.playerShortName): running NI config")
    }

    /// True if we've been waiting a long time without a single reading and should resend our token.
    func shouldResendToken(now: Date) -> Bool {
        guard range.connected, !stopped, range.lastUpdate == nil else { return false }
        if now.timeIntervalSince(lastResend ?? since) < 8 { return false }
        lastResend = now
        return true
    }

    func setRemoteSuspended(_ suspended: Bool) { range.remoteSuspended = suspended }

    func stop() {
        stopped = true
        niSession.invalidate()
    }

    func markDisconnected() {
        stop()
        range.connected = false
        range.distance = nil
        range.direction = nil
    }

    // MARK: NISessionDelegate
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let obj = nearbyObjects.first else { return }
        let now = Date()
        if let last = range.lastUpdate {
            let dt = now.timeIntervalSince(last)
            if dt > 0 { range.rate = range.rate == 0 ? 1 / dt : 0.8 * range.rate + 0.2 / dt }
        }
        range.distance = obj.distance
        range.direction = obj.direction
        range.state = obj.distance == nil ? .searching : .ranging
        range.errorMessage = nil
        range.updateCount += 1
        if obj.distance != nil { range.lastUpdate = now }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        range.distance = nil
        range.direction = nil
        if reason == .timeout, let peerToken {
            session.run(NINearbyPeerConfiguration(peerToken: peerToken))
            range.state = .lost
            onLog?("\(range.id.playerShortName): NI timeout, retrying")
        } else {
            range.state = .lost
            onLog?("\(range.id.playerShortName): NI peer ended")
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        range.state = .searching
        onLog?("NI suspended (\(range.id.playerShortName))")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        if let peerToken { session.run(NINearbyPeerConfiguration(peerToken: peerToken)) }
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        guard !stopped else { return }
        // Recreate with a fresh token and ask the peer to re-pair.
        peerToken = nil
        lastPeerTokenData = nil
        niSession = NISession()
        niSession.delegate = self
        range.state = .error
        range.distance = nil
        range.direction = nil
        range.errorMessage = error.localizedDescription
        onLog?("\(range.id.playerShortName): NI error \(error.localizedDescription)")
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
