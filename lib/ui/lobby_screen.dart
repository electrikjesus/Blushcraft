import 'package:flutter/material.dart';

import '../../networking/game_transport.dart';
import '../../state/chat_controller.dart';
import '../../state/game_controller.dart';
import 'theme.dart';
import 'widgets/chat_panel.dart';
import 'widgets/game_mode_picker.dart';
import 'widgets/lobby_av_setup.dart';
import 'widgets/riskay_slider.dart';

class LobbyScreen extends StatelessWidget {
  const LobbyScreen({
    super.key,
    required this.controller,
    this.session,
    this.chat,
    required this.onLeave,
    required this.onStart,
  });

  final GameController controller;
  final GameSession? session;
  final ChatController? chat;
  final VoidCallback onLeave;
  final VoidCallback onStart;

  LocalDiscoverySession? get _local =>
      session is LocalDiscoverySession
          ? session as LocalDiscoverySession
          : null;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final local = _local;
    final chatCtrl = chat;
    final partnerConnected = session != null && session!.isConnected;
    final partnerName = state?.remotePlayer.name ?? 'partner';

    return BlushBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(controller.dryRun ? 'Practice lobby' : 'Lobby'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: onLeave,
          ),
          actions: [
            if (chatCtrl != null)
              ChatAppBarButton(
                chat: chatCtrl,
                partnerName: partnerName,
                enabled: partnerConnected && !controller.dryRun,
              ),
          ],
        ),
        body: Column(
          children: [
            if (chatCtrl != null)
              ChatInviteBanner(chat: chatCtrl, partnerName: partnerName),
            if (chatCtrl != null) ChatIncomingToast(chat: chatCtrl),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  controller,
                  ?session,
                  ?chatCtrl,
                ]),
                builder: (context, _) {
                  final s = controller.state ?? state;
                  final status = session?.status ?? s?.message ?? '';
                  final discovered = local?.discovered.entries.toList() ?? [];
                  final canEditRiskay = controller.isHost || controller.dryRun;
                  final canEditMode = canEditRiskay;
                  final partnerReady = controller.dryRun ||
                      (s != null && s.guest.id != 'pending-guest') ||
                      (session != null && session!.isConnected);
                  final name = s?.remotePlayer.name ?? partnerName;

                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text('Blushcraft', style: BlushTheme.display(32)),
                      const SizedBox(height: 8),
                      Text(
                        status,
                        style: BlushTheme.body(15, color: BlushTheme.inkMuted),
                      ),
                      const SizedBox(height: 28),
                      _playerTile(
                        'Host',
                        s?.host.name ?? controller.displayName,
                        highlighted: true,
                      ),
                      const SizedBox(height: 12),
                      _playerTile(
                        'Partner',
                        s?.guest.name ?? 'Waiting…',
                        highlighted:
                            s != null && s.guest.id != 'pending-guest',
                      ),
                      const SizedBox(height: 28),
                      GameModePicker(
                        value: s?.gameMode ?? controller.gameMode,
                        enabled: canEditMode,
                        onChanged: canEditMode
                            ? (m) => controller.setGameMode(m)
                            : (_) {},
                      ),
                      if (!canEditMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Host sets the game mode for this match.',
                            style: BlushTheme.body(
                              12,
                              color: BlushTheme.inkMuted,
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),
                      RiskaySlider(
                        value: s?.riskayLevel ?? controller.riskayLevel,
                        enabled: canEditRiskay,
                        onChanged: canEditRiskay
                            ? (v) => controller.setRiskayLevel(v)
                            : null,
                      ),
                      if (!canEditRiskay)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Host sets the Riskay level for this game.',
                            style: BlushTheme.body(
                              12,
                              color: BlushTheme.inkMuted,
                            ),
                          ),
                        ),
                      const SizedBox(height: 28),
                      LobbyAvSetup(
                        localPlayerId: controller.localPlayerId,
                        controller: controller,
                        session: session,
                      ),
                      if (local != null &&
                          !controller.isHost &&
                          !local.isConnected &&
                          discovered.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        Text('Local hosts', style: BlushTheme.display(20)),
                        const SizedBox(height: 8),
                        ...discovered.map(
                          (e) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(e.value),
                            trailing: ElevatedButton(
                              onPressed: () => local.connectTo(e.key),
                              child: const Text('Connect'),
                            ),
                          ),
                        ),
                      ],
                      if (chatCtrl != null &&
                          partnerReady &&
                          !controller.dryRun) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Optional chat needs both of you to Allow it first. '
                          'Photos stay on these two devices for this session.',
                          style: BlushTheme.body(
                            12,
                            color: BlushTheme.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: session?.isConnected != true
                              ? null
                              : () async {
                                  if (chatCtrl.status ==
                                      ChatConsentStatus.open) {
                                    await ChatPanel.open(
                                      context,
                                      chat: chatCtrl,
                                      partnerName: name,
                                    );
                                  } else {
                                    await ChatPanel.promptInvite(
                                      context,
                                      chat: chatCtrl,
                                      partnerName: name,
                                    );
                                  }
                                },
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: Text(
                            chatCtrl.status == ChatConsentStatus.open
                                ? 'Open chat'
                                : 'Invite to chat',
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      if (controller.isHost)
                        ElevatedButton(
                          onPressed: () {
                            if (!partnerReady) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Wait for your partner to join.',
                                  ),
                                ),
                              );
                              return;
                            }
                            onStart();
                          },
                          child: const Text('Start game'),
                        ),
                      if (!controller.isHost)
                        Text(
                          'Waiting for the host to start…',
                          textAlign: TextAlign.center,
                          style: BlushTheme.body(
                            14,
                            color: BlushTheme.inkMuted,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerTile(String role, String name, {bool highlighted = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted
            ? BlushTheme.cardFace
            : BlushTheme.creamDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? BlushTheme.rose : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: BlushTheme.blush,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: BlushTheme.body(16, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role,
                  style: BlushTheme.body(12, color: BlushTheme.inkMuted),
                ),
                Text(name, style: BlushTheme.body(17, weight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
