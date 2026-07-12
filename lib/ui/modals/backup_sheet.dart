import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../backup/backup_service.dart';
import '../../backup/passphrase_backup.dart';
import '../../providers/library_provider.dart';
import '../../providers/online_settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/shared/app_toast.dart';

/// Backup & restore (3.0 #8). Tier 0: a local ZIP — no server, works
/// offline, both editions. Convenience tier (plus): the same bundle
/// encrypted client-side and parked on the backend under a
/// phrase-derived id — type the phrase on a new device and everything
/// comes back, leaderboard identity included.
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
  static const _phraseKey = 'backup_phrase';

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
      _toast(e is BackupFormatException ? e.message : 'That didn\'t work: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportZip() => _guarded(() async {
        final bytes = await _bundle();
        final stamp = DateTime.now().toIso8601String().substring(0, 10);
        final name = 'hanamimi-backup-$stamp.zip';
        if (Platform.isAndroid) {
          // SAF save dialogs are flaky through file_selector — the share
          // sheet reaches Files/Drive/anything and always works.
          final dir = await getTemporaryDirectory();
          final f = File('${dir.path}/$name');
          await f.writeAsBytes(bytes, flush: true);
          await SharePlus.instance.share(ShareParams(
              files: [XFile(f.path, mimeType: 'application/zip')]));
        } else {
          final location = await getSaveLocation(
              suggestedName: name,
              acceptedTypeGroups: const [
                XTypeGroup(label: 'ZIP', extensions: ['zip'])
              ]);
          if (location == null) return;
          await File(location.path).writeAsBytes(bytes, flush: true);
          _toast('Backup saved 🌸');
        }
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
          onlineAllowed: ref.read(onlineEnabledProvider),
        );
        ref.invalidate(libraryProvider);
        _toast(summary.describe());
      });

  Future<void> _cloudBackup() => _guarded(() async {
        final prefs = ref.read(sharedPrefsProvider);
        var phrase = prefs.getString(_phraseKey);
        final isNew = phrase == null;
        phrase ??= PassphraseBackup.generatePhrase();
        final ok =
            await PassphraseBackup.upload(await _bundle(), phrase, null);
        if (!ok) {
          _toast('Upload failed — check your connection');
          return;
        }
        await prefs.setString(_phraseKey, phrase);
        if (isNew && mounted) {
          await _showPhraseDialog(phrase);
        } else {
          _toast('Cloud backup updated 🌸');
        }
      });

  Future<void> _showPhraseDialog(String phrase) async {
    final theme = ref.read(currentThemeProvider);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg)),
        title: Text('Your recovery phrase',
            style: AppText.rowSongTitle(theme)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'These 8 words are the ONLY key to your backup. Write '
                'them down somewhere safe — they can\'t be recovered, '
                'not even by us (that\'s the point).',
                style: AppText.caption(theme)),
            const SizedBox(height: Space.s3),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Space.s3),
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: theme.divider),
              ),
              child: SelectableText(phrase,
                  style: AppText.body(theme).copyWith(height: 1.6)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: phrase)),
            child: Text('Copy',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('I wrote it down',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreFromPhrase() async {
    final theme = ref.read(currentThemeProvider);
    final controller = TextEditingController();
    final phrase = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg)),
        title:
            Text('Restore from phrase', style: AppText.rowSongTitle(theme)),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 3,
          style: AppText.body(theme),
          decoration: InputDecoration(
            labelText: 'Your 8 recovery words',
            labelStyle: AppText.caption(theme),
            border: const OutlineInputBorder(),
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
            onPressed: () =>
                Navigator.of(context).pop(controller.text),
            child: Text('Restore',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.primary)),
          ),
        ],
      ),
    );
    if (phrase == null || phrase.trim().isEmpty) return;

    await _guarded(() async {
      final Uint8List? bundle;
      try {
        bundle = await PassphraseBackup.download(phrase, null);
      } catch (_) {
        _toast('Wrong phrase — check the words and try again');
        return;
      }
      if (bundle == null) {
        _toast('No backup found for that phrase');
        return;
      }
      final summary = await BackupService.importBundle(
        bundle,
        prefs: ref.read(sharedPrefsProvider),
        repo: await ref.read(libraryRepositoryProvider.future),
        onlineAllowed: ref.read(onlineEnabledProvider),
      );
      // Remember the phrase: future "back up now" continues this blob.
      await ref
          .read(sharedPrefsProvider)
          .setString(_phraseKey, PassphraseBackup.normalizePhrase(phrase));
      ref.invalidate(libraryProvider);
      _toast(summary.describe());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final hasCloud =
        ref.watch(sharedPrefsProvider).getString(_phraseKey) != null;

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
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, Space.s4),
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
                'History, stats, playlists, favorites, settings and your '
                'leaderboard identity — in one file.',
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
            Divider(height: Space.s6, color: theme.divider),
            Text('CLOUD (ENCRYPTED)', style: AppText.sectionLabel(theme)),
            tile(
              icon: Icons.cloud_upload_outlined,
              title: hasCloud ? 'Update cloud backup' : 'Create cloud backup',
              subtitle: hasCloud
                  ? 'Re-encrypts and replaces your existing blob'
                  : 'Encrypted on this device; you get an 8-word key. '
                      'The server only ever sees ciphertext',
              onTap: _cloudBackup,
            ),
            tile(
              icon: Icons.cloud_download_outlined,
              title: 'Restore from phrase',
              subtitle: 'Type the 8 words from your old device',
              onTap: _restoreFromPhrase,
            ),
          ],
        ),
      ),
    );
  }
}
