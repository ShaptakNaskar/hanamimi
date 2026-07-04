import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';
import '../../providers/update_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../utils/format_bytes.dart';

/// "Update available" dialog: changelog + in-app download with a live
/// progress bar, then hands the APK to the system installer (the app
/// reopens itself after Android swaps the package).
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    builder: (_) => _UpdateDialog(update: update),
  );
}

class _UpdateDialog extends ConsumerStatefulWidget {
  const _UpdateDialog({required this.update});

  final AppUpdate update;

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

enum _Phase { idle, downloading, installing, failed }

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  _Phase _phase = _Phase.idle;
  double _progress = 0;

  Future<void> _start() async {
    // Unknown-sources permission first — otherwise the installer
    // silently bounces.
    if (!await UpdaterChannel.canInstall()) {
      await UpdaterChannel.openInstallPerm();
      if (!await UpdaterChannel.canInstall()) return;
    }
    setState(() => _phase = _Phase.downloading);
    try {
      String? path;
      await for (final p in downloadUpdate(widget.update, (f) => path = f)) {
        if (!mounted) return;
        setState(() => _progress = p);
      }
      if (path == null) throw Exception('download incomplete');
      setState(() => _phase = _Phase.installing);
      final ok = await UpdaterChannel.install(path!);
      if (!ok && mounted) setState(() => _phase = _Phase.failed);
      // On success Android's installer takes over; nothing left to do.
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final update = widget.update;

    return AlertDialog(
      backgroundColor: theme.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      title: Text('Update available ✨', style: AppText.rowSongTitle(theme)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${update.versionName} · ${formatBytes(update.sizeBytes)}',
              style: AppText.caption(theme).copyWith(color: theme.primary),
            ),
            const SizedBox(height: Space.s2),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  update.changelog.isEmpty
                      ? 'No release notes.'
                      : update.changelog,
                  style: AppText.caption(theme),
                ),
              ),
            ),
            if (_phase == _Phase.downloading ||
                _phase == _Phase.installing) ...[
              const SizedBox(height: Space.s3),
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.pill),
                child: LinearProgressIndicator(
                  value: _phase == _Phase.installing ? null : _progress,
                  minHeight: 6,
                  color: theme.primary,
                  backgroundColor: theme.divider.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: Space.s1),
              Text(
                _phase == _Phase.installing
                    ? 'Opening installer…'
                    : '${(_progress * 100).toStringAsFixed(0)} %',
                style: AppText.caption(theme),
              ),
            ],
            if (_phase == _Phase.failed) ...[
              const SizedBox(height: Space.s2),
              Text("Couldn't update — try again later",
                  style: AppText.caption(theme)
                      .copyWith(color: theme.accent)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Later',
              style: AppText.rowSongTitle(theme)
                  .copyWith(color: theme.textMuted)),
        ),
        TextButton(
          onPressed: _phase == _Phase.downloading ||
                  _phase == _Phase.installing
              ? null
              : _start,
          child: Text(_phase == _Phase.failed ? 'Retry' : 'Update',
              style: AppText.rowSongTitle(theme)
                  .copyWith(color: theme.primary)),
        ),
      ],
    );
  }
}
