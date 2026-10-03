import SwiftUI

struct LobbyView: View {
    @ObservedObject var service: NearbyService

    var body: some View {
        VStack(spacing: 16) {
            Text("Game code").foregroundColor(.secondary)
            Text(service.gameCode ?? "").font(.system(size: 56, weight: .bold, design: .monospaced))
            Text("Others join by entering this code.").font(.footnote).foregroundColor(.secondary)

            List {
                Section("Players (\(1 + service.connectedCount)/\(NearbyService.maxPlayers))") {
                    Label("\(service.myID.playerShortName) (you)", systemImage: "person.fill")
                    ForEach(service.peers) { p in
                        Label(p.id.playerShortName, systemImage: p.connected ? "person" : "person.slash")
                            .foregroundColor(p.connected ? .primary : .secondary)
                    }
                    if service.peers.isEmpty {
                        HStack { ProgressView(); Text("Looking for players…").foregroundColor(.secondary) }
                    }
                }
            }

            Button { service.showRadar = true } label: {
                Text("Open Radar").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            Button("Leave Game", role: .destructive) { service.leave() }
        }
        .padding()
    }
}
