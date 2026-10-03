import SwiftUI

@main
struct UWBDistanceApp: App {
    @StateObject private var service = NearbyService()

    var body: some Scene {
        WindowGroup {
            ContentView(service: service)
        }
    }
}
