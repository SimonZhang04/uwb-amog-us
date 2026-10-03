import Foundation

/// Everything two phones say to each other over the shared MCSession.
enum WireMessage: Codable, Equatable {
    /// Our NISession discovery token for the receiving peer.
    case token(Data)
    /// Our fresh UWB readings, keyed by peer id (gossip so every phone sees every edge).
    case distances([String: Float])
    /// Sent when the app goes to/from the background (NI is suspended in the background).
    case status(suspended: Bool)

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WireMessage? { try? JSONDecoder().decode(WireMessage.self, from: data) }
}

extension String {
    /// Peer ids look like "Simon-AB12" (name + random suffix so duplicates don't collide).
    var playerShortName: String {
        guard count > 5, self[index(endIndex, offsetBy: -5)] == "-" else { return self }
        return String(dropLast(5))
    }
}
