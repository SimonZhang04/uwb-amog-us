import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var service: NearbyService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("This device") {
                    row("Precise distance", service.supportsUWB ? "yes" : "no")
                    row("Direction", service.supportsDirection ? "yes" : "no")
                    row("Extended range", service.supportsExtendedDistance ? "yes" : "no")
                    row("Game", service.gameCode ?? "-")
                    row("Players connected", "\(1 + service.connectedCount) / \(NearbyService.maxPlayers)")
                    row("NI sessions", "\(service.connectedCount)")
                    row("NI errors", "\(service.peers.filter { $0.state == .error }.count)")
                }
                Section("Peers") {
                    ForEach(service.peers) { p in peerRow(p) }
                    if service.peers.isEmpty { Text("None yet").foregroundColor(.secondary) }
                }
                Section("Log") {
                    ForEach(Array(service.logLines.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func peerRow(_ p: PeerRange) -> some View {
        let now = Date()
        let age = p.lastUpdate.map { String(format: "%.1fs ago", now.timeIntervalSince($0)) } ?? "never"
        let az = p.azimuth.map { String(format: "%.0f°", $0 * 180 / .pi) }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle().fill(p.dotStatus(now: now).color).frame(width: 10, height: 10)
                Text(p.id.playerShortName).font(.headline)
                Spacer()
                Text(p.distance.map { String(format: "%.2f m", $0) } ?? "—").monospacedDigit()
            }
            Text("\(p.dotStatus(now: now).rawValue) · NI \(p.state.rawValue) · \(p.connected ? "linked" : "disconnected")"
                 + (p.remoteSuspended ? " · backgrounded" : ""))
            Text("bearing: \(az ?? "none") · \(String(format: "%.1f", p.rate)) Hz · last \(age) · \(p.updateCount) updates")
            if let err = p.errorMessage { Text(err).foregroundColor(.red) }
        }
        .font(.caption)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(.secondary) }
    }
}
