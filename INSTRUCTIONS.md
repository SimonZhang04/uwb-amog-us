# Installing and testing the UWB Radar POC

## Requirements
- A Mac with Xcode 26+ (`xcode-select -p` should work) and `xcodegen` (`brew install xcodegen`) if you change `project.yml`.
- iPhones **11 or newer (not SE)**, on iOS 16+. The simulator has no UWB hardware, so it can only show the UI.
- A free Apple ID is enough. A Lightning/USB-C cable for the first install of each phone.

## Install on a phone
1. `git clone https://github.com/SimonZhang04/uwb-amog-us.git` and open `UWBDistance.xcodeproj`.
2. Xcode > Settings > Accounts > **+** > sign in with your Apple ID.
3. Select the **UWBDistance** target > **Signing & Capabilities**:
   - Team: your **Personal Team**.
   - Bundle Identifier: must be unique per developer, e.g. `com.<yourname>.uwbdistance`.
   - `project.yml` currently pins Simon's team ID. Everyone else must pick their own team in Xcode, and should **not** run `xcodegen generate` without editing `DEVELOPMENT_TEAM` there (it overwrites Xcode's setting).
4. Plug the phone in, unlock it, tap **Trust This Computer**.
5. Phone: Settings > Privacy & Security > **Developer Mode** > on, then restart.
6. In Xcode choose the phone as the run destination (top bar) and press **Run**.
7. First launch: phone Settings > General > **VPN & Device Management** > your Apple ID > **Trust**. Then open the app.
8. Accept the **Local Network** and **Nearby Interaction** permission prompts.
9. You can unplug after it launches. Free-signed installs expire after **7 days**: plug in and press Run again to refresh. Every player needs the app installed on their own phone.

## Play / test
1. Everyone opens the app and types a name (optional but helpful, iOS hides device names).
2. One person taps **Host Game** and shows the 4-letter code. Everyone else types it and taps **Join Game**. Max **8 players** (shared Multipeer session limit).
3. The lobby lists who has joined. Tap **Open Radar** (each phone does this itself).
4. Radar: you are the blue center dot. Lines go between every pair of players with the distance in metres. Dot colors:
   - **green** live reading, **yellow** stale/searching/backgrounded, **red** UWB lost the peer, **grey** disconnected (app closed, out of Wi-Fi/Bluetooth range).
   - The layout is rebuilt from distances only, so it can appear rotated or mirrored compared to the real room.
5. **Diagnostics** shows each peer's state, distance, whether direction is available, update rate, last-update age, errors and a live event log. Use it when something looks wrong.
6. **Record** logs a CSV (`timestamp, peer, status, distance, azimuth, rate`). Tap Stop, then the share button to AirDrop/save it.

## Suggested experiments
- Accuracy: place phones at 0.5 / 1 / 2 / 5 m with a tape measure; compare both phones' numbers (they should agree within ~10-20 cm).
- Walls: walk behind a wall or door, watch the dot go yellow/red and how fast it recovers.
- Orientation: phone flat, upright, in a pocket, face-down. Note when direction disappears.
- Dropout: force-quit the app on one phone; its dot should go grey on the others within a few seconds and recover when it rejoins (rejoin with the same code).
- Scale: add phones one at a time up to 8 and watch Diagnostics for NI errors; this finds the concurrent-session limit.

## Troubleshooting
- **Stuck on "searching"**: both phones must be foreground, unlocked, and within a few metres, roughly facing each other. Check Diagnostics > Log for "token from ..." and "running NI config" on both phones.
- **Nobody found**: Local Network permission denied (Settings > UWBDistance > Local Network), code mismatch, or Wi-Fi/Bluetooth off.
- **"Your team has no devices"** / signing errors: plug the phone in, select it as the destination, click Try Again in Signing.
- **App won't open after a week**: the free profile expired; re-run from Xcode.
