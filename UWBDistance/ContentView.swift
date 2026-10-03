import SwiftUI

struct ContentView: View {
    @ObservedObject var service: NearbyService

    var body: some View {
        NavigationView {
            Group {
                if !service.supportsUWB {
                    Text("This device doesn't support Ultra Wideband ranging.\nUse an iPhone 11 or newer (not SE).")
                        .multilineTextAlignment(.center).padding()
                } else if service.peers.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Looking for nearby phones running this app…").foregroundColor(.secondary)
                    }
                } else {
                    List(service.peers) { PeerRow(peer: $0) }
                }
            }
            .navigationTitle("Nearby")
        }
        .navigationViewStyle(.stack)
    }
}

struct PeerRow: View {
    let peer: PeerRange

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(peer.id).font(.headline)
                Text(peer.errorMessage ?? peer.state.rawValue).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if let d = peer.direction {
                Image(systemName: "arrow.up")
                    .rotationEffect(.radians(RangeMath.arrowAngle(for: d)))
            }
            Text(peer.distance.map { String(format: "%.2f m", $0) } ?? "—")
                .font(.system(.title2, design: .rounded)).monospacedDigit()
        }
    }
}
