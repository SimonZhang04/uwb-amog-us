# UWB Multi-Peer Distance App (Swift / SwiftUI)

## Context
Build an iOS app that measures distance (and direction) from one iPhone to several other iPhones (target: 3 phones, each ranging the other two) using Ultra Wideband via Apple's NearbyInteraction framework. Project dir `/Users/simonzh/Documents/SE 490` is empty (greenfield, not a git repo). Xcode 26.3 is installed.

## Constraints to know up front
- **Simulator cannot do UWB.** Testing needs 3 physical iPhones with U1/U2 chip (iPhone 11 or newer; not SE).
- `distance` is the robust value. `direction` is only reliable when both devices are U1/U2 and roughly facing each other. Use `NISession.deviceCapabilities` (iOS 16+) to check `supportsPreciseDistanceMeasurement` / `supportsDirectionMeasurement`.
- NearbyInteraction ranges **one peer per `NISession`**, so N peers means N sessions. Concurrent-session limits are device-dependent; 2 peers per phone is fine, but handle failures gracefully (surface `NIError` per peer rather than crashing).
- Minimum deployment: iOS 16. Info.plist: `NSNearbyInteractionUsageDescription`, `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_uwbdist._tcp`, `_uwbdist._udp`).
- Foreground only in v1 (no background ranging).

## Approach
Discovery and token exchange via **MultipeerConnectivity**; ranging via **one NISession per peer**; UI in **SwiftUI** (list of peers).

Flow per pair of phones A and B: each side creates a *dedicated* `NISession` for that peer, sends its `discoveryToken` (archived with `NSKeyedArchiver`) to that peer over the shared `MCSession`, and on receiving the peer's token runs `NINearbyPeerConfiguration(peerToken:)`. A phone with 2 peers therefore holds 2 sessions and sends a separate token per peer (a token must not be reused across sessions).

## Files (new Xcode project "UWBDistance")
- `UWBDistanceApp.swift` – `@main` entry.
- `ContentView.swift` – SwiftUI list: one row per peer with name, distance (m), direction arrow, state ("connecting / ranging / lost"). Banner for unsupported device.
- `PeerRange.swift` – model: peer ID, `distance: Float?`, `direction: SIMD3<Float>?`, state enum.
- `PeerSession.swift` – owns one `NISession` + its delegate for a single peer; publishes `PeerRange`; handles `didUpdate`, `didRemove`, suspension (re-run config), invalidation (recreate session and resend token).
- `NearbyService.swift` – `ObservableObject` holding `[MCPeerID: PeerSession]`; creates/destroys `PeerSession` on peer connect/disconnect; routes incoming token data to the right `PeerSession`; publishes sorted `[PeerRange]` for the UI.
- `PeerConnection.swift` – wraps `MCNearbyServiceAdvertiser` + `MCNearbyServiceBrowser` + one `MCSession`; every device advertises and browses; invite tiebreak (lower display name invites) to avoid duplicate invites; auto-accept; connect/disconnect callbacks; `send(token, to:)`.
- `Info.plist` keys above.
- `UWBDistanceTests/` – unit tests for token (de)serialization, direction→angle math, and the invite tiebreak (pure functions). Ranging is manual.

## Steps
1. Create the Xcode project (SwiftUI, iOS 16+), preferably via `xcodegen` + `project.yml` so it's scriptable from the CLI; fall back to the Xcode GUI if unavailable.
2. Implement `PeerConnection`; verify 3 devices all connect to each other (log peers).
3. Implement `PeerSession` + `NearbyService`; show raw per-peer distance for 2 phones, then 3.
4. Add direction arrow, capability checks, per-peer error/suspension/reconnect handling.
5. Unit tests for pure helpers.

## Installing on the phones (free Apple ID is enough)
Sign in under Xcode > Settings > Accounts; set a unique bundle ID and Personal Team; for each phone: cable in, Trust, enable Developer Mode, Run from Xcode, then trust the profile in Settings > General > VPN & Device Management. Free installs expire after 7 days (just reinstall). TestFlight needs the paid program ($99/yr) and is only worth it if a phone can't be plugged into your Mac.

## Verification
- `xcodebuild -scheme UWBDistance -destination 'generic/platform=iOS' build` compiles; `xcodebuild test` on a simulator runs the unit tests.
- Manual with 3 iPhones: grant Local Network + Nearby Interaction prompts; each phone lists the other two; distances track moves (~0.5 m, 1 m, 3 m vs. tape measure) and agree between the two ends of a pair; turn one phone away/pocket it and confirm its row goes to "lost" and recovers; kill and relaunch one app and confirm the others re-pair.
- Simulator only confirms the UI and the "UWB not supported" state.

## Risks
- Distance becomes `nil` without line-of-sight or at steep angles; UI shows "searching".
- Concurrent session limit may cap peers on some devices; surface the error per peer.
- Reconnect races (both sides recreate sessions at once); mitigated by the deterministic invite tiebreak and by always resending a fresh token after a session is recreated.
