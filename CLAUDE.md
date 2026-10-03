# CLAUDE.md

## The game (long-term)
An AR, room-scale social deduction party game. Players have secret roles; some phases are seated in a ring (passive abilities based on immediate neighbors: learn alignments, intercept messages, "poison" adjacent screens), and some are "Free Time" where players walk around and trigger active, proximity-based abilities (secret whisper channels, swapping roles, marking a target). Phones range each other via Ultra-Wideband to build a live spatial map. The app acts as the automatic game master (Jackbox-style shared host screen + personal devices), resolves rule conflicts and produces an event log. The abstract also mentions Android (UWB Jetpack); not built.

**Concrete rules, roles and abilities are NOT defined yet.** Don't invent them in code or docs; ask.

## What exists today: a proof-of-concept
Native SwiftUI iPhone app (iOS 16+, no server) that answers: does Nearby Interaction work well enough for this game? Players host/join a game by 4-letter code (max 8), every phone ranges every other phone, and a radar shows all players with distances on every edge. No roles or game logic yet. See `PLAN.md` for the design/rationale and `INSTRUCTIONS.md` for installing and testing.

## Architecture (`UWBDistance/`)
- `PeerConnection.swift`: MultipeerConnectivity transport. ONE shared `MCSession`, every device advertises + browses with `discoveryInfo["code"]`, deterministic `shouldInvite` tiebreak so exactly one side invites per pair, `canAccept` enforces the player cap. Keep it behind its callbacks (`onPeerConnected/Disconnected/onData`, `send`, `broadcast`) so the transport can be swapped (per-pair sessions or Network.framework for >8 players).
- `PeerSession.swift`: one `NISession` per remote peer, plus delegate handling (suspension, timeout retry, invalidation then recreate and resend token). Publishes a `PeerRange`.
- `NearbyService.swift`: `@MainActor` ObservableObject. Owns the connection, the per-peer `PeerSession`s, the 4 Hz `tick()` (gossip own distances, resend stuck tokens, rebuild edges + layout, CSV recording) and the event log.
- `Messages.swift`: `WireMessage` JSON envelope (`token`, `distances`, `status`).
- `MeshModel.swift`: pairwise distance matrix from own + gossiped readings; averages both ends of an edge; expires old readings.
- `RadarLayout.swift`: distance matrix to 2D positions (force relaxation), me pinned at origin; warm-started per frame.
- `PeerRange.swift`: per-peer state + `dotStatus(now:)` (green/yellow/red/grey logic).
- Views: `HomeView` (name, host, join), `LobbyView`, `RadarView` (Canvas), `DiagnosticsView`; `UWBDistanceApp.swift` has `RootView` routing and forwards foreground/background to peers.

## Build / test
- Project is generated from `project.yml`: `xcodegen generate`. It overwrites signing settings, so keep `DEVELOPMENT_TEAM` in `project.yml` in sync (currently Simon's team).
- Unit tests (simulator): `xcodebuild test -scheme UWBDistance -destination 'platform=iOS Simulator,name=<an installed iPhone>' CODE_SIGNING_ALLOWED=NO`
- Compile check for device: `xcodebuild build -scheme UWBDistance -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`
- Ranging can only be verified on real UWB iPhones (11+, not SE); the simulator can't.

## Gotchas
- `NISession` ranges ONE peer; N peers = N sessions. A discovery token must not be reused across sessions. Concurrent-session limit is undocumented; the POC is meant to find it (Diagnostics shows errors).
- `MCSession.maximumNumberOfPeers` is 8 (self + 7). That's the player cap until the transport changes.
- A token can arrive before our own `.connected` callback creates the `PeerSession`; `NearbyService.pendingTokens` buffers it. Tokens are also resent after 8 s if a peer never produced a reading.
- iOS 16+ returns a generic `UIDevice.current.name`, so players type a name; peer ids are `name-XXXX` (random suffix), shown via `String.playerShortName`.
- UWB gives distance (+ direction relative to the local phone, unreliable, needs U1/U2 and good angle). It gives no absolute positions: the radar can be rotated/mirrored vs. the real room.
- NI is suspended in the background; the app sends `status(suspended:)` so others show yellow. Foreground only.
- iPhone SE has no UWB. Free Apple ID builds expire after 7 days.

## Status / findings
- Unit tests pass; builds for device. **Not yet verified on real phones**: end-to-end ranging (an earlier 2-phone test got stuck on "searching"; a token-race fix and resend were added but are untested), the 8-phone mesh, wall/angle accuracy, and the NISession concurrency limit. Record results here after testing.
