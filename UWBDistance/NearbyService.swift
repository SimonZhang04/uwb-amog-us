import Foundation
import MultipeerConnectivity
import NearbyInteraction
import CoreGraphics

@MainActor
final class NearbyService: ObservableObject {
    static let maxPlayers = 8   // one shared MCSession: self + 7 (see PLAN.md)
    static let edgeMaxAge: TimeInterval = 3

    @Published var gameCode: String?
    @Published var showRadar = false
    @Published private(set) var myID = ""
    @Published private(set) var peers: [PeerRange] = []
    @Published private(set) var edges: [MeshEdge] = []
    @Published private(set) var positions: [String: CGPoint] = [:]
    @Published private(set) var logLines: [String] = []
    @Published private(set) var isRecording = false
    @Published private(set) var recordingURL: URL?

    let supportsUWB = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    let supportsDirection = NISession.deviceCapabilities.supportsDirectionMeasurement

    private var connection: PeerConnection?
    private var sessions: [String: PeerSession] = [:]
    private var peerIDs: [String: MCPeerID] = [:]
    /// Tokens that arrived before our own `.connected` callback created the PeerSession.
    private var pendingTokens: [String: Data] = [:]
    private var mesh = MeshModel()
    private var timer: Timer?
    private var tickCount = 0
    private var recordRows: [String] = []

    var connectedCount: Int { peers.filter(\.connected).count }

    // MARK: Game lifecycle
    static func randomCode() -> String {
        String((0..<4).map { _ in "ABCDEFGHJKLMNPQRSTUVWXYZ".randomElement()! })
    }

    func host(name: String) { start(code: Self.randomCode(), name: name) }
    func join(code: String, name: String) { start(code: code.uppercased().trimmingCharacters(in: .whitespaces), name: name) }

    private func start(code: String, name: String) {
        guard supportsUWB, !code.isEmpty else { return }
        let conn = PeerConnection(gameCode: code, playerName: name, maxPlayers: Self.maxPlayers)
        conn.onPeerConnected = { [weak self] in self?.add($0) }
        conn.onPeerDisconnected = { [weak self] in self?.remove($0) }
        conn.onData = { [weak self] data, peer in self?.handle(data, from: peer) }
        connection = conn
        myID = conn.myPeerID.displayName
        gameCode = code
        log("started game \(code) as \(myID.playerShortName)")
        conn.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func leave() {
        timer?.invalidate(); timer = nil
        if isRecording { stopRecording() }
        sessions.values.forEach { $0.stop() }
        connection?.stop()
        connection = nil
        sessions = [:]; peerIDs = [:]; pendingTokens = [:]
        mesh = MeshModel()
        peers = []; edges = []; positions = [:]
        gameCode = nil; showRadar = false
    }

    func setForeground(_ foreground: Bool) {
        guard let data = WireMessage.status(suspended: !foreground).encoded() else { return }
        connection?.broadcast(data)
    }

    // MARK: Peers
    private func add(_ peer: MCPeerID) {
        let name = peer.displayName
        peerIDs[name] = peer
        sessions[name]?.stop()
        let ps = PeerSession(peerName: name)
        ps.onLog = { [weak self] in self?.log($0) }
        ps.onNeedsTokenResend = { [weak self, weak ps] in
            guard let data = ps?.localTokenData else { return }
            self?.sendToken(data, to: name)
        }
        sessions[name] = ps
        log("\(name.playerShortName) connected")
        if let data = ps.localTokenData { sendToken(data, to: name) }
        if let pending = pendingTokens.removeValue(forKey: name) { ps.receive(peerTokenData: pending) }
    }

    private func remove(_ peer: MCPeerID) {
        let name = peer.displayName
        sessions[name]?.markDisconnected()
        pendingTokens[name] = nil
        mesh.remove(name)
        log("\(name.playerShortName) disconnected")
    }

    private func sendToken(_ data: Data, to name: String) {
        guard let peer = peerIDs[name], let msg = WireMessage.token(data).encoded() else { return }
        connection?.send(msg, to: peer)
    }

    private func handle(_ data: Data, from peer: MCPeerID) {
        guard let msg = WireMessage.decode(data) else { return }
        let name = peer.displayName
        switch msg {
        case .token(let token):
            log("token from \(name.playerShortName)")
            if let ps = sessions[name] { ps.receive(peerTokenData: token) } else { pendingTokens[name] = token }
        case .distances(let d):
            mesh.update(from: name, distances: d, at: Date())
        case .status(let suspended):
            sessions[name]?.setRemoteSuspended(suspended)
        }
    }

    // MARK: Periodic work (4 Hz): publish, gossip, layout, record
    private func tick() {
        tickCount += 1
        let now = Date()

        var own: [String: Float] = [:]
        for (name, ps) in sessions where ps.range.dotStatus(now: now) == .ranging {
            if let d = ps.range.distance { own[name] = d }
        }
        mesh.update(from: myID, distances: own, at: now)

        if tickCount % 2 == 0, let data = WireMessage.distances(own).encoded() { connection?.broadcast(data) }

        for (name, ps) in sessions where ps.shouldResendToken(now: now) {
            if let data = ps.localTokenData { sendToken(data, to: name); log("resent token to \(name.playerShortName)") }
        }

        peers = sessions.values.map(\.range).sorted { $0.id < $1.id }
        edges = mesh.edges(now: now, maxAge: Self.edgeMaxAge)
        positions = RadarLayout.layout(me: myID, players: [myID] + sessions.keys.sorted(), edges: edges, previous: positions)

        if isRecording { record(now: now) }
    }

    private func log(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        logLines.append("\(f.string(from: Date())) \(line)")
        if logLines.count > 80 { logLines.removeFirst(logLines.count - 80) }
    }

    // MARK: CSV recording (for wall / angle experiments)
    func startRecording() {
        recordRows = ["timestamp,peer,status,distance_m,azimuth_rad,rate_hz"]
        recordingURL = nil
        isRecording = true
    }

    func stopRecording() {
        isRecording = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uwb-\(Int(Date().timeIntervalSince1970)).csv")
        try? recordRows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        recordingURL = url
    }

    private func record(now: Date) {
        let ts = ISO8601DateFormatter().string(from: now)
        for p in peers {
            let dist = p.distance.map { String(format: "%.3f", $0) } ?? ""
            let az = p.direction.map { String(format: "%.3f", RangeMath.arrowAngle(for: $0)) } ?? ""
            recordRows.append("\(ts),\(p.id.playerShortName),\(p.dotStatus(now: now).rawValue),\(dist),\(az),\(String(format: "%.1f", p.rate))")
        }
    }
}
