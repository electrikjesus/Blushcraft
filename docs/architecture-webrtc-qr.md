# Online play architecture: WebRTC + QR (v1)

Status: **v1 in app** (QR signaling + data channel + WebRTC AV). **Local play** uses mDNS + WebSocket ([`LanGameSession`](../lib/networking/lan_game_session.dart)) and does not need Play Services or QR. Cloud signaling / TURN still later.

## Goal

Internet play **without a Blushcraft game server**. Round data (decks, hands, submissions, scores, AV) stays on the two phones. Pairing uses a **QR code or texted payload** for WebRTC signaling.

Same-Wi‑Fi play should use **Play over → Local** (auto discovery). Online QR/paste is for when devices are not on a shared LAN (or as a fallback).

Later: swap QR signaling for Supabase or Cloudflare **signaling-only** (and optional TURN) without rewriting `GameController`.

## Principles

1. **Host authority unchanged** - same `GameController` + `GameMessage` JSON as Nearby.
2. **Transport is pluggable** - `GameTransport`: Nearby | WebRTC+QR | future WebRTC+cloud signal.
3. **No round payloads in the cloud** in v1 - only optional public STUN; TURN later if needed.
4. **Privacy toggles** remain; online AV prefers WebRTC media tracks over Nearby JPEG/AAC.

## Pairing flow (v1)

```text
Host                         Guest
  |                            |
  | createPeerConnection       |
  | createDataChannel (only)   |
  | createOffer, lean ICE      |
  | encode offer -> QR/text ------> scan / paste
  |                            | setRemoteDescription(offer)
  |                            | createAnswer, lean ICE
  | scan / paste <------------- encode answer -> QR/text
  | setRemoteDescription       |
  |                            |
  |<===== RTCDataChannel open =====>|
  | Hello + StateSync (GameMessage) |
  | renegotiate A/V over DC ------->|
  |<===== WebRTC audio/video ======>|
```

Invites are **data-channel-only** so QR/paste strings stay short. Camera/mic are attached after connect and upgraded over the data channel. Pairing screens keep the display awake until Connected.

### QR payload

Versioned envelope, gzip + base64url (chunked multi-QR if needed):

```json
{
  "v": 1,
  "role": "offer|answer",
  "session": "<uuid>",
  "name": "Alex",
  "sdp": "<sdp>",
  "ice": ["candidate...", "..."],
  "pkg": "com.blushcraft.blushcraft"
}
```

- Prefer **bundled lean ICE** (host/srflx) in the offer/answer.
- Optional later deep link: `blushcraft://webrtc?...` (same payload).

### UX sketch

- **Host online** → show QR + share text; scan or paste guest answer.
- **Join online** → scan or paste invite → show answer QR for host to scan.
- Once the data channel opens → existing lobby / game UI.
- Honest copy: best on Wi-Fi; some mobile networks may need a later TURN update.
- Keep both phones awake on the QR screens until Connected.

## Module layout (proposed)

```text
lib/networking/
  game_transport.dart           # abstract send / messages / connection state
  nearby_game_session.dart      # existing; implement GameTransport
  webrtc/
    webrtc_qr_session.dart      # PeerConnection, data channel, media
    sdp_qr_codec.dart           # compress / chunk encode-decode
    ice_config.dart             # STUN now; TURN hooks later
    signal_channel.dart         # interface: QrSignalChannel | future cloud
  online_play_stub.dart         # evolve into OnlineInvite API
lib/ui/
  online_host_qr_screen.dart
  online_join_scan_screen.dart
```

### `GameTransport`

```dart
abstract class GameTransport {
  Stream<GameMessage> get messages;
  Stream<TransportConnectionState> get connectionStates;
  Future<void> send(GameMessage message);
  Future<void> dispose();
}
```

`GameController.sendMessage` → `transport.send`. Inbound → existing `onMessage`.

### AV

| Mode | Video / audio |
|------|----------------|
| Nearby (local) | Current PiP JPEG + AAC chunks |
| WebRTC (online) | Media tracks into the same PiP chrome |
| Privacy | Disable local tracks + `AvPrivacyMessage` on data channel |

## Connectivity expectations (v1)

| Situation | Likely result |
|-----------|----------------|
| Same Wi-Fi / friendly NATs | Works with public STUN |
| Carrier NAT on both phones | May fail without TURN |
| Large SDP | Mitigate with compression + chunked QR |

v1 ships **STUN-only**. Document failures; do not pretend all networks work.

## Later: Supabase / Cloudflare (signaling only)

Do **not** move game state to the cloud for play sync.

1. Host creates `sessionId`; posts offer to a Realtime channel or Durable Object.
2. QR shrinks to `https://…/join/<sessionId>` or `blushcraft://join/<id>`.
3. Guest pulls offer, posts answer; ICE trickle on the channel.
4. Same `RTCPeerConnection` + data channel as QR path.
5. Add TURN credentials from edge config when needed.

`QrSignalChannel` and `SupabaseSignalChannel` / `CloudflareSignalChannel` both implement `SignalChannel`. Game layer unchanged.

Optional “synced stats / backups” later is a **separate** feature from live play.

## Implementation order

1. Extract `GameTransport`; wrap Nearby with no UX change.
2. Add `flutter_webrtc` + QR generate/scan; `SdpQrCodec`.
3. Host/join QR screens; wire transport into lobby/game.
4. `GameMessage` over data channel (gameplay first).
5. WebRTC media → online reaction PiP.
6. Chunked QR, reconnect (new offer QR), STUN config polish.
7. Keep `SignalChannel` stub ready for Supabase/CF.

## Non-goals (this early online version)

- Supabase/Cloudflare in production
- Accounts or storing combos/scores in the cloud for live play
- Guaranteed connect on all mobile networks (no TURN yet)
- More than two players
