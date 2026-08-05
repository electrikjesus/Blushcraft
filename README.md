# Blushcraft

**Blushcraft** is a two-player fill-in-the-blank card game made for couples and close friends who want something more personal than trivia night. One player reads a Statement with a blank; the other plays a Choice from their hand. You read the finished line out loud, watch each other's reaction, and score a point when someone breaks first: a blush, a laugh, looking away, or "I can't believe you said that."

Rounds stay light or turn spicy with the **Riskay** slider. Play face to face over Nearby Connections, practice alone on one phone, or invite a partner online with a QR code. Game sync and reaction video stay between your devices, not on a Blushcraft server.

First to **5** Statement points wins and picks the prize.

## Screenshots

<p align="center">
  <img src="docs/screenshots/home.png" alt="Home: name, Riskay slider, Nearby and Online play" width="200" />
  <img src="docs/screenshots/lobby.png" alt="Practice lobby ready to start" width="200" />
  <img src="docs/screenshots/play.png" alt="Round 1: statement, camera row, and choice hand" width="200" />
</p>

<p align="center">
  <img src="docs/screenshots/choice-selected.png" alt="Browsing Choice cards to submit" width="200" />
  <img src="docs/screenshots/reveal.png" alt="Reveal: filled statements ready to read aloud" width="200" />
  <img src="docs/screenshots/reaction.png" alt="Reaction check: who broke first" width="200" />
</p>

<p align="center">
  <img src="docs/screenshots/round-result.png" alt="Round result with point and share combo" width="200" />
</p>

## Round demo

Practice round in ~12 seconds: scroll the hand, submit, reveal, reaction check, score a point. Tap the preview for the full MP4.

<p align="center">
  <a href="docs/screenshots/round-demo.mp4">
    <img src="docs/screenshots/round-demo.gif" alt="Animated Blushcraft round demo" width="280" />
  </a>
</p>

<p align="center">
  <a href="docs/screenshots/round-demo.mp4"><strong>Play round-demo.mp4</strong></a>
</p>

Built with **Flutter** (Android first, iOS-ready). Local multiplayer uses Google **Nearby Connections** (Bluetooth / Wi-Fi). Online play uses **WebRTC + QR** so round data stays on the two phones.

## Features (v1)

- Host / Join local 2-player games (Nearby)
- Host / Join online via WebRTC + QR invite
- Practice mode on a single device
- **Riskay** slider (Innocent / Blush / Riskay) mixes card heat
- Statement + Choice decks (default / innocent / provocative packs)
- First to **5** points wins and picks a prize
- Reaction Check with front-camera + mic (privacy toggles for both)
- Mid-game reconnect if Nearby drops briefly
- Share combos, results, and stats from the app
- Local win/loss and recent-combo stats
- Universal Android APK (armeabi-v7a / arm64-v8a / x86_64)

## Requirements

- Flutter 3.22+ (Dart 3)
- Two Android phones for Host/Join (API 26+)
- **Location** and **Bluetooth** enabled (Nearby Connections requirement)
- Camera + microphone permission for the reaction selfie/voice view (either can be muted in-app)

## Run

```bash
flutter pub get
flutter run
```

Practice without a second phone:

1. Open the app
2. Enter a name
3. Tap **Practice on this device**
4. Start game and play both seats when prompted

## Two-device play

1. Both players install/run the app and enter names
2. Player A taps **Host a game** (keep Location + Bluetooth on)
3. Player B taps **Join a game**, then **Connect** on the discovered host
4. Host taps **Start game**
5. Each round: pick a Choice, reveal and read aloud, reaction check (who blushed / broke eye contact first), refill to 7
6. First to 5 Statement points wins and chooses a prize

## Project layout

```
lib/
  data/          # cards.json loader
  models/        # cards, game state, players
  networking/    # Nearby + WebRTC sessions + GameMessage protocol
  camera/        # reaction selfie controller
  state/         # GameController (host authority) + stats
  share/         # share_plus helpers
  ui/            # screens + widgets
assets/cards.json
```

## Cards

Source CSV: `Blush Card Game - Print Template - Blush Card Game - Print Template.csv`
Runtime deck: `assets/cards.json` (default + innocent + provocative packs)

Statements with multiple blanks fill the first blank with the chosen Choice and show `…` for extras.

### Riskay slider

- **Innocent** (left) - classic blush deck + sweeter / softer cards
- **Blush** (center, default) - classic deck only
- **Riskay** (right) - classic blush deck + spicier / dirtier cards

The host can adjust this on the home screen and in the lobby before starting.

## Build a universal Android APK

Versioning is derived from git automatically:

- **versionCode** (`build-number`): `git rev-list --count HEAD`
- **versionName** (`build-name`): exact git tag on HEAD (optional leading `v` stripped), otherwise `0.1.<commit-count>`

```bash
chmod +x tool/build_apk.sh tool/git_version.sh
./tool/build_apk.sh
# → build/app/outputs/flutter-apk/app-release.apk

# Inspect the computed version:
./tool/git_version.sh
```

Fat APK includes **armeabi-v7a**, **arm64-v8a**, and **x86_64**. Do not use `--split-per-abi` if you want one installable for devices and x86_64 emulators.

### Signed releases (GitHub Actions)

Pushing a `v*` tag builds signed `app-release.apk` + `app-debug.apk` and publishes a GitHub Release (same secret names as BumpDesk). See [docs/distribution.md](docs/distribution.md) and `keystore.properties.example`.

Local signed build: copy `keystore.properties.example` → `keystore.properties`, generate `keystore/blushcraft-release.jks`, then run `./tool/build_apk.sh`.

To cut a named release:

```bash
git tag v0.2.0
git push origin v0.2.0   # triggers Create Release workflow
```

Refresh `docs/screenshots/` (stills + `round-demo.mp4` / `.gif`) when the UI changes before tagging so the README stays current.

## Online play

**Local:** Nearby Connections (Bluetooth / Wi-Fi).

**Internet:** WebRTC + QR signaling so round data never leaves the two devices. See [docs/architecture-webrtc-qr.md](docs/architecture-webrtc-qr.md).

Later: Supabase or Cloudflare can replace QR for signaling only (optional TURN), without putting card/score sync in the cloud.

## License

[GNU General Public License v3.0](LICENSE) (GPLv3).
