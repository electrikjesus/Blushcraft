# Blushcraft

A two-player, blush-inducing card game for romantic and playful moments.

Built with **Flutter** (Android first, iOS-ready). Local multiplayer syncs over Google **Nearby Connections** (Bluetooth / Wi‑Fi). Online play uses **WebRTC + QR** so round data stays on the two phones.

## Features (v1)

- Host / Join local 2-player games (Nearby)
- Host / Join online via WebRTC + QR invite
- Practice mode on a single device
- **Riskay** slider (Innocent ↔ Blush ↔ Riskay) mixes card heat
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
5. Each round: pick a Choice → reveal & read aloud → reaction check (who blushed / broke eye contact first) → refill to 7  
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

- **Innocent** (left) — classic blush deck + sweeter / softer cards  
- **Blush** (center, default) — classic deck only  
- **Riskay** (right) — classic blush deck + spicier / dirtier cards  

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

## Online play

**Local:** Nearby Connections (Bluetooth / Wi‑Fi).

**Internet:** WebRTC + QR signaling so round data never leaves the two devices. See [docs/architecture-webrtc-qr.md](docs/architecture-webrtc-qr.md).

Later: Supabase or Cloudflare can replace QR for signaling only (optional TURN), without putting card/score sync in the cloud.

## License

Private / unreleased — Blushcraft.
