import Foundation
import MultipeerConnectivity
import NearbyInteraction

@MainActor
final class NearbyService: ObservableObject {
    @Published private(set) var peers: [PeerRange] = []
    @Published private(set) var supportsUWB = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement

    private let connection = PeerConnection()
    private var sessions: [MCPeerID: PeerSession] = [:]

    init() {
        guard supportsUWB else { return }
        connection.onPeerConnected = { [weak self] in self?.add($0) }
        connection.onPeerDisconnected = { [weak self] in self?.remove($0) }
        connection.onData = { [weak self] data, peer in self?.sessions[peer]?.receive(peerTokenData: data) }
        connection.start()
    }

    private func add(_ peer: MCPeerID) {
        sessions[peer]?.invalidate()
        let ps = PeerSession(peerName: peer.displayName)
        ps.onUpdate = { [weak self] _ in self?.refresh() }
        ps.onNeedsTokenResend = { [weak self, weak ps] in
            guard let data = ps?.localTokenData else { return }
            self?.connection.send(data, to: peer)
        }
        sessions[peer] = ps
        if let data = ps.localTokenData { connection.send(data, to: peer) }
        refresh()
    }

    private func remove(_ peer: MCPeerID) {
        sessions[peer]?.invalidate()
        sessions[peer] = nil
        refresh()
    }

    private func refresh() {
        peers = sessions.values.map(\.range).sorted { $0.id < $1.id }
    }
}
