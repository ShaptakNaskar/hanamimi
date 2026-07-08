import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/listenbrainz_provider.dart';
import '../../providers/theme_provider.dart';
import '../../reco/listenbrainz.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';

/// Tier 2 consent dialog (ARCHITECTURE-RECOMMENDATIONS.md §4): the
/// plain-language notice IS the connect flow — there is no way to hand
/// over a token without reading what it means.
Future<void> showListenBrainzDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ListenBrainzDialog(),
  );
}

class _ListenBrainzDialog extends ConsumerStatefulWidget {
  const _ListenBrainzDialog();

  @override
  ConsumerState<_ListenBrainzDialog> createState() =>
      _ListenBrainzDialogState();
}

class _ListenBrainzDialogState extends ConsumerState<_ListenBrainzDialog> {
  final _token = TextEditingController();
  final _host = TextEditingController();
  var _showHost = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _token.dispose();
    _host.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final user = await ref
        .read(listenBrainzProvider.notifier)
        .connect(_token.text.trim(), host: _host.text);
    if (!mounted) return;
    if (user == null) {
      setState(() {
        _busy = false;
        _error = "Couldn't validate the token — check it (and the host)";
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      content: Text('Connected as $user 🎶',
          style: const TextStyle(fontFamily: 'Nunito')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final host = _host.text.trim().isEmpty
        ? ListenBrainz.defaultHost
        : _host.text.trim();
    return AlertDialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      title:
          Text('Connect ListenBrainz', style: AppText.rowSongTitle(theme)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This sends every song you listen to (title, artist, '
              'album, when) to $host and stores it there under your '
              'account. In return you get collaborative picks — Weekly '
              'Jams from listeners like you.\n\n'
              'ListenBrainz is open data and self-hostable; you can '
              'delete your listens there anytime. Disconnecting here '
              'stops all submissions immediately.',
              style: AppText.caption(theme),
            ),
            const SizedBox(height: Space.s3),
            TextField(
              controller: _token,
              autofocus: true,
              // Rebuild so "Agree & connect" enables as soon as a token
              // is typed/pasted.
              onChanged: (_) => setState(() {}),
              style: AppText.caption(theme),
              decoration: InputDecoration(
                labelText: 'User token',
                labelStyle: AppText.caption(theme),
                helperStyle: AppText.caption(theme)
                    .copyWith(color: theme.textMuted),
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            TextButton(
              onPressed: () => launchUrl(
                  Uri.parse('https://listenbrainz.org/settings/'),
                  mode: LaunchMode.externalApplication),
              child: Text('Get your token at listenbrainz.org →',
                  style: AppText.caption(theme)
                      .copyWith(color: theme.primary)),
            ),
            if (_showHost)
              TextField(
                controller: _host,
                style: AppText.caption(theme),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Instance URL (self-hosted)',
                  hintText: ListenBrainz.defaultHost,
                  labelStyle: AppText.caption(theme),
                  border: const OutlineInputBorder(),
                ),
              )
            else
              TextButton(
                onPressed: () => setState(() => _showHost = true),
                child: Text('Use a self-hosted instance…',
                    style: AppText.caption(theme)
                        .copyWith(color: theme.textMuted)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: AppText.rowSongTitle(theme)
                  .copyWith(color: theme.textMuted)),
        ),
        TextButton(
          onPressed:
              _busy || _token.text.trim().isEmpty ? null : _connect,
          child: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: theme.primary))
              : Text('Agree & connect',
                  style: AppText.rowSongTitle(theme)
                      .copyWith(color: theme.primary)),
        ),
      ],
    );
  }
}
