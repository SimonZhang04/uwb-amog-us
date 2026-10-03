import SwiftUI

@main
struct UWBDistanceApp: App {
    @StateObject private var service = NearbyService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(service: service)
                .onChange(of: scenePhase) { service.setForeground($0 == .active) }
        }
    }
}

struct RootView: View {
    @ObservedObject var service: NearbyService

    var body: some View {
        if service.gameCode == nil {
            HomeView(service: service)
        } else if service.showRadar {
            RadarView(service: service)
        } else {
            LobbyView(service: service)
        }
    }
}
