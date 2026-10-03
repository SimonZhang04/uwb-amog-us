# Plan: UWB Social-Deduction POC (up to 8 phones for now, radar mesh)

Supersedes the earlier 2–3 phone plan. We keep most of the existing code and change the pairing flow, the transport layout, and the main UI.

## Goal (today's POC)
Prove Nearby Interaction works technically for the game: native iPhone app, no server, a "game" of up to 8 phones (10 is the eventual target), a radar-style mesh showing every player and the distance on each edge, graceful handling of dropouts, and enough diagnostics to see UWB's limits (walls, angles, range).

## Concerns / decisions to confirm (these change the design)
1. **MCSession caps at 8 peers (decided: keep ONE shared `MCSession` for now).** That means the POC supports **at most 8 phones per game (self + 7)**, not 10. Accepted trade-off: simplest change, and 8 is enough to answer the UWB questions. To get to 10 later, either switch to one `MCSession` per pair or move the transport to Network.framework. Keep the transport behind a small interface (`send(data,to:)`, `onPeerConnected`, `onPeerDisconnected`, `onData`) so that swap doesn't touch ranging or UI.
2. **Full mesh at 8 phones = 7 NISessions per phone (28 pairs total; 9 and 45 at 10).** Apple doesn't document a concurrent-session cap, and it may be lower than 9 on some devices. Plan: surface per-peer `NIError`, and add a debug counter. If we hit a cap, fall back to ranging only nearby/closest peers or a ring topology. This is the biggest technical unknown, so it's the thing this POC must answer.
3. **Each phone only measures its own links.** To draw edges between *other* players, every phone **gossips its distance table** over Multipeer (e.g. 2 Hz, small JSON). Every phone then holds the full pairwise matrix.
4. **No absolute positions exist.** UWB gives pairwise distance (+ direction relative to *my* phone). Layout = stress-minimisation (MDS/force-directed) over the distance matrix, with me pinned at the center. Direction vectors are used to orient neighbors only when available (they're unreliable and U1/U2-dependent). The layout is mirror-ambiguous and rotates arbitrarily. That's fine for a POC but must be known when we do seating-ring logic later.
5. **Android is out of scope.** The abstract mentions Android UWB Jetpack. iOS NI and Android UWB don't interoperate in this setup; POC is iPhone-only (iPhone 11+, not SE).
6. **Pairing is decentralized**, so "up to 8" is enforced by a host-set cap checked when accepting invitations (best-effort, no server).
7. Last bug: phones were stuck on "searching". I added a token-buffering fix (race where the token arrived before the local session existed); **it is untested on devices and uncommitted**. Step 0 below re-verifies it before the larger refactor.

## What we keep
`PeerSession.swift` (one NISession per peer, suspension/invalidation handling), `TokenCoding`, `PeerRange` (extended), `RangeMath`, project setup (`project.yml`, xcodegen), tests. `PeerConnection.swift` and `NearbyService.swift` are refactored; `ContentView.swift` is replaced.

## Changes

### Step 0 – Re-verify the 2-phone baseline
Run the current build with the token-buffering fix on 2 phones; confirm distance appears. If still "searching", add logging (token sent/received, `didUpdate` contents, `NIError`) before proceeding. Don't build multi-phone infrastructure on a broken baseline.

### Step 1 – Pairing: Host / Join by code (`PeerConnection.swift`)
- Home screen: **Host Game** (generates a 4-letter code, displays it) and **Join Game** (enter code).
- Service type `uwbdist`; advertise `discoveryInfo = ["code": CODE, "id": uuid]`. Browsers only invite peers whose code matches.
- Keep the single shared `MCSession`. Keep the deterministic invite tiebreak (`shouldInvite`) so exactly one side invites each pair; every device in the game both advertises and browses, so all pairs link up (full mesh).
- Cap: a `maxPlayers = 8` check (`MCSession.maximumNumberOfPeers`)  when accepting invitations; reject beyond it.
- Handle reconnect: if a peer drops and returns, rebuild their `PeerSession` (fresh token) as today.

### Step 2 – Ranging per peer (`PeerSession`, `NearbyService`)
- Keep one `NISession` per peer. Extend `PeerRange` with: `connectionState` (connected / disconnected), `niState`, `lastUpdate: Date`, `hasDirection`, `updateCount` (for a Hz readout), `errorMessage`.
- Mark readings **stale** if no update for ~2 s (dot dims, distance shows last known + age).
- App backgrounded → `sessionWasSuspended` → show "suspended" on the *remote* phones' radars too (broadcast a `status` message).

### Step 3 – Gossip + mesh model (new `MeshModel.swift`)
- Message envelope (Codable JSON over each pair's MCSession): `.token(Data)`, `.distances([peerID: Float?], timestamp)`, `.status(...)`.
- `MeshModel`: `[PlayerID: [PlayerID: Float]]` pairwise matrix, merged from own readings + received tables. Edge distance shown = latest fresh value, preferring the lower-id endpoint's reading (or averaging both) so the two phones agree.
- Pure functions (unit-tested): matrix merge, staleness, symmetric edge selection.

### Step 4 – Layout (new `RadarLayout.swift`)
- Input: pairwise matrix + my id. Output: `[PlayerID: CGPoint]` in meters.
- Me at origin. Stress-minimisation (SMACOF or a few hundred force-iteration steps), warm-started from the previous frame to avoid jitter; missing distances use weak springs. Low-pass smoothing on positions.
- Unit tests with synthetic matrices (known triangle/square → recovered distances within tolerance).

### Step 5 – Radar UI (replace `ContentView.swift`)
- `HomeView` (host/join) → `LobbyView` (code, joined players list, "Start" shows the radar; for the POC, anyone can enter the radar) → `RadarView`.
- `RadarView` (SwiftUI `Canvas`): concentric range rings, my dot (center, accent color), other dots (named/initial), **edges to all others with a distance label at the midpoint** (`1.42 m`). Auto-zoom to fit all dots; pinch to zoom optional.
- Dot colors: green = ranging, yellow = stale/searching, **red = NI lost / out of UWB range**, **grey = app closed / Multipeer disconnected**.
- Bottom sheet / toggle **Diagnostics**: per-peer table: state, distance, direction yes/no (+ azimuth), update Hz, last update age, NIError, my capabilities. Plus a "session count / max reached" line to answer concern #2.
- Optional: **Record CSV** button (timestamp, peer, distance, direction) shareable via the share sheet, to analyse wall/angle tests later.

### Step 6 – Tests
- Unit tests: invite tiebreak with 8 ids (exactly one inviter per pair), message encode/decode, mesh merge/staleness, layout recovery, player cap.
- Existing tests stay.

### Step 7 – Docs
- **`INSTRUCTIONS.md`**: install on personal phones (Xcode + free Apple ID, Personal Team, unique bundle ID, cable, Trust, Developer Mode, trust profile in Settings, 7-day expiry, wireless debugging), how to host/join a game, how to run the wall/angle tests, known limitations.
- **`CLAUDE.md`**: game summary (from the abstract: Jackbox-style host screen, seated phases with neighbor passive abilities, Free Time with proximity abilities, auto-moderated event log), the POC's scope, architecture map (files above), build/test commands (`xcodegen generate`, `xcodebuild test ...`), gotchas (simulator has no UWB, one NISession per peer, token per session never reused, 8-peer MCSession limit, direction is unreliable, xcodegen resets signing team). **Game rules aren't specified yet**, so CLAUDE.md will say so rather than invent them.

## Files
New: `MeshModel.swift`, `RadarLayout.swift`, `Messages.swift`, `HomeView.swift`, `LobbyView.swift`, `RadarView.swift`, `DiagnosticsView.swift`, `INSTRUCTIONS.md`, `CLAUDE.md`.
Modified: `PeerConnection.swift`, `NearbyService.swift`, `PeerSession.swift`, `PeerRange.swift`, `UWBDistanceApp.swift`, `project.yml` (no new Info.plist keys expected), tests.
Removed: `ContentView.swift`.

## Verification
- `xcodebuild test` (simulator) passes the new unit tests; `xcodebuild build -destination 'generic/platform=iOS'` succeeds.
- On devices (the POC's real test): 2 phones first, then 3, then as many as available up to 8. Check: all join with the same code; every phone shows every other phone with edges and labels; distances agree across both ends (within ~10–20 cm); closing an app turns that dot grey on the others within a few seconds and it recovers on reopen; walking behind a wall → red/stale; diagnostics shows direction availability and update rate; note the max concurrent sessions reached.
- Record findings (accuracy, wall behavior, session cap) in `CLAUDE.md` after the test.

## Out of scope
Roles, abilities, phases, host display screen, Android, background ranging, any server.
