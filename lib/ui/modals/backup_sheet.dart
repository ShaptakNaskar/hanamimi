import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../backup/backup_service.dart';
import '../../providers/library_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/shared/app_toast.dart';

/// Backup & restore (3.0 #8), Tier 0: a local ZIP — no server, works
/// offline. History, playlists, favorites and settings, stored as
/// identity snapshots so a restore re-links against a freshly scanned
/// library even when every file path changed.
void showBackupSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _BackupSheetBody(),
  );
}

class _BackupSheetBody extends ConsumerStatefulWidget {
  const _BackupSheetBody();

  @override
  ConsumerState<_BackupSheetBody> createState() => _BackupSheetBodyState();
}

class _BackupSheetBodyState extends ConsumerState<_BackupSheetBody> {
  var _busy = false;

  void _toast(String message) {
    if (!mounted) return;
    // Root-overlay toast — SnackBars hide behind the modal sheet.
    showAppToast(context, message);
  }

  Future<Uint8List> _bundle() async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    return BackupService.buildBundle(
        prefs: ref.read(sharedPrefsProvider), repo: repo);
  }

  Future<void> _guarded(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (e) {
      _toast(
          e is BackupFormatException ? e.message : 'That didn\'t work: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportZip() => _guarded(() async {
        final bytes = await _bundle();
        final stamp = DateTime.now().toIso8601String().substring(0, 10);
        final name = 'hanamimi-backup-$stamp.zip';
        // SAF save dialogs are flaky; the share sheet reaches
        // Files/Drive/anything and always works.
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(ShareParams(
            files: [XFile(f.path, mimeType: 'application/zip')]));
      });

  Future<void> _importZip() => _guarded(() async {
        final file = await openFile(acceptedTypeGroups: const [
          XTypeGroup(label: 'ZIP', extensions: ['zip'])
        ]);
        if (file == null) return;
        final summary = await BackupService.importBundle(
          await file.readAsBytes(),
          prefs: ref.read(sharedPrefsProvider),
          repo: await ref.read(libraryRepositoryProvider.future),
        );
        ref.invalidate(libraryProvider);
        _toast(summary.describe());
      });

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);

    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) =>
        ListTile(
          enabled: !_busy,
          leading: Icon(icon, size: 20, color: theme.textMuted),
          title: Text(title, style: AppText.rowSongTitle(theme)),
          subtitle: Text(subtitle, style: AppText.caption(theme)),
          onTap: onTap,
        );

    return SafeArea(
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Backup & restore',
                      style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: theme.textPrimary)),
                ),
                if (_busy)
                  SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: theme.primary)),
              ],
            ),
            const SizedBox(height: Space.s2),
            Text(
                'History, playlists, favorites and settings — in one file. '
                'No server involved.',
                style: AppText.caption(theme)),
            const SizedBox(height: Space.s3),
            tile(
              icon: Icons.archive_outlined,
              title: 'Export backup (.zip)',
              subtitle: 'A local file. No server involved',
              onTap: _exportZip,
            ),
            tile(
              icon: Icons.unarchive_outlined,
              title: 'Import backup (.zip)',
              subtitle: 'Merges into this device — nothing is deleted',
              onTap: _importZip,
            ),
          ],
        ),
      ),
    );
  }
}
