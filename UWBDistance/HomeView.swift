import SwiftUI

struct HomeView: View {
    @ObservedObject var service: NearbyService
    @AppStorage("playerName") private var playerName = ""
    @State private var code = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("UWB Radar").font(.largeTitle.bold())
            if !service.supportsUWB {
                Text("This device doesn't support Ultra Wideband ranging.\nUse an iPhone 11 or newer (not SE).")
                    .multilineTextAlignment(.center).foregroundColor(.red)
            }
            TextField("Your name", text: $playerName)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled()

            Button { service.host(name: playerName) } label: {
                Text("Host Game").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).controlSize(.large)

            Divider()

            TextField("Game code", text: $code)
                .textFieldStyle(.roundedBorder).textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button { service.join(code: code, name: playerName) } label: {
                Text("Join Game").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).controlSize(.large).disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
        .padding(24)
        .disabled(!service.supportsUWB)
    }
}
