/// ICE servers for WebRTC. STUN only in v1; TURN hooks for later.
class IceConfig {
  const IceConfig._();

  static const stunUrls = <String>[
    'stun:stun.l.google.com:19302',
    'stun:stun1.l.google.com:19302',
    'stun:stun.cloudflare.com:3478',
  ];

  /// Map suitable for [createPeerConnection].
  static Map<String, dynamic> peerConnectionConfig({
    List<Map<String, dynamic>>? turnServers,
  }) {
    final iceServers = <Map<String, dynamic>>[
      {'urls': stunUrls},
      ...?turnServers,
    ];
    return {
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };
  }
}
