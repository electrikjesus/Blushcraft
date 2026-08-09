# <img src="web/icons/Icon-192.png" alt="" width="40" height="40" align="absmiddle"> Blushcraft

**Blushcraft** is a two-player fill-in-the-blank card game made for couples and close friends who want something more personal than trivia night. One player reads a Statement with a blank; the other plays a Choice from their hand. You read the finished line out loud, watch each other's reaction, and score a point when someone breaks first: a blush, a laugh, looking away, or "I can't believe you said that."

Rounds stay light or turn spicy with the **Riskay** slider. Choose **Romantic Partner** or **Fresh Start** decks. Play face to face over the same Wi‑Fi (no Google Play Services required), practice alone on one phone, or invite a partner online with a QR / paste invite. Game sync and reaction video stay between your devices, not on a Blushcraft server.

First to **5** Statement points wins and picks the prize.

## Round demo

Practice round in ~12 seconds: scroll the hand, submit, reveal, reaction check, score a point.

<p align="center">
  <img src="docs/screenshots/round-demo.gif" alt="Animated Blushcraft round demo" width="280" />
</p>

Store / Obtainium listing stills (pulled from the demo) live in [`docs/screenshots/store/`](docs/screenshots/store/). Regenerate with `tool/record_round_demo.py` then `./tool/extract_store_screenshots.sh` after recording a new demo. A social-ready `round-demo.mp4` is attached to GitHub Releases.

Built with **Flutter** (Android first, iOS-ready). Local multiplayer uses **mDNS + WebSocket** on the same Wi‑Fi. Online play uses **WebRTC + QR** so round data stays on the two phones.

## Features

- Host / Join local 2-player games on the same Wi‑Fi (works without Google Play Services)
- Host / Join online via WebRTC + data-channel QR / paste invites
- Practice mode on a single device
- **Game modes:** Romantic Partner, Fresh Start (BFF coming soon)
- **Riskay** slider (Innocent / Blush / Riskay) mixes card heat
- Statement blanks use one NP/gerund form so Choice cards fit consistently
- First to **5** points wins and picks a prize
- Optional reaction camera + mic (consent in lobby or in-game; privacy toggles)
- Phone layout expands the reaction camera strip with on-screen controls
- Mid-game reconnect if the local link drops briefly
- Share combos, results, and stats from the app
- Local win/loss and recent-combo stats
- Per-ABI + universal Android APKs (armeabi-v7a / arm64-v8a / x86_64)

## Requirements

- Flutter 3.22+ (Dart 3)
- Two Android devices for Host/Join (API 26+), same Wi‑Fi for Local
- Local network permission (Android 17+ / iOS Local Network)
- Camera + microphone permission for the optional reaction selfie/voice view (either can be muted in-app)

## Run

```bash
flutter pub get
flutter run
```

Practice without a second phone:

1. Open the app
2. Enter a name
3. Tap **Practice on this device**
4. Optionally set reaction camera/mic in the lobby
5. Start game and play both seats when prompted

## Two-device play

### Local (same Wi‑Fi)

1. Both players install/run the app and enter names
2. On **Play over → Local**, Player A taps **Host local**
3. Player B taps **Join local**, then **Connect** on the discovered host
4. Host taps **Start game**
5. Each round: pick a Choice, reveal and read aloud, reaction check, refill to 7
6. First to 5 Statement points wins and chooses a prize

### Online (QR / paste)

1. Switch **Play over → Online**
2. Host taps **Host online** and shows the invite QR (or Copy / Share the full invite text)
3. Guest taps **Join online**, scans or pastes the invite, then shows the answer QR
4. Host scans or pastes the **full** answer text and waits for **Connected** (keep both screens awake)
5. Continue in the lobby as with Local

Best on the same Wi‑Fi. See [docs/architecture-webrtc-qr.md](docs/architecture-webrtc-qr.md).

## Project layout

