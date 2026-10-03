import Foundation
import MultipeerConnectivity
import UIKit

/// One shared MCSession for the whole game (so max 8 devices: MCSession.maximumNumberOfPeers).
/// Every device advertises and browses with the game code, so all pairs connect (full mesh).
final class PeerConnection: NSObject {
    static let serviceType = "uwbdist"

    let myPeerID: MCPeerID
    let gameCode: String
    let maxPlayers: Int
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    var onPeerConnected: ((MCPeerID) -> Void)?
    var onPeerDisconnected: ((MCPeerID) -> Void)?
    var onData: ((Data, MCPeerID) -> Void)?

    /// Deterministic tiebreak so only one side of a pair sends the invitation.
    static func shouldInvite(local: String, remote: String) -> Bool { local < remote }

    /// `connectedPeers` excludes ourselves.
    static func canAccept(connectedPeers: Int, maxPlayers: Int) -> Bool { connectedPeers + 1 < maxPlayers }

    init(gameCode: String, playerName: String, maxPlayers: Int) {
        self.gameCode = gameCode
        self.maxPlayers = maxPlayers
        let base = playerName.isEmpty ? UIDevice.current.name : String(playerName.prefix(20))
        myPeerID = MCPeerID(displayName: "\(base)-\(UUID().uuidString.prefix(4))")
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: ["code": gameCode], serviceType: Self.serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    func send(_ data: Data, to peer: MCPeerID) {
        try? session.send(data, toPeers: [peer], with: .reliable)
    }

    func broadcast(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }
}

extension PeerConnection: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected: self.onPeerConnected?(peerID)
            case .notConnected: self.onPeerDisconnected?(peerID)
            default: break
            }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async { self.onData?(data, peerID) }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension PeerConnection: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let sameGame = context.flatMap { String(data: $0, encoding: .utf8) } == gameCode
        let hasRoom = Self.canAccept(connectedPeers: session.connectedPeers.count, maxPlayers: maxPlayers)
        invitationHandler(sameGame && hasRoom, session)
    }
}

extension PeerConnection: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard info?["code"] == gameCode,
              Self.shouldInvite(local: myPeerID.displayName, remote: peerID.displayName) else { return }
        browser.invitePeer(peerID, to: session, withContext: gameCode.data(using: .utf8), timeout: 15)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
