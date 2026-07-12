import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../date/date_room.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/shared/app_toast.dart';

/// Long-Distance Date Mode (3.0 #6): create or join a two-person room,
/// then share what you're playing — both players move in lockstep and
/// wait for each other's buffers. No accounts, no chat, just a code.
void showDateRoomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _DateRoomSheetBody(),
  );
}

class _DateRoomSheetBody extends ConsumerStatefulWidget {
  const _DateRoomSheetBody();

  @override
  ConsumerState<_DateRoomSheetBody> createState() =>
      _DateRoomSheetBodyState();
}

class _DateRoomSheetBodyState extends ConsumerState<_DateRoomSheetBody> {
  final _codeField = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _codeField.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// One line describing the room: who's leading, who's in step, and
  /// whether we've wandered off on our own.
  String _statusText(DateRoomState room) {
    if (!room.partnerJoined) return 'waiting for someone to join...';
    if (!room.partnerOnline) return 'partner stepped away';
    final locked = room.isDj ? room.partnerFollowing : room.following;
    if (room.partnerStalled && locked) {
      return 'buffering — holding for each other';
    }
    if (room.pausedForPartner) return 'catching up together...';
    if (room.isDj) {
      return room.partnerFollowing
          ? 'you\'re the DJ · in step ♪'
          : 'you\'re the DJ · they\'re listening solo';
    }
    if (room.solo) return 'listening solo — rejoin any time';
    return 'following the DJ ♪';
  }

  void _toast(String message) {
    if (!mounted) return;
    // Root-overlay toast, not a SnackBar — SnackBars render in the
    // Scaffold behind this modal sheet, so the message was unreadable
    // (user-reported).
    showAppToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final room = ref.watch(dateRoomProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4,
            Space.s4 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Long-distance date 💞',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s2),
            if (!room.inRoom) ...[
              Text(
                  'Listen together, perfectly in step. One of you creates '
                  'a room, the other types the code. Online songs only — '
                  'local files can\'t travel.',
                  style: AppText.caption(theme)),
              const SizedBox(height: Space.s4),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final ok = await ref
                              .read(dateRoomProvider.notifier)
                              .createRoom();
                          if (!ok) _toast('Could not create a room');
                        }),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create a room'),
              ),
              const SizedBox(height: Space.s4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeField,
                      maxLength: 6,
                      textCapitalization: TextCapitalization.characters,
                      style: AppText.body(theme)
                          .copyWith(letterSpacing: 4),
                      decoration: InputDecoration(
                        labelText: 'Room code',
                        counterText: '',
                        labelStyle: AppText.caption(theme),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  FilledButton(
                    onPressed: _busy || _codeField.text.trim().length != 6
                        ? null
                        : () => _run(() async {
                              final ok = await ref
                                  .read(dateRoomProvider.notifier)
                                  .joinRoom(_codeField.text);
                              if (!ok) {
                                _toast(ref.read(dateRoomProvider).error ??
                                    'Could not join');
                              }
                            }),
                    child: const Text('Join'),
                  ),
                ],
              ),
            ] else ...[
              // In a room.
              Center(
                child: Column(
                  children: [
                    Text('room code', style: AppText.caption(theme)),
                    const SizedBox(height: Space.s1),
                    InkWell(
                      borderRadius: BorderRadius.circular(Radii.md),
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: room.code!));
                        _toast('Code copied — send it to them 💌');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Space.s4, vertical: Space.s2),
                        decoration: BoxDecoration(
                          color: theme.background,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: theme.divider),
                        ),
                        child: Text(room.code!,
                            style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 8,
                                color: theme.primary)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Space.s4),
              Row(
                children: [
                  Icon(
                    room.partnerOnline
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 16,
                    color: room.partnerOnline
                        ? theme.primary
                        : theme.textMuted,
                  ),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    child: Text(
                      _statusText(room),
                      style: AppText.caption(theme),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s4),
              // A solo listener snaps back to the DJ's live spot.
              if (room.solo)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() =>
                          ref.read(dateRoomProvider.notifier).rejoin()),
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Rejoin the DJ'),
                ),
              if (room.solo) const SizedBox(height: Space.s2),
              // The DJ shares/re-shares their queue; a follower can grab
              // the DJ chair to make their own playback lead the room.
              if (room.isDj)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final err = await ref
                                .read(dateRoomProvider.notifier)
                                .shareCurrentQueue();
                            _toast(err ?? 'Sharing what you\'re playing 🌸');
                          }),
                  icon: const Icon(Icons.queue_music_rounded, size: 18),
                  label: Text(room.shared
                      ? 'Re-share what I\'m playing'
                      : 'Share what I\'m playing'),
                )
              else
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() =>
                          ref.read(dateRoomProvider.notifier).takeOver()),
                  icon: const Icon(Icons.headphones_rounded, size: 18),
                  label: const Text('Take over as DJ'),
                ),
              const SizedBox(height: Space.s2),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () =>
                        _run(() => ref.read(dateRoomProvider.notifier).leave()),
                icon: Icon(Icons.logout_rounded,
                    size: 16, color: theme.textMuted),
                label: Text('Leave the room',
                    style: AppText.caption(theme)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