```
lib/
  data/          # cards.json / Fresh Start loader
  models/        # cards, game state, players, game modes
  networking/    # Nearby + WebRTC sessions + GameMessage protocol
  camera/        # reaction selfie controller
  state/         # GameController (host authority) + stats
  share/         # share_plus helpers
  ui/            # screens + widgets
assets/cards.json
assets/cards_fresh_start.json
```

## Cards

Source CSV: `Blush Card Game - Print Template - Blush Card Game - Print Template.csv`

Runtime decks:

- `assets/cards.json` — Romantic Partner (default + innocent + provocative)
- `assets/cards_fresh_start.json` — Fresh Start (same heat packs)

### Blank form (authoring rule)

Every statement blank is a single slot for a **noun phrase or gerund phrase** (a thing / moment / act)—the same shapes as Choice cards (`A slow dance…`, `Whispering something wicked.`, `a chaotic good playlist`).

**Prefer lead-ins like:** `about ___`, `of ___`, `is ___`, `like ___`, `at ___`, `by ___`, `for ___`, `with ___`, `during ___`, `involving ___`, `when it comes to ___`, `filled with ___`.

**Avoid:** bare infinitive after `to ___`, bare verb after `you` / `we` / `won't` / `and ___`, adjective-only slots (`incredibly ___`), and bare possessives (`Your ___`).

Statements with multiple blanks fill the first blank with the chosen Choice and show `…` for extras; prefer writing **one** blank when editing.

`fillWith` trims the choice, strips a trailing period, and lowercases the first letter when the blank is mid-sentence.

### Riskay slider

- **Innocent** (left) - classic blush deck + sweeter / softer cards
- **Blush** (center, default) - classic deck only
- **Riskay** (right) - classic blush deck + spicier / dirtier cards

The host can adjust this on the home screen and in the lobby before starting.

## Build Android APKs

Versioning is derived from git automatically:

- **versionCode** (`build-number`): `git rev-list --count HEAD`
- **versionName** (`build-name`): exact git tag on HEAD (optional leading `v` stripped), otherwise `0.1.<commit-count>`

```bash
chmod +x tool/build_apk.sh tool/git_version.sh
./tool/build_apk.sh
# → build/app/outputs/flutter-apk/app-release.apk              (universal)
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk    (phones)
# → build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
# → build/app/outputs/flutter-apk/app-x86_64-release.apk

# Inspect the computed version:
./tool/git_version.sh
```

Prefer the **arm64-v8a** split on modern phones (~1/3 the download of the fat APK). Use the universal `app-release.apk` when you need one file that covers all ABIs.

### Signed releases (GitHub Actions)

Pushing a `v*` tag builds signed universal + per-ABI APKs plus `app-debug.apk` and publishes a GitHub Release (same secret names as BumpDesk). See [docs/distribution.md](docs/distribution.md) and `keystore.properties.example`.

Local signed build: copy `keystore.properties.example` → `keystore.properties`, generate `keystore/blushcraft-release.jks`, then run `./tool/build_apk.sh`.

To cut a named release:

```bash
git tag v0.2.2
git push origin v0.2.2   # triggers Create Release workflow
```

Refresh media before tagging so the README stays current:

1. `flutter build web --release && python3 -m http.server 7357 --directory build/web`
2. `python3 tool/record_round_demo.py` (needs Playwright; writes `round-demo.gif` + temp `round-demo.mp4`)
3. `./tool/extract_store_screenshots.sh` to refresh Obtainium / store stills in `docs/screenshots/store/`
4. Upload `round-demo.mp4` to the GitHub Release for social posts (gitignored locally)

## Online play

**Local:** Nearby Connections (Bluetooth / Wi-Fi).

**Internet:** WebRTC + short data-channel QR / paste signaling so round data never leaves the two devices. Camera/mic attach after connect. See [docs/architecture-webrtc-qr.md](docs/architecture-webrtc-qr.md).

Later: Supabase or Cloudflare can replace QR for signaling only (optional TURN), without putting card/score sync in the cloud.

## License

[GNU General Public License v3.0](LICENSE) (GPLv3).
